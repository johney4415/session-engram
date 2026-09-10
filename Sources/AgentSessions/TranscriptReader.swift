import Foundation

/// Reads a JSONL transcript one object at a time.
///
/// Transcripts reach several megabytes, so the file is memory-mapped and split on
/// newlines rather than decoded into one giant string.
enum TranscriptReader {
    static func forEachObject(
        at url: URL,
        _ body: ([String: Any]) throws -> Bool
    ) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            defer { start = end < data.endIndex ? data.index(after: end) : data.endIndex }
            guard end > start else { continue }
            let slice = data[start..<end]
            guard let object = try? JSONSerialization.jsonObject(with: slice) as? [String: Any] else {
                continue
            }
            if try body(object) == false { return }
        }
    }

    /// Pulls the plain text out of a message payload, which is either a bare string
    /// or a list of typed content blocks. Claude labels text blocks `text`, Codex
    /// labels the same thing `input_text`.
    static func text(from content: Any?, textKeys: Set<String> = ["text"]) -> String {
        if let string = content as? String { return string }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks
            .filter { textKeys.contains($0["type"] as? String ?? "") }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    // `FormatStyle` values are Sendable, unlike `ISO8601DateFormatter`, so they can be
    // shared across the parsing tasks.
    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    /// Parses the timestamps both CLIs write, with or without fractional seconds.
    static func date(from string: String) -> Date? {
        (try? isoWithFraction.parse(string)) ?? (try? isoPlain.parse(string))
    }
}

enum FileMetrics {
    static func size(of url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    static func modified(at url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }
}
