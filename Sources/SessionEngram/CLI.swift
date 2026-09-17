import Foundation

/// Command line entry point. Runs for every terminal invocation; the menu bar app
/// takes over only when the binary is launched from inside the .app bundle.
enum CLI {
    struct ExitError: Error {
        var message: String
        var code: Int32 = 1
    }

    static let usage = """
    session-engram — browse, resume and clean up past Claude Code and Codex sessions.

    USAGE
      session-engram                        Browse sessions interactively
      session-engram browse [options]       The same browser, explicitly
      session-engram list [options]         Print sessions
      session-engram prompts <id> [--json]  Print the prompts typed in a session
      session-engram resume <id> [--copy]   Print the command that reopens a session
      session-engram delete <id>... [opts]  Move sessions to the Trash
      session-engram refresh                Rebuild the parse cache
      session-engram help

    BROWSE KEYS
      arrows/jk move    space select      a all      x none
      / filter by word
      enter resume in this terminal       c copy resume command
      d move to Trash   s sort   f provider   r rescan
      esc drop the search, then the filter, then quit    q quit

    PROMPTS OPTIONS
      --limit <n>              At most n prompts (default 8)
      --json                   The prompts as a JSON array

    LIST OPTIONS
      --claude, --codex        Only one provider
      --search <text>          Match title, directory or id (all words must match)
      --content                Also match words inside the transcripts (slower)
      --sort <newest|oldest|largest|busiest>
      --limit <n>              Show at most n sessions
      --no-archived            Hide Codex archived sessions
      --plain                  One tab-separated line per session (for fzf or pipes)
      --json                   Full records as JSON
      --interactive, -i        Open the browser with these filters applied

    DELETE OPTIONS
      --yes                    Skip the confirmation prompt
      --permanent              Delete outright instead of moving to the Trash

    EXAMPLES
      session-engram list --search "export preview" --limit 10
      session-engram list --plain --content 16942
      eval "$(session-engram resume 1a2b3c4d)"
      session-engram list --plain | fzf -m | cut -f1 | xargs session-engram delete
      session-engram browse --codex --sort largest
      session-engram prompts 1a2b3c4d

    The menu bar app opens when the binary is launched from Session Engram.app.
    Nothing leaves the machine: every command reads local files and writes to your
    terminal.
    """

    static func run(arguments: [String]) throws {
        var args = arguments
        let command = args.removeFirst()

        switch command {
        case "browse", "pick", "ui": try browse(args)
        case "list", "ls": try list(args)
        case "prompts", "show": try prompts(args)
        case "resume", "cd": try resume(args)
        case "delete", "rm": try delete(args)
        case "refresh": try refresh()
        case "help", "--help", "-h": print(usage)
        case "--version", "version": print(Version.current)
        default:
            throw ExitError(message: "unknown command '\(command)'. Run 'session-engram help'.", code: 2)
        }
    }

    // MARK: - Commands

    private static func list(_ args: [String]) throws {
        let options = try Options(args)
        if options.interactive {
            try browse(args)
            return
        }
        let records = options.query.apply(to: loadRecords())
        let shown = options.limit.map { Array(records.prefix($0)) } ?? records

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(shown)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        guard !shown.isEmpty else {
            fflush(stdout)
            FileHandle.standardError.write(Data("No sessions matched.\n".utf8))
            return
        }

        for record in shown {
            if options.plain {
                print([
                    record.sessionID,
                    record.provider.rawValue,
                    Format.timestamp(record.updatedAt),
                    "\(record.messageCount)",
                    ByteFormat.short(record.byteCount),
                    record.directoryLabel,
                    record.title,
                ].joined(separator: "\t"))
            } else {
                let head = [
                    String(record.sessionID.prefix(8)),
                    Format.timestamp(record.updatedAt),
                    record.provider.rawValue.padded(to: 6),
                    "\(record.messageCount)t".padded(to: 5),
                    ByteFormat.short(record.byteCount).padded(to: 6),
                ].joined(separator: "  ")
                print("\(head)  \(record.title)\(record.isArchived ? "  [archived]" : "")")
                print(String(repeating: " ", count: 10) + record.directoryLabel)
            }
        }

        if !options.plain {
            let bytes = shown.reduce(0) { $0 + $1.byteCount }
            // stdout is block-buffered when piped; flush so the summary lands after the rows.
            fflush(stdout)
            FileHandle.standardError.write(
                Data("\n\(shown.count) session(s), \(ByteFormat.short(bytes)) on disk\n".utf8)
            )
        }
    }

