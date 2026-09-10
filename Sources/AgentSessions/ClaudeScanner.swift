import Foundation

/// Finds Claude Code transcripts under `~/.claude/projects`.
///
/// Layout: `<projects>/<escaped-cwd>/<session-uuid>.jsonl`, with an optional
/// `<escaped-cwd>/<session-uuid>/subagents/*.jsonl` directory holding the
/// subagent transcripts that belong to the same session.
struct ClaudeScanner: Sendable {
    var root: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        root = home.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }

    init(root: URL) {
        self.root = root
    }

    func transcripts() -> [URL] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return projectDirs.flatMap { dir -> [URL] in
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let entries = try? fm.contentsOfDirectory(
                      at: dir,
                      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                      options: [.skipsHiddenFiles]
                  )
            else { return [] }
            return entries.filter { $0.pathExtension == "jsonl" }
        }
    }

    func record(for url: URL) -> SessionRecord? {
        let sessionID = url.deletingPathExtension().lastPathComponent
        var cwd = ""
        // Kept as text and parsed once at the end; parsing every line would dominate the scan.
        var latestStamp: String?
        var messageCount = 0
        var candidates: [String] = []

        do {
            try TranscriptReader.forEachObject(at: url) { object in
                if cwd.isEmpty, let value = object["cwd"] as? String { cwd = value }
                if let stamp = object["timestamp"] as? String { latestStamp = stamp }
                guard object["type"] as? String == "user",
                      (object["isMeta"] as? Bool) != true,
                      let message = object["message"] as? [String: Any]
                else { return true }

                let text = TranscriptReader.text(from: message["content"])
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
                messageCount += 1
                if candidates.count < 6 { candidates.append(text) }
                return true
            }
        } catch {
            return nil
        }

        let subagents = url.deletingPathExtension()
        let hasSubagents = FileManager.default.fileExists(atPath: subagents.path)

        return SessionRecord(
            provider: .claude,
            sessionID: sessionID,
            title: TitleBuilder.title(from: candidates) ?? TitleBuilder.fallback,
            cwd: cwd,
            updatedAt: latestStamp.flatMap(TranscriptReader.date(from:)) ?? FileMetrics.modified(at: url),
            messageCount: messageCount,
            byteCount: FileMetrics.size(of: url) + (hasSubagents ? directorySize(subagents) : 0),
            transcriptPath: url.path,
            auxiliaryPaths: hasSubagents ? [subagents.path] : [],
            isArchived: false
        )
    }

    private func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total = 0
        for case let child as URL in enumerator {
            total += FileMetrics.size(of: child)
        }
        return total
    }
}
