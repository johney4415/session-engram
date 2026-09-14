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
        for candidate in candidates {
            guard let cleaned = displayText(candidate) else { continue }
            if isUsable(cleaned) { return truncate(cleaned) }
        }
        return nil
    }

    /// What one turn should read as in a list, or nil when the harness wrote it.
    static func displayText(_ raw: String) -> String? {
        if let command = slashCommand(raw) { return command }
        guard isPersonWritten(raw) else { return nil }
        return normalize(raw)
    }

    /// Rebuilds the line a person typed to run a slash command.
    ///
    /// The harness stores the invocation as tags, so the plain filter throws it away
    /// with the rest of the injected context — and with it the only thing that
    /// identifies a session spent entirely on one command. `/review-pr 16942` is how
    /// someone looks for that session later, so the arguments are kept verbatim:
    /// stripping the link would take the number with it.
    ///
    /// Only commands that carry arguments come back. A bare `/clear` or `/compact`
    /// names the command, never the session.
    static func slashCommand(_ raw: String) -> String? {
        guard let name = tagValue("command-name", in: raw), !name.isEmpty,
              let args = tagValue("command-args", in: raw), !args.isEmpty
        else { return nil }
        return collapseWhitespace("\(name) \(args)")
    }

    private static func tagValue(_ tag: String, in raw: String) -> String? {
        guard let range = raw.range(
            of: "<\(tag)>[\\s\\S]*?</\(tag)>",
            options: .regularExpression
        ) else { return nil }
        let inner = raw[range].dropFirst(tag.count + 2).dropLast(tag.count + 3)
        return collapseWhitespace(String(inner))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rejects turns that the harness injected rather than the person typing.
    ///
    /// Both CLIs push context into the user role — reminders, available plugins,
    /// recovered state — and every one of those starts with a tag. A slash command
    /// with arguments is the exception: it is tagged too, but the person typed it.
    static func isPersonWritten(_ raw: String) -> Bool {
        if slashCommand(raw) != nil { return true }
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
