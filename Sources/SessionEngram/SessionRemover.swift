import Foundation

/// Deletes transcripts. Sessions move to the Trash by default so a mistake is recoverable.
enum SessionRemover {
    struct Outcome: Sendable {
        var removed: [SessionRecord] = []
        var failed: [(record: SessionRecord, message: String)] = []

        var reclaimedBytes: Int { removed.reduce(0) { $0 + $1.byteCount } }
    }

    enum Mode: Sendable {
        /// Move to the user's Trash, where it can be put back.
        case trash
        /// Remove from disk immediately.
        case permanent
    }

    static func remove(_ records: [SessionRecord], mode: Mode = .trash) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default

        for record in records {
            var failure: String?
            for path in record.allPaths {
                let url = URL(filePath: path)
                guard fm.fileExists(atPath: path) else { continue }
                do {
                    switch mode {
                    case .trash:
                        try fm.trashItem(at: url, resultingItemURL: nil)
                    case .permanent:
                        try fm.removeItem(at: url)
                    }
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }
            if let failure {
                outcome.failed.append((record, failure))
            } else {
                outcome.removed.append(record)
            }
        }
        return outcome
    }
}
