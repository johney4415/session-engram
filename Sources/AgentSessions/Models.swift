import Foundation

enum AgentProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// A finished (or resumable) session transcript found on disk.
struct SessionRecord: Identifiable, Hashable, Codable, Sendable {
    /// Transcript path, which is unique across both providers.
    var id: String { transcriptPath }

    var provider: AgentProvider
    /// The id the provider's CLI accepts for resuming.
    var sessionID: String
    var title: String
    /// Working directory the session ran in. Empty when the transcript never recorded one.
    var cwd: String
    var updatedAt: Date
    /// Number of real user turns, excluding tool results and injected context.
    var messageCount: Int
    var byteCount: Int
    var transcriptPath: String
    /// Extra paths that belong to this session and must be removed alongside it,
    /// such as Claude's per-session subagent directory.
    var auxiliaryPaths: [String]
    /// Codex moves some transcripts to `archived_sessions`; those still take up space
    /// but the CLI can no longer resume them.
    var isArchived: Bool

    var isResumable: Bool { !isArchived }

    /// Shell command that reopens the session in its original directory.
    var resumeCommand: String {
        let resume = switch provider {
        case .claude: "claude --resume \(sessionID)"
        case .codex: "codex resume \(sessionID)"
        }
        guard !cwd.isEmpty else { return resume }
        return "cd \(Shell.quote(cwd)) && \(resume)"
    }

    /// Directory label used in the list, with the home prefix collapsed to `~`.
    var directoryLabel: String {
        guard !cwd.isEmpty else { return "unknown directory" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }

    var allPaths: [String] { [transcriptPath] + auxiliaryPaths }
}

enum Shell {
    /// Single-quotes a path so it survives spaces and shell metacharacters.
    static func quote(_ value: String) -> String {
        guard value.contains(where: { !$0.isLetter && !$0.isNumber && !"/._-~".contains($0) }) else {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum SessionSort: String, CaseIterable, Identifiable, Sendable {
    case recent
    case oldest
    case largest
    case busiest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Newest"
        case .oldest: "Oldest"
        case .largest: "Largest"
        case .busiest: "Most turns"
        }
    }

    func sort(_ records: [SessionRecord]) -> [SessionRecord] {
        switch self {
        case .recent: records.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest: records.sorted { $0.updatedAt < $1.updatedAt }
        case .largest: records.sorted { $0.byteCount > $1.byteCount }
        case .busiest: records.sorted { $0.messageCount > $1.messageCount }
        }
    }
}

enum ByteFormat {
    static func short(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1 { return "\(bytes)B" }
        if kb < 1024 { return "\(Int(kb.rounded()))K" }
        return String(format: "%.1fM", kb / 1024)
    }
}
