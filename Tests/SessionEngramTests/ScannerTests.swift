import Foundation
import Testing
@testable import SessionEngram

/// A throwaway directory tree that mimics the on-disk layout of both CLIs.
private struct Fixture {
    let root: URL

    init() throws {
        root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "session-engram-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ lines: [String], to relativePath: String) throws -> URL {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Test func readsClaudeTranscript() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    _ = try fixture.write([
        #"{"type":"user","isMeta":true,"cwd":"/Users/x/work","message":{"content":"boot"}}"#,
        #"{"type":"user","cwd":"/Users/x/work","timestamp":"2026-09-10T02:39:00.123Z","message":{"content":"<command-name>/clear</command-name>"}}"#,
        #"{"type":"user","timestamp":"2026-09-10T02:40:00.000Z","message":{"content":[{"type":"text","text":"幫我解 merge conflict"}]}}"#,
        #"{"type":"assistant","timestamp":"2026-09-10T02:41:00.000Z","message":{"content":[{"type":"text","text":"好"}]}}"#,
        #"{"type":"user","timestamp":"2026-09-10T02:42:00.000Z","message":{"content":"commit"}}"#,
        "not json at all",
    ], to: ".claude/projects/-Users-x-work/abc-123.jsonl")

    let scanner = ClaudeScanner(root: fixture.root.appending(path: ".claude/projects"))
    let files = scanner.transcripts()
    #expect(files.count == 1)

    let record = try #require(scanner.record(for: files[0]))
    #expect(record.provider == .claude)
    #expect(record.sessionID == "abc-123")
    #expect(record.cwd == "/Users/x/work")
    #expect(record.title == "幫我解 merge conflict")
    // The meta turn and the slash command are skipped; the real prompt and "commit" count.
    #expect(record.messageCount == 2)
    #expect(record.updatedAt == TranscriptReader.date(from: "2026-09-10T02:42:00.000Z"))
    #expect(record.auxiliaryPaths.isEmpty)
}

@Test func includesClaudeSubagentDirectory() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    _ = try fixture.write(
        [#"{"type":"user","cwd":"/w","message":{"content":"parent task"}}"#],
        to: ".claude/projects/-w/sess.jsonl"
    )
    _ = try fixture.write(
        [#"{"type":"user","message":{"content":"child"}}"#],
        to: ".claude/projects/-w/sess/subagents/agent-1.jsonl"
    )

    let scanner = ClaudeScanner(root: fixture.root.appending(path: ".claude/projects"))
    let files = scanner.transcripts()
    // The subagent transcript is not its own row.
    #expect(files.count == 1)

    let record = try #require(scanner.record(for: files[0]))
    #expect(record.auxiliaryPaths.count == 1)
    #expect(record.allPaths.count == 2)
    #expect(record.byteCount > 0)
}

@Test func readsCodexRolloutAndPrefersThreadName() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    _ = try fixture.write([
        #"{"timestamp":"2026-09-09T14:45:00.000Z","type":"session_meta","payload":{"session_id":"019f-abc","cwd":"/Users/x/work"}}"#,
        #"{"timestamp":"2026-09-09T14:46:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"查一下這個問題"}}"#,
        #"{"timestamp":"2026-09-09T14:47:00.000Z","type":"event_msg","payload":{"type":"token_count"}}"#,
    ], to: "sessions/2026/09/09/rollout-2026-09-09T14-45-00-019f-abc.jsonl")

    _ = try fixture.write(
        [#"{"id":"019f-abc","thread_name":"排查 Word 字體輸出問題"}"#],
        to: "session_index.jsonl"
    )

    let scanner = CodexScanner(
        sessionsRoot: fixture.root.appending(path: "sessions"),
        archivedRoot: fixture.root.appending(path: "archived_sessions"),
        indexFile: fixture.root.appending(path: "session_index.jsonl")
    )
    let files = scanner.transcripts()
    #expect(files.count == 1)

    let record = try #require(
        scanner.record(for: files[0].url, archived: false, threadNames: scanner.threadNames())
    )
    #expect(record.sessionID == "019f-abc")
    #expect(record.title == "排查 Word 字體輸出問題")
    #expect(record.messageCount == 1)
    #expect(record.isArchived == false)
}

