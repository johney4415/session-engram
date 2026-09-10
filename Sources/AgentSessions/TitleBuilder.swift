import Foundation

/// Turns raw prompt text into a one-line session title.
///
/// Both CLIs store whole transcripts and neither writes a title for Claude sessions,
/// so the first prompt a person actually typed is the best available label. This
/// filters out the noise that surrounds it: injected context, interruption markers,
/// pasted links, and one-word replies.
enum TitleBuilder {
    static let maxLength = 80
    static let fallback = "(untitled session)"

    /// Picks the first prompt worth showing and normalizes it.
    static func title(from candidates: [String]) -> String? {
        for candidate in candidates where isPersonWritten(candidate) {
            let cleaned = normalize(candidate)
            if isUsable(cleaned) { return truncate(cleaned) }
        }
        return nil
    }

    /// Rejects turns that the harness injected rather than the person typing.
    ///
    /// Both CLIs push context into the user role — reminders, available plugins,
    /// recovered state — and every one of those starts with a tag.
    static func isPersonWritten(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") { return false }
        if trimmed.hasPrefix("Caveat:") { return false }
        if trimmed.hasPrefix("[Request interrupted") { return false }
        if trimmed.localizedCaseInsensitiveContains("system-reminder") { return false }
        return true
    }

    /// Collapses whitespace and strips wrappers that carry no meaning in a list.
    static func normalize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(
            of: "<[^>]{1,80}>",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\[(Request interrupted[^\\]]*|Image #\\d+)\\]",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "https?://\\S+",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "^[#>\\-*\\s]+",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rejects prompts that would leave the reader no wiser than an empty row.
    static func isUsable(_ normalized: String) -> Bool {
        guard normalized.count >= 4 else { return false }
        if normalized.localizedCaseInsensitiveContains("system-reminder") { return false }
        if normalized.hasPrefix("Caveat:") { return false }
        let filler: Set<String> = ["exit", "eixt", "exut", "wxit", "quit", "continue", "繼續", "ok 繼續"]
        if filler.contains(normalized.lowercased()) { return false }
        // A prompt that is only punctuation or digits tells the reader nothing.
        return normalized.contains { $0.isLetter }
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
