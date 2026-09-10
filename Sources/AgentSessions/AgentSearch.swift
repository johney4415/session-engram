import Foundation

/// Which installed coding agent answers a natural-language search.
enum SearchAgent: String, CaseIterable, Sendable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// `claude -p` and `codex exec` both put the final answer on stdout and their
    /// progress chatter on stderr, which is what makes them usable as a filter.
    func arguments(for prompt: String) -> [String] {
        switch self {
        case .claude:
            ["-p", prompt]
        case .codex:
            ["exec", "--skip-git-repo-check", "--color", "never", "--sandbox", "read-only", prompt]
        }
    }

    var executablePath: String? { Executable.find(rawValue) }

    /// Claude first when both are installed, because `claude -p` answers sooner.
    static func detect() -> SearchAgent? { allCases.first { $0.executablePath != nil } }

    static func named(_ name: String) throws -> SearchAgent {
        guard let agent = SearchAgent(rawValue: name.lowercased()) else {
            throw AgentSearch.Failure(message: "unknown agent '\(name)' — use claude or codex")
        }
        return agent
    }
}

enum Executable {
    /// Looks the name up on PATH. `Process` needs an absolute path, and both agents
    /// are installed in places that vary between machines.
    static func find(_ name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for directory in path.split(separator: ":") {
            let candidate = URL(filePath: String(directory)).appending(path: name).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// Natural-language session search, with the judgement handed to a coding agent.
///
/// Two passes, because neither extreme works on its own: titles alone miss whatever
/// the session turned out to be about, and every transcript at once is far too much
/// to send. So the agent first shortlists from the metadata, and then reads the
/// prompts of the sessions it shortlisted.
///
/// This is the only part of the tool that sends anything off the machine.
struct AgentSearch {
    struct Failure: Error {
        var message: String
    }

    struct Hit: Sendable {
        var record: SessionRecord
        var reason: String
    }

    struct Report: Sendable {
        var agent: SearchAgent
        var hits: [Hit] = []
        var shortlisted = 0
        /// Anything the caller should mention to the person, such as a truncated pool.
        var note: String?
    }

    /// A prefix that makes the sessions this search itself creates recognisable in
    /// the list, since both agents record their own transcript for every run.
    static let marker = "agent-sessions search"
    /// Metadata is one line per session, but a pool of thousands would still dominate
    /// the prompt, so only the most recent are offered to the first pass.
    static let poolLimit = 400

    var agent: SearchAgent
    var question: String
    /// How many sessions the first pass may put forward for the content pass.
    var shortlist = 12
    var limit = 8
    var timeout: TimeInterval = 180
    /// Called before each agent call, so a caller can show what is happening.
    var progress: (String) -> Void = { _ in }

    func run(over records: [SessionRecord]) throws -> Report {
        var report = Report(agent: agent)
        guard !records.isEmpty else { return report }

        let pool = Array(records.prefix(Self.poolLimit))
        if pool.count < records.count {
            report.note = "searched the \(pool.count) most recent of \(records.count) sessions"
        }

        progress("Shortlisting \(pool.count) sessions with \(agent.displayName)…")
        guard let offsets = indexes(in: try ask(shortlistPrompt(for: pool))) else {
            throw Failure(message: "could not read \(agent.displayName)'s shortlist reply")
        }
        let candidates = offsets
            .filter { pool.indices.contains($0 - 1) }
            .prefix(shortlist)
            .map { pool[$0 - 1] }
        report.shortlisted = candidates.count
        guard !candidates.isEmpty else { return report }

        progress("Reading \(candidates.count) transcripts…")
        let excerpts = candidates.map { SessionExcerpt.prompts(for: $0) }

        progress("Ranking with \(agent.displayName)…")
        let reply = try ask(rankPrompt(for: candidates, excerpts: excerpts))

        guard let ranked = ranking(in: reply) else {
            // An unparseable reply is not the same as "nothing matched", so fall back
            // to the shortlist rather than reporting an empty result.
            report.hits = candidates.prefix(limit).map { Hit(record: $0, reason: "shortlisted from the title") }
            report.note = "could not read \(agent.displayName)'s ranking; showing its shortlist"
            return report
        }

        report.hits = ranked
            .filter { candidates.indices.contains($0.index - 1) }
            .prefix(limit)
            .map { Hit(record: candidates[$0.index - 1], reason: $0.why) }
        return report
    }

    // MARK: - Prompts

    /// Exposed so `--dry-run` can show exactly what would be sent.
    func shortlistPrompt(for pool: [SessionRecord]) -> String {
        let rows = pool.enumerated().map { offset, record in
            [
                "\(offset + 1)",
                record.provider.rawValue,
                Format.timestamp(record.updatedAt),
                "\(record.messageCount)t",
                record.directoryLabel,
                TextWidth.oneLine(record.title),
            ].joined(separator: " | ")
        }

        return """
        \(Self.marker): match a person's description to their own past coding-agent sessions.

        THE PERSON IS LOOKING FOR
        \(question)

        SESSIONS — index | agent | last used | turns | directory | title
        \(rows.joined(separator: "\n"))

        Pick the sessions whose full transcript is worth reading to check the match.
        Judge on the topic, the directory and the date. Prefer a broad shortlist over
        a confident guess: a title is only the first thing the person typed, so a
        session about the right subject can have an unrelated title.

        Reply with only a JSON array of indexes, most promising first, at most
        \(shortlist) entries, and nothing else. Example: [12, 3, 40]
        Reply [] if not one of them could plausibly match.
        """
    }

    func rankPrompt(for candidates: [SessionRecord], excerpts: [[String]]) -> String {
        let blocks = zip(candidates, excerpts).enumerated().map { offset, pair in
            let (record, prompts) = pair
            let body = prompts.isEmpty
                ? "(no readable prompts)"
                : prompts.map { "- \($0)" }.joined(separator: "\n")
            return """
            --- \(offset + 1) ---
            \(record.provider.rawValue) · \(Format.timestamp(record.updatedAt)) · \(record.directoryLabel)
            title: \(TextWidth.oneLine(record.title))
            what the person asked in it:
            \(body)
            """
        }

        return """
        \(Self.marker): decide which of these sessions the person means.

        THE PERSON IS LOOKING FOR
        \(question)

        CANDIDATES
        \(blocks.joined(separator: "\n\n"))

        Reply with only a JSON array, best match first, at most \(limit) entries, and
        nothing else. Each entry is {"index": <number>, "why": "<up to 12 words>"}.
        The "why" names the concrete thing in that session that matches. Leave out
        every candidate that does not actually match; reply [] if none of them do.
        """
    }

    // MARK: - Replies

    /// Both passes are asked for a bare JSON array, but agents like to wrap an answer
    /// in prose or a fenced block, so the array is lifted out of whatever comes back.
    func jsonArray(in reply: String) -> [Any]? {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end
        else { return nil }
        let slice = String(reply[start...end])
        return try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [Any]
    }

    /// `nil` means the reply could not be read; `[]` means the agent found nothing.
    func indexes(in reply: String) -> [Int]? {
        guard let array = jsonArray(in: reply) else { return nil }
        return array.compactMap { element in
            if let number = element as? Int { return number }
            if let object = element as? [String: Any] { return object["index"] as? Int }
            return nil
        }
    }

    func ranking(in reply: String) -> [(index: Int, why: String)]? {
        guard let array = jsonArray(in: reply) else { return nil }
        return array.compactMap { element in
            if let object = element as? [String: Any], let index = object["index"] as? Int {
                let why = (object["why"] as? String) ?? ""
                return (index, why.isEmpty ? "matched" : why)
            }
            // A bare index is still an answer, just without the reasoning.
            if let index = element as? Int { return (index, "matched") }
            return nil
        }
    }

    // MARK: - Running the agent

    private func ask(_ prompt: String) throws -> String {
        guard let executable = agent.executablePath else {
            throw Failure(message: "\(agent.rawValue) is not on PATH")
        }

        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = agent.arguments(for: prompt)
        // The agent must not inherit the browser's terminal, or it draws over it.
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        // stdout is drained while the process runs: waiting first would deadlock as
        // soon as a reply outgrew the pipe buffer.
        let collector = OutputCollector()
        let reading = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            collector.data = output.fileHandleForReading.readDataToEndOfFile()
            reading.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw Failure(message: "could not run \(agent.rawValue): \(error.localizedDescription)")
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw Failure(message: "\(agent.displayName) did not answer within \(Int(timeout))s")
        }
        _ = reading.wait(timeout: .now() + 10)

        let reply = String(decoding: collector.data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure(message: "\(agent.rawValue) exited with status \(process.terminationStatus)")
        }
        return reply
    }

    private final class OutputCollector: @unchecked Sendable {
        var data = Data()
    }
}
