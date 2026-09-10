import Foundation

/// Finds Codex transcripts under `~/.codex/sessions` (and `archived_sessions`).
///
/// Layout: `sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`. The first line
/// is a `session_meta` object carrying the resumable id and the working directory.
/// `~/.codex/session_index.jsonl` maps ids to the thread names Codex already wrote,
/// so those are preferred over a prompt-derived title.
struct CodexScanner: Sendable {
    var sessionsRoot: URL
    var archivedRoot: URL
    var indexFile: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let codex = home.appending(path: ".codex", directoryHint: .isDirectory)
        sessionsRoot = codex.appending(path: "sessions", directoryHint: .isDirectory)
        archivedRoot = codex.appending(path: "archived_sessions", directoryHint: .isDirectory)
        indexFile = codex.appending(path: "session_index.jsonl")
    }

    init(sessionsRoot: URL, archivedRoot: URL, indexFile: URL) {
        self.sessionsRoot = sessionsRoot
        self.archivedRoot = archivedRoot
        self.indexFile = indexFile
    }

    /// Session id to thread name, as recorded by Codex itself.
    func threadNames() -> [String: String] {
        var names: [String: String] = [:]
        try? TranscriptReader.forEachObject(at: indexFile) { object in
            if let id = object["id"] as? String,
               let name = (object["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                names[id] = name
            }
            return true
        }
        return names
    }

    func transcripts() -> [(url: URL, archived: Bool)] {
        rollouts(in: sessionsRoot).map { ($0, false) }
            + rollouts(in: archivedRoot).map { ($0, true) }
    }

    private func rollouts(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            found.append(url)
        }
        return found
    }

    func record(for url: URL, archived: Bool, threadNames: [String: String]) -> SessionRecord? {
        var sessionID = ""
        var cwd = ""
        // Kept as text and parsed once at the end; parsing every line would dominate the scan.
        var latestStamp: String?
        // Interactive runs record prompts as `event_msg`; `codex exec` runs only leave
        // them on the raw `response_item` turns, so both are collected.
        var typedCount = 0
        var typedCandidates: [String] = []
        var rawCount = 0
        var rawCandidates: [String] = []

        do {
            try TranscriptReader.forEachObject(at: url) { object in
                if let stamp = object["timestamp"] as? String { latestStamp = stamp }
                guard let type = object["type"] as? String,
                      let payload = object["payload"] as? [String: Any]
                else { return true }

                switch type {
                case "session_meta":
                    sessionID = (payload["session_id"] as? String) ?? (payload["id"] as? String) ?? ""
                    cwd = (payload["cwd"] as? String) ?? ""
                case "event_msg" where payload["type"] as? String == "user_message":
                    let text = (payload["message"] as? String) ?? ""
                    guard TitleBuilder.isPersonWritten(text) else { return true }
                    typedCount += 1
                    if typedCandidates.count < 6 { typedCandidates.append(text) }
                case "response_item" where payload["type"] as? String == "message"
                    && payload["role"] as? String == "user":
                    let text = TranscriptReader.text(from: payload["content"], textKeys: ["input_text", "text"])
                    guard TitleBuilder.isPersonWritten(text) else { return true }
                    rawCount += 1
                    if rawCandidates.count < 6 { rawCandidates.append(text) }
                default:
                    break
                }
                return true
            }
        } catch {
            return nil
        }

        let messageCount = typedCount > 0 ? typedCount : rawCount
        let candidates = typedCandidates.isEmpty ? rawCandidates : typedCandidates

        if sessionID.isEmpty {
            // `rollout-<timestamp>-<uuid>.jsonl` — the uuid is the last five dashed groups.
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "-")
            guard parts.count >= 5 else { return nil }
            sessionID = parts.suffix(5).joined(separator: "-")
        }

        let title = threadNames[sessionID]
            ?? TitleBuilder.title(from: candidates)
            ?? TitleBuilder.fallback

        return SessionRecord(
            provider: .codex,
            sessionID: sessionID,
            title: TitleBuilder.truncate(title),
            cwd: cwd,
            updatedAt: latestStamp.flatMap(TranscriptReader.date(from:)) ?? FileMetrics.modified(at: url),
            messageCount: messageCount,
            byteCount: FileMetrics.size(of: url),
            transcriptPath: url.path,
            auxiliaryPaths: [],
            isArchived: archived
        )
    }
}
