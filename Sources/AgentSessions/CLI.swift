import Foundation

/// Command line entry point. Runs whenever the binary is invoked with arguments;
/// without arguments the same binary opens the menu bar app instead.
enum CLI {
    struct ExitError: Error {
        var message: String
        var code: Int32 = 1
    }

    static let usage = """
    agent-sessions — browse, resume and clean up past Claude Code and Codex sessions.

    USAGE
      agent-sessions                        Open the menu bar app
      agent-sessions list [options]         List sessions
      agent-sessions resume <id> [--copy]   Print the command that reopens a session
      agent-sessions delete <id>... [opts]  Move sessions to the Trash
      agent-sessions refresh                Rebuild the parse cache
      agent-sessions help

    LIST OPTIONS
      --claude, --codex        Only one provider
      --search <text>          Match title, directory or id (all words must match)
      --sort <newest|oldest|largest|busiest>
      --limit <n>              Show at most n sessions
      --no-archived            Hide Codex archived sessions
      --plain                  One tab-separated line per session (for fzf or pipes)
      --json                   Full records as JSON

    DELETE OPTIONS
      --yes                    Skip the confirmation prompt
      --permanent              Delete outright instead of moving to the Trash

    EXAMPLES
      agent-sessions list --search "export preview" --limit 10
      eval "$(agent-sessions resume 1a2b3c4d)"
      agent-sessions list --plain | fzf -m | cut -f1 | xargs agent-sessions delete
    """

    static func run(arguments: [String]) throws {
        var args = arguments
        let command = args.removeFirst()

        switch command {
        case "list", "ls": try list(args)
        case "resume", "cd": try resume(args)
        case "delete", "rm": try delete(args)
        case "refresh": try refresh()
        case "help", "--help", "-h": print(usage)
        case "--version", "version": print(Version.current)
        default:
            throw ExitError(message: "unknown command '\(command)'. Run 'agent-sessions help'.", code: 2)
        }
    }

    // MARK: - Commands

    private static func list(_ args: [String]) throws {
        let options = try Options(args)
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

    private static func resume(_ args: [String]) throws {
        var rest = args
        let copy = rest.removeFlag("--copy")
        guard let prefix = rest.first else {
            throw ExitError(message: "usage: agent-sessions resume <session-id> [--copy]", code: 2)
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
            throw ExitError(message: "usage: agent-sessions delete <session-id>... [--yes] [--permanent]", code: 2)
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

    private struct Options {
        var query = SessionQuery()
        var limit: Int?
        var json = false
        var plain = false

        init(_ args: [String]) throws {
            var iterator = args.makeIterator()
            while let arg = iterator.next() {
                switch arg {
                case "--claude": query.provider = .claude
                case "--codex": query.provider = .codex
                case "--no-archived": query.includeArchived = false
                case "--json": json = true
                case "--plain": plain = true
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
}
