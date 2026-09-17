import Foundation

/// Search and filter rules shared by the menu bar list and the CLI.
struct SessionQuery: Sendable, Equatable {
    var text: String = ""
    var provider: AgentProvider?
    var sort: SessionSort = .recent
    var includeArchived: Bool = true
    /// Also read each transcript for the search terms. Off by default because the
    /// menu bar and the browser re-run the query on every keystroke, and reading
    /// every transcript is a disk scan rather than a lookup.
    var searchContent: Bool = false

    func apply(to records: [SessionRecord]) -> [SessionRecord] {
        let terms = text
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        let candidates = records.filter { record in
            if let provider, record.provider != provider { return false }
            if !includeArchived, record.isArchived { return false }
            return true
        }
        guard !terms.isEmpty else { return sort.sort(candidates) }

        // Every term must appear, so extra words narrow rather than widen.
        let byMetadata = candidates.filter { record in
            let haystack = [
                record.title,
                record.directoryLabel,
                record.sessionID,
                record.provider.rawValue,
            ].joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        guard searchContent else { return sort.sort(byMetadata) }

        // Only the sessions the metadata missed are read from disk.
        let matched = Set(byMetadata.map(\.id))
        let byContent = TranscriptSearch.filter(candidates.filter { !matched.contains($0.id) }, terms: terms)
        return sort.sort(byMetadata + byContent)
    }
}

/// Resolves a user-typed id prefix to exactly one session.
enum SessionLookup {
    enum Result: Sendable {
        case found(SessionRecord)
        case notFound
        case ambiguous([SessionRecord])
    }

    static func resolve(_ prefix: String, in records: [SessionRecord]) -> Result {
        let needle = prefix.lowercased()
        let exact = records.filter { $0.sessionID.lowercased() == needle }
        if let match = exact.first, exact.count == 1 { return .found(match) }

        let matches = records.filter { $0.sessionID.lowercased().hasPrefix(needle) }
        switch matches.count {
        case 0: return .notFound
        case 1: return .found(matches[0])
        default: return .ambiguous(matches)
        }
    }
}
