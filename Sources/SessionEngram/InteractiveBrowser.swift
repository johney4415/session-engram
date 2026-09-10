import Foundation

/// Full-screen session browser: arrows to move, space to select, enter to resume.
///
/// The browser owns the terminal while it runs and hands back what should happen
/// afterwards, so resuming a session can replace this process once the screen has
/// been restored.
final class InteractiveBrowser {
    enum Outcome {
        case quit
        case resume(SessionRecord)
    }

    private enum Mode {
        case browsing
        /// Typing into the plain text filter.
        case searching
        /// Waiting for `y` before moving sessions to the Trash.
        case confirmingDelete
    }

    private let terminal: Terminal
    private let index = SessionIndex()

    private var allRecords: [SessionRecord]
    private var query: SessionQuery
    private var visible: [SessionRecord] = []
    private var selection: Set<String> = []
    private var cursor = 0
    private var top = 0
    private var mode = Mode.browsing
    private var status: String?

    init?(records: [SessionRecord], query: SessionQuery) {
        guard let terminal = Terminal() else { return nil }
        self.terminal = terminal
        self.allRecords = records
        self.query = query
        rebuild()
    }

    func run() -> Outcome {
        terminal.start()
        defer { terminal.restore() }

        while true {
            render()
            if let outcome = handle(terminal.readKey()) { return outcome }
        }
    }

    // MARK: - Keys

    /// Returns an outcome only when the browser should close.
    private func handle(_ key: Terminal.Key) -> Outcome? {
        switch mode {
        case .confirmingDelete: return confirmDelete(key)
        case .searching: return typeSearch(key)
        case .browsing: return browse(key)
        }
    }

    private func browse(_ key: Terminal.Key) -> Outcome? {
        switch key {
        case .up: move(-1)
        case .down: move(1)
        case .pageUp: move(-pageSize)
        case .pageDown: move(pageSize)
        case .home: move(-visible.count)
        case .end: move(visible.count)
        case .interrupt: return .quit
        case .escape: clearNarrowing()
        case .enter:
            if let record = current { return resume(record) }
        case .character(let character):
            switch character {
            case " ": toggleSelection()
            case "j": move(1)
            case "k": move(-1)
            case "/":
                mode = .searching
            case "a": selection = Set(visible.map(\.id)); note("\(selection.count) selected")
            case "x": selection.removeAll()
            case "c": copyResumeCommands()
            case "d": if !targets.isEmpty { mode = .confirmingDelete }
            case "s": cycleSort()
            case "f": cycleProvider()
            case "r": rescan()
            case "q": return .quit
            default: break
            }
        default: break
        }
        return nil
    }

    private func typeSearch(_ key: Terminal.Key) -> Outcome? {
        switch key {
        case .enter, .escape: mode = .browsing
        case .interrupt: return .quit
        case .backspace:
            guard !query.text.isEmpty else { break }
            query.text.removeLast()
            rebuild()
        case .character(let character):
            query.text.append(character)
            rebuild()
        case .up: move(-1)
        case .down: move(1)
        default: break
        }
        return nil
    }

    private func confirmDelete(_ key: Terminal.Key) -> Outcome? {
        switch key {
        case .character("y"), .character("Y"), .enter:
            mode = .browsing
            delete()
        case .interrupt:
            return .quit
        default:
            mode = .browsing
            note("Cancelled")
        }
        return nil
    }

    // MARK: - Actions

    private var current: SessionRecord? {
        visible.indices.contains(cursor) ? visible[cursor] : nil
    }

    /// The rows an action applies to: everything ticked, or the row under the cursor
    /// when nothing is ticked.
    private var targets: [SessionRecord] {
        let selected = visible.filter { selection.contains($0.id) }
        if !selected.isEmpty { return selected }
        return current.map { [$0] } ?? []
    }