@Test func fallsBackToResponseItemsForExecRuns() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    // `codex exec` runs record no `event_msg` prompts at all.
    _ = try fixture.write([
        #"{"timestamp":"2026-09-08T09:00:00.000Z","type":"session_meta","payload":{"session_id":"exec-1","cwd":"/w"}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<recommended_plugins>Airtable</recommended_plugins>"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Review PR #17120 of this repository"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]}}"#,
    ], to: "sessions/2026/09/08/rollout-2026-09-08T09-00-00-exec-1.jsonl")

    let scanner = CodexScanner(
        sessionsRoot: fixture.root.appending(path: "sessions"),
        archivedRoot: fixture.root.appending(path: "archived_sessions"),
        indexFile: fixture.root.appending(path: "missing.jsonl")
    )
    let files = scanner.transcripts()
    let record = try #require(
        scanner.record(for: files[0].url, archived: false, threadNames: [:])
    )
    #expect(record.title == "Review PR #17120 of this repository")
    #expect(record.messageCount == 1)
}

@Test func marksArchivedCodexSessions() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    _ = try fixture.write([
        #"{"timestamp":"2026-07-27T08:30:00.000Z","type":"session_meta","payload":{"session_id":"old-1","cwd":"/w"}}"#,
    ], to: "archived_sessions/rollout-2026-07-27T08-30-21-old-1.jsonl")

    let scanner = CodexScanner(
        sessionsRoot: fixture.root.appending(path: "sessions"),
        archivedRoot: fixture.root.appending(path: "archived_sessions"),
        indexFile: fixture.root.appending(path: "session_index.jsonl")
    )
    let files = scanner.transcripts()
    #expect(files.count == 1)
    #expect(files[0].archived == true)

    let record = try #require(scanner.record(for: files[0].url, archived: true, threadNames: [:]))
    #expect(record.isArchived == true)
    #expect(record.isResumable == false)
}

@Test func indexCachesParsedRecords() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    _ = try fixture.write(
        [#"{"type":"user","cwd":"/w","timestamp":"2026-09-10T01:00:00.000Z","message":{"content":"第一個任務"}}"#],
        to: ".claude/projects/-w/one.jsonl"
    )

    let cacheURL = fixture.root.appending(path: "cache/index.json")
    let index = SessionIndex(home: fixture.root, cacheURL: cacheURL)

    let scanned = await index.scan()
    #expect(scanned.count == 1)
    #expect(FileManager.default.fileExists(atPath: cacheURL.path))

    // A second process reads the same records without touching the transcripts.
    let reloaded = SessionIndex(home: fixture.root, cacheURL: cacheURL).load()
    #expect(reloaded.map(\.title) == ["第一個任務"])

    index.clearCache()
    #expect(SessionIndex(home: fixture.root, cacheURL: cacheURL).load().isEmpty)
}

@Test func removerMovesEveryPathBelongingToASession() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    let main = try fixture.write(
        [#"{"type":"user","message":{"content":"x"}}"#],
        to: "projects/-w/sess.jsonl"
    )
    let aux = try fixture.write(
        [#"{"type":"user","message":{"content":"y"}}"#],
        to: "projects/-w/sess/subagents/a.jsonl"
    )

    let record = SessionRecord(
        provider: .claude,
        sessionID: "sess",
        title: "x",
        cwd: "/w",
        updatedAt: .now,
        messageCount: 1,
        byteCount: 10,
        transcriptPath: main.path,
        auxiliaryPaths: [aux.deletingLastPathComponent().deletingLastPathComponent().path],
        isArchived: false
    )

    let outcome = SessionRemover.remove([record], mode: .permanent)
    #expect(outcome.removed.count == 1)
    #expect(outcome.failed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: main.path) == false)
    #expect(FileManager.default.fileExists(atPath: aux.path) == false)
}
