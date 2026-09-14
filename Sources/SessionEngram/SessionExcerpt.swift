import Foundation

/// Pulls the prompts a person typed out of a transcript, behind `prompts`.
///
/// Only user turns are read. They carry the topic of the session, which a title —
/// the first thing typed — often does not, and keeping to them means whole
/// transcripts of code and tool output stay unread.
enum SessionExcerpt {
    static func prompts(for record: SessionRecord, limit: Int = 8, characters: Int = 200) -> [String] {
        var found: [String] = []

        /// Returns false once enough prompts are collected, which stops the read.
        func collect(_ raw: String) -> Bool {
            guard let text = TitleBuilder.displayText(raw) else { return true }
            guard text.count >= 4, text.contains(where: { $0.isLetter }) else { return true }
            found.append(text.count > characters ? String(text.prefix(characters)) + "…" : text)
            return found.count < limit
        }

        let url = URL(filePath: record.transcriptPath)
        switch record.provider {
        case .claude:
            try? TranscriptReader.forEachObject(at: url) { object in
                guard object["type"] as? String == "user",
                      (object["isMeta"] as? Bool) != true,
                      let message = object["message"] as? [String: Any]
                else { return true }
                return collect(TranscriptReader.text(from: message["content"]))
            }
        case .codex:
            try? TranscriptReader.forEachObject(at: url) { object in
                guard let type = object["type"] as? String,
                      let payload = object["payload"] as? [String: Any]
                else { return true }
                switch type {
                case "event_msg" where payload["type"] as? String == "user_message":
                    return collect((payload["message"] as? String) ?? "")
                case "response_item" where payload["type"] as? String == "message"
                    && payload["role"] as? String == "user":
                    return collect(TranscriptReader.text(from: payload["content"], textKeys: ["input_text", "text"]))
                default:
                    return true
                }
            }
        }
        return found
    }
}
