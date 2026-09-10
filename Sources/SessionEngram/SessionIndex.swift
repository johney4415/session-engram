import Foundation

/// Scans both providers and keeps a parse cache so repeat runs stay instant.
///
/// Parsing every transcript means reading ~100MB of JSONL, which is quick but not
/// free. A transcript is re-parsed only when its size or modification date changed.
struct SessionIndex: Sendable {
    struct Entry: Codable, Sendable {
        var modified: Date
        var size: Int
        var record: SessionRecord
    }

    private struct CacheFile: Codable {
        var schema: Int
        var entries: [String: Entry]
    }

    /// Bump when `SessionRecord` changes shape, so stale caches are discarded.
    static let schema = 2

    var claude: ClaudeScanner
    var codex: CodexScanner
    var cacheURL: URL

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheURL: URL? = nil
    ) {
        claude = ClaudeScanner(home: home)
        codex = CodexScanner(home: home)
        self.cacheURL = cacheURL ?? Self.defaultCacheURL(home: home)
    }

    static func defaultCacheURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Caches/dev.johney4415.session-engram/index.json")
    }

    func load() -> [SessionRecord] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data),
              cache.schema == Self.schema
        else { return [] }
        return SessionMerger.merge(cache.entries.values.map(\.record))
    }

    /// Re-reads both transcript trees, reusing cached parses where nothing changed.
    func scan() async -> [SessionRecord] {
        let index = self
        return await Task.detached(priority: .userInitiated) { index.scanSync() }.value
    }

    /// Synchronous scan, parsing transcripts across all cores.
    func scanSync() -> [SessionRecord] {
        let cached = loadEntries()
        let names = codex.threadNames()

        let claudeScanner = claude
        let codexScanner = codex
        let claudeFiles = claudeScanner.transcripts()
        let codexFiles = codexScanner.transcripts()

        let urls: [URL] = claudeFiles + codexFiles.map(\.url)
        let work: [@Sendable () -> SessionRecord?] = claudeFiles.map { url in
            { @Sendable in claudeScanner.record(for: url) }
        } + codexFiles.map { file in
            { @Sendable in codexScanner.record(for: file.url, archived: file.archived, threadNames: names) }
        }

        let sink = ResultSink(count: work.count)
        DispatchQueue.concurrentPerform(iterations: work.count) { i in
            sink.set(i, Self.entry(for: urls[i], cached: cached, parse: work[i]))
        }

        let entries = sink.values()
        save(entries)
        return SessionMerger.merge(entries.map(\.record))
    }

    /// Collects results from `concurrentPerform` without sharing mutable state.
    private final class ResultSink: @unchecked Sendable {
        private var storage: [Entry?]
        private let lock = NSLock()

        init(count: Int) { storage = Array(repeating: nil, count: count) }

        func set(_ index: Int, _ value: Entry?) {
            lock.lock()
            storage[index] = value
            lock.unlock()
        }

        func values() -> [Entry] {
            lock.lock()
            defer { lock.unlock() }
            return storage.compactMap { $0 }
        }
    }

    private static func entry(
        for url: URL,
        cached: [String: Entry],
        parse: () -> SessionRecord?
    ) -> Entry? {
        let size = FileMetrics.size(of: url)
        let modified = FileMetrics.modified(at: url)
        if let hit = cached[url.path],
           hit.size == size,
           abs(hit.modified.timeIntervalSince(modified)) < 1 {
            return hit
        }
        guard let record = parse() else { return nil }
        return Entry(modified: modified, size: size, record: record)
    }

    private func loadEntries() -> [String: Entry] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data),
              cache.schema == Self.schema
        else { return [:] }
        return cache.entries
    }

    private func save(_ entries: [Entry]) {
        let cache = CacheFile(
            schema: Self.schema,
            entries: Dictionary(entries.map { ($0.record.transcriptPath, $0) }) { _, last in last }
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Drops cached parses so the next scan rebuilds from disk.
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