    private func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        cursor = min(max(0, cursor + delta), visible.count - 1)
    }

    private func toggleSelection() {
        guard let record = current else { return }
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
        move(1)
    }

    /// Escape drops the text filter first, and only leaves once there is none.
    private func clearNarrowing() {
        guard !query.text.isEmpty else { return }
        query.text = ""
        rebuild()
    }

    private func resume(_ record: SessionRecord) -> Outcome? {
        guard record.isResumable else {
            note("That Codex session is archived and cannot be resumed")
            return nil
        }
        return .resume(record)
    }

    private func copyResumeCommands() {
        let rows = targets
        guard !rows.isEmpty else { return }
        Pasteboard.copy(rows.map(\.resumeCommand).joined(separator: "\n"))
        note(rows.count == 1 ? "Copied resume command" : "Copied \(rows.count) commands")
    }

    private func delete() {
        let rows = targets
        guard !rows.isEmpty else { return }
        let outcome = SessionRemover.remove(rows, mode: .trash)
        let removed = Set(outcome.removed.map(\.id))
        allRecords.removeAll { removed.contains($0.id) }
        selection.subtract(removed)
        index.clearCache()
        rebuild()

        if outcome.failed.isEmpty {
            note("Moved \(outcome.removed.count) to Trash · \(ByteFormat.short(outcome.reclaimedBytes)) freed")
        } else {
            note("\(outcome.failed.count) session(s) could not be removed")
        }
    }

    private func rescan() {
        note("Rescanning…")
        render()
        allRecords = index.scanSync()
        selection = selection.filter { id in allRecords.contains { $0.id == id } }
        rebuild()
        note("\(allRecords.count) session(s) indexed")
    }

    private func cycleSort() {
        let options = SessionSort.allCases
        let next = (options.firstIndex(of: query.sort).map { $0 + 1 } ?? 0) % options.count
        query.sort = options[next]
        rebuild()
        note("Sorted by \(query.sort.label.lowercased())")
    }

    private func cycleProvider() {
        query.provider = switch query.provider {
        case .none: .claude
        case .claude: .codex
        case .codex: nil
        }
        rebuild()
        note(query.provider?.displayName ?? "All providers")
    }

    private func note(_ message: String) { status = message }

    private func rebuild() {
        let anchor = current?.id
        visible = query.apply(to: allRecords)
        cursor = anchor.flatMap { id in visible.firstIndex { $0.id == id } } ?? cursor
        cursor = min(max(0, cursor), max(0, visible.count - 1))
        status = nil
    }

    // MARK: - Rendering

    /// Two terminal lines per session: the title, then its id, meta and directory.
    private let linesPerRow = 2
    /// Header, prompt line, two dividers, the status line and the key hints.
    private let chromeLines = 6

    private var pageSize: Int {
        max(1, (terminal.size.rows - chromeLines) / linesPerRow)
    }

    private func render() {
        let (_, columns) = terminal.size
        let page = pageSize
        if cursor < top { top = cursor }
        if cursor >= top + page { top = cursor - page + 1 }
        top = min(top, max(0, visible.count - page))

        var lines = [header(columns), promptLine(columns), divider(columns)]

        if visible.isEmpty {
            lines.append(Style.dim(allRecords.isEmpty ? "  No transcripts found" : "  Nothing matches that"))
            lines.append(contentsOf: Array(repeating: "", count: max(0, page * linesPerRow - 1)))
        } else {
            for offset in 0..<page {
                let position = top + offset
                guard position < visible.count else {
                    lines.append(contentsOf: ["", ""])
                    continue
                }
                lines.append(contentsOf: row(visible[position], isCursor: position == cursor, columns: columns))
            }
        }

        lines.append(divider(columns))
        lines.append(infoLine(columns))
        lines.append(hintLine(columns))
        terminal.draw(lines)
    }

    private func header(_ columns: Int) -> String {
        let bytes = visible.reduce(0) { $0 + $1.byteCount }
        let scope = query.provider?.displayName ?? "All"
        let counts = visible.count == allRecords.count
            ? "\(allRecords.count) sessions"
            : "\(visible.count)/\(allRecords.count) sessions"
        let right = "\(scope) · \(query.sort.label) · \(ByteFormat.short(bytes))"
        let left = Style.bold("session-engram") + Style.dim("  \(counts)")
        let gap = max(1, columns - TextWidth.of("session-engram  \(counts)") - TextWidth.of(right))
        return left + String(repeating: " ", count: gap) + Style.dim(right)
    }

    /// The text filter, with a caret while it is being typed.
    private func promptLine(_ columns: Int) -> String {
        let caret = mode == .searching ? "█" : ""
        let text = query.text.isEmpty && mode != .searching
            ? Style.dim("/ to search")
            : Style.cyan("/") + " " + query.text + caret
        return "  " + TextWidth.truncate(text, to: columns - 4)
    }

    private func divider(_ columns: Int) -> String {
        Style.dim(String(repeating: "─", count: columns))
    }

    private func row(_ record: SessionRecord, isCursor: Bool, columns: Int) -> [String] {
        let marker = isCursor ? "❯" : " "
        let box = selection.contains(record.id) ? Style.green("◉") : Style.dim("○")
        let title = TextWidth.pad(TextWidth.oneLine(record.title), to: max(10, columns - 6))

        let meta = [
            String(record.sessionID.prefix(8)),
            record.provider.rawValue.padded(to: 6),
            Format.relative(record.updatedAt).padded(to: 10),
            "\(record.messageCount)t".padded(to: 5),
            ByteFormat.short(record.byteCount).padded(to: 6),
        ].joined(separator: "  ")
        let archived = record.isArchived ? Style.yellow("  archived") : ""
        let detail = TextWidth.truncate("\(meta)  \(record.directoryLabel)", to: max(10, columns - 8))

        let first = "\(marker) \(box) " + (isCursor ? Style.bold(title) : title)
        let second = "    " + Style.dim(detail) + archived
        return [first, second]
    }

    /// Status, or the pending delete confirmation.
    private func infoLine(_ columns: Int) -> String {
        if mode == .confirmingDelete {
            return "  " + Style.yellow("Move \(targets.count) session(s) to the Trash?")
                + Style.dim("  y to confirm, any other key to cancel")
        }
        if let status {
            return "  " + Style.cyan(TextWidth.truncate(status, to: columns - 4))
        }
        return ""
    }

    private func hintLine(_ columns: Int) -> String {
        let left = selection.isEmpty ? "" : Style.bold("\(selection.count) selected") + "  "
        let hints = switch mode {
        case .searching: "type to filter · enter done · esc clear"
        default:
            "↑↓ move · space select · / search · enter resume · c copy · d trash · s sort · f filter · q quit"
        }
        return "  " + left + Style.dim(TextWidth.truncate(hints, to: max(20, columns - TextWidth.of(left) - 4)))
    }
}
