import Foundation

/// Search and filter rules shared by the menu bar list and the CLI.
struct SessionQuery: Sendable, Equatable {
    var text: String = ""
    var provider: AgentProvider?
    var sort: SessionSort = .recent
    var includeArchived: Bool = true

    func apply(to records: [SessionRecord]) -> [SessionRecord] {
        let terms = text
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        let filtered = records.filter { record in
            if let provider, record.provider != provider { return false }
            if !includeArchived, record.isArchived { return false }
            guard !terms.isEmpty else { return true }
            let haystack = [
                record.title,
                record.directoryLabel,
                record.sessionID,
                record.provider.rawValue,
            ].joined(separator: " ").lowercased()
            // Every term must appear, so extra words narrow rather than widen.
            return terms.allSatisfy { haystack.contains($0) }
        }
        return sort.sort(filtered)
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