    /// Interactive browser. Without a terminal to draw on — a pipe, a cron job —
    /// this degrades to the plain listing rather than failing.
    static func browse(_ args: [String]) throws {
        var options = try Options(args)
        // The browser re-applies the query on every keystroke; a disk scan per key
        // would make typing lag, so the interactive filter stays on the metadata.
        options.query.searchContent = false
        try browse(records: loadRecords(), query: options.query, args: args)
    }

    private static func browse(
        records: [SessionRecord],
        query: SessionQuery,
        args: [String]
    ) throws {
        guard let browser = InteractiveBrowser(records: records, query: query) else {
            try list(args.filter { $0 != "--interactive" && $0 != "-i" })
            return
        }
        switch browser.run() {
        case .quit:
            return
        case .resume(let record):
            try exec(resume: record)
        }
    }

    /// Replaces this process with the agent's own CLI so the session reopens in the
    /// terminal the browser was started from. Only returns if the launch failed.
    private static func exec(resume record: SessionRecord) throws {
        let argv: [String] = switch record.provider {
        case .claude: ["claude", "--resume", record.sessionID]
        case .codex: ["codex", "resume", record.sessionID]
        }
        if !record.cwd.isEmpty {
            FileManager.default.changeCurrentDirectoryPath(record.cwd)
        }

        var pointers = argv.map { strdup($0) } + [nil]
        defer { for pointer in pointers { free(pointer) } }
        execvp(argv[0], &pointers)

        // Reached only when exec failed, so leave the command behind to run by hand.
        print(record.resumeCommand)
        throw ExitError(message: "could not launch \(argv[0]) — run the command above instead.")
    }

    /// Prints the prompts a person typed in one session. The titles a listing shows
    /// are only the first thing they typed, so this is what tells apart two sessions
    /// on the same subject — for a person reading, or for an agent doing the reading.
    private static func prompts(_ args: [String]) throws {
        let options = try Options(args)
        guard let prefix = options.query.text.split(separator: " ").first.map(String.init) else {
            throw ExitError(message: "usage: session-engram prompts <session-id> [--limit n] [--json]", code: 2)
        }
        let record = try lookup(prefix, in: loadRecords())
        let typed = SessionExcerpt.prompts(for: record, limit: options.limit ?? 8)

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            print(String(decoding: try encoder.encode(typed), as: UTF8.self))
            return
        }

