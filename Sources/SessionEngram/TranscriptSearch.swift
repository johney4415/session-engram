import Foundation

/// Plain substring search over a session's transcript files, behind `--content`.
///
/// Word search on the metadata only finds what the title, directory or id happen
/// to carry. A PR number that was only ever pasted mid-conversation, or a table
/// name that came up in the third turn, lives in the transcript body alone. This
/// reads the raw JSONL bytes and matches case-insensitively, without decoding the
/// JSON: the goal is "did this session mention it", not a ranked result.
enum TranscriptSearch {
    /// True when every term appears somewhere in the session's files.
    ///
    /// A term satisfied by one file counts for the whole session, so a Codex thread
    /// split across resumed rollouts still matches as one session.
    static func matches(_ terms: [String], in record: SessionRecord) -> Bool {
        guard !terms.isEmpty else { return true }
        var pending = Set(terms.map { $0.lowercased() })
        for path in record.allPaths {
            guard !pending.isEmpty else { break }
            let url = URL(filePath: path)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { continue }
            let text = String(decoding: data, as: UTF8.self).lowercased()
            pending = pending.filter { !text.contains($0) }
        }
        return pending.isEmpty
    }

    /// Filters `records` down to those whose transcripts mention every term,
    /// reading the files in parallel and keeping the input order.
    static func filter(_ records: [SessionRecord], terms: [String]) -> [SessionRecord] {
        guard !terms.isEmpty, !records.isEmpty else { return records }
        let flags = Flags(count: records.count)
        DispatchQueue.concurrentPerform(iterations: records.count) { index in
            flags.set(index, to: matches(terms, in: records[index]))
        }
        return records.indices.filter { flags[$0] }.map { records[$0] }
    }

    /// One slot per record; every slot is written by exactly one iteration, so the
    /// buffer is safe to share across the parallel loop without a lock.
    private final class Flags: @unchecked Sendable {
        private let buffer: UnsafeMutableBufferPointer<Bool>

        init(count: Int) {
            buffer = .allocate(capacity: count)
            buffer.initialize(repeating: false)
        }

        deinit { buffer.deallocate() }

        func set(_ index: Int, to value: Bool) { buffer[index] = value }
        subscript(index: Int) -> Bool { buffer[index] }
    }
}
