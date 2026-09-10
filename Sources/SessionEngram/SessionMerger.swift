import Foundation

/// Folds transcripts that belong to the same conversation into one row.
///
/// Codex writes a fresh `rollout-*.jsonl` whenever a thread is resumed or compacted,
/// so one session id can span several files. They resume as one session and should
/// be deleted as one, so they are presented as one.
enum SessionMerger {
    static func merge(_ records: [SessionRecord]) -> [SessionRecord] {
        var groups: [String: [SessionRecord]] = [:]
        for record in records {
            let key = "\(record.provider.rawValue)|\(record.sessionID)|\(record.isArchived)"
            groups[key, default: []].append(record)
        }

        return groups.values.map { group -> SessionRecord in
            guard group.count > 1 else { return group[0] }
            let ordered = group.sorted { $0.updatedAt < $1.updatedAt }
            var merged = ordered[ordered.count - 1]
            merged.byteCount = ordered.reduce(0) { $0 + $1.byteCount }
            merged.messageCount = ordered.reduce(0) { $0 + $1.messageCount }
            // The opening prompt describes the work better than a resumed fragment does.
            if let named = ordered.first(where: { $0.title != TitleBuilder.fallback }) {
                merged.title = named.title
            }
            merged.auxiliaryPaths = ordered
                .dropLast()
                .flatMap(\.allPaths)
                + merged.auxiliaryPaths
            return merged
        }
    }
}