        guard !typed.isEmpty else {
            FileHandle.standardError.write(Data("No prompts found in that session.\n".utf8))
            return
        }
        for prompt in typed {
            print("- \(prompt)")
        }
    }

    private static func resume(_ args: [String]) throws {
        var rest = args
        let copy = rest.removeFlag("--copy")
        guard let prefix = rest.first else {
            throw ExitError(message: "usage: session-engram resume <session-id> [--copy]", code: 2)
        }
        let record = try lookup(prefix, in: loadRecords())
        if record.isArchived {
            FileHandle.standardError.write(
                Data("warning: this Codex session is archived and may not resume.\n".utf8)
            )
        }
        if copy {
            Pasteboard.copy(record.resumeCommand)
            FileHandle.standardError.write(Data("Copied: \(record.resumeCommand)\n".utf8))
        } else {
            print(record.resumeCommand)
        }
    }

    private static func delete(_ args: [String]) throws {
        var rest = args
        let assumeYes = rest.removeFlag("--yes") || rest.removeFlag("-y")
        let permanent = rest.removeFlag("--permanent")
        let prefixes = rest.filter { !$0.hasPrefix("-") }
        guard !prefixes.isEmpty else {
            throw ExitError(message: "usage: session-engram delete <session-id>... [--yes] [--permanent]", code: 2)
        }

        let records = loadRecords()
        let targets = try prefixes.map { try lookup($0, in: records) }

        let verb = permanent ? "Permanently delete" : "Move to Trash"
        print("\(verb) \(targets.count) session(s):")
        for record in targets {
            print("  \(record.sessionID.prefix(8))  \(record.provider.rawValue)  \(record.title)")
        }

        if !assumeYes {
            print("Continue? [y/N] ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                throw ExitError(message: "Cancelled.", code: 1)
            }
        }

        let outcome = SessionRemover.remove(targets, mode: permanent ? .permanent : .trash)
        SessionIndex().clearCache()

        print("Removed \(outcome.removed.count) session(s), \(ByteFormat.short(outcome.reclaimedBytes)) reclaimed.")
        for failure in outcome.failed {
            FileHandle.standardError.write(
                Data("failed: \(failure.record.sessionID) — \(failure.message)\n".utf8)
            )
        }
        if !outcome.failed.isEmpty { throw ExitError(message: "", code: 1) }
    }

    private static func refresh() throws {
        let index = SessionIndex()
        index.clearCache()
        let records = index.scanSync()
        let bytes = records.reduce(0) { $0 + $1.byteCount }
        print("Indexed \(records.count) session(s), \(ByteFormat.short(bytes)) of transcripts.")
    }

    // MARK: - Helpers

    private static func loadRecords() -> [SessionRecord] {
        SessionIndex().scanSync()
    }

    private static func lookup(_ prefix: String, in records: [SessionRecord]) throws -> SessionRecord {
        switch SessionLookup.resolve(prefix, in: records) {
        case .found(let record):
            return record
        case .notFound:
            throw ExitError(message: "no session id starts with '\(prefix)'.")
        case .ambiguous(let matches):
            let list = matches.prefix(5)
                .map { "  \($0.sessionID)  \($0.title)" }
                .joined(separator: "\n")
            throw ExitError(message: "'\(prefix)' matches \(matches.count) sessions:\n\(list)")
        }
    }

    struct Options {
        var query = SessionQuery()
        var limit: Int?
        var json = false
        var plain = false
        var interactive = false

        init(_ args: [String]) throws {
            var iterator = args.makeIterator()
            while let arg = iterator.next() {
                switch arg {
                case "--claude": query.provider = .claude
                case "--codex": query.provider = .codex
                case "--no-archived": query.includeArchived = false
                case "--content", "--deep": query.searchContent = true
                case "--json": json = true
                case "--plain": plain = true
                case "--interactive", "-i": interactive = true
                case "--search", "-s":
                    guard let value = iterator.next() else {
                        throw ExitError(message: "--search needs a value", code: 2)
                    }
                    query.text = value
                case "--sort":
                    guard let value = iterator.next() else {
                        throw ExitError(message: "--sort needs a value", code: 2)
                    }
                    switch value {
                    case "newest", "recent": query.sort = .recent
                    case "oldest": query.sort = .oldest
                    case "largest", "size": query.sort = .largest
                    case "busiest", "turns": query.sort = .busiest
                    default: throw ExitError(message: "unknown sort '\(value)'", code: 2)
                    }
                case "--limit", "-n":
                    guard let value = iterator.next(), let number = Int(value), number > 0 else {
                        throw ExitError(message: "--limit needs a positive number", code: 2)
                    }
                    limit = number
                default:
                    if arg.hasPrefix("-") {
                        throw ExitError(message: "unknown option '\(arg)'", code: 2)
                    }
                    // A bare word is treated as a search term.
                    query.text = query.text.isEmpty ? arg : query.text + " " + arg
                }
            }
        }
    }
}

enum Version {
    static let current = "0.1.0"
}

enum Format {
    /// `VerbatimFormatStyle` is Sendable, so it can be a shared constant under Swift 6.
    private static let stamp = Date.VerbatimFormatStyle(
        format: """
        \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \
        \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)
        """,
        timeZone: .current,
        calendar: .current
    )

    static func timestamp(_ date: Date) -> String { date.formatted(stamp) }

    static func relative(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        switch seconds {
        case ..<3600: return "\(max(1, Int(seconds / 60)))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d ago"
        default: return String(timestamp(date).prefix(10))
        }
    }
}

enum Pasteboard {
    /// Uses `pbcopy` so this works from a plain CLI run without loading AppKit.
    static func copy(_ text: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe
        guard (try? process.run()) != nil else { return }
        pipe.fileHandleForWriting.write(Data(text.utf8))
        pipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

extension Array where Element == String {
    mutating func removeFlag(_ flag: String) -> Bool {
        guard let index = firstIndex(of: flag) else { return false }
        remove(at: index)
        return true
    }

    /// Removes `--name value` and hands back the value, so the remaining arguments
    /// can go through the shared option parser.
    mutating func removeValue(for flag: String) -> String? {
        guard let index = firstIndex(of: flag), index + 1 < count else { return nil }
        let value = self[index + 1]
        removeSubrange(index...(index + 1))
        return value
    }
}
