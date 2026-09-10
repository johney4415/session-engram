import Foundation

/// Raw-mode terminal I/O for the interactive browser.
///
/// Everything is drawn to `/dev/tty` instead of stdout, so a session's resume
/// command can still be printed on stdout and captured by a pipe or `$(…)`.
final class Terminal {
    enum Key: Equatable {
        case up, down, pageUp, pageDown, home, end
        case enter, escape, backspace
        case character(Character)
        case interrupt
        case unknown
    }

    private let tty: Int32
    private var saved = termios()
    private var isRaw = false

    /// Fails when the process has no controlling terminal, which is how a piped or
    /// non-interactive run is detected.
    init?() {
        let fd = open("/dev/tty", O_RDWR)
        guard fd >= 0 else { return nil }
        tty = fd
    }

    deinit {
        restore()
        close(tty)
    }

    var size: (rows: Int, columns: Int) {
        var window = winsize()
        guard ioctl(tty, UInt(TIOCGWINSZ), &window) == 0, window.ws_row > 0 else {
            return (24, 80)
        }
        return (Int(window.ws_row), max(40, Int(window.ws_col)))
    }

    /// Whether there is a controlling terminal to draw on at all.
    static var isAvailable: Bool {
        let fd = open("/dev/tty", O_RDWR)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    /// Colour is skipped when `NO_COLOR` is set, following the informal convention.
    static let usesColor = ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    // MARK: - Session

    func start() {
        guard !isRaw else { return }
        tcgetattr(tty, &saved)
        var raw = saved
        cfmakeraw(&raw)
        // VMIN 1 / VTIME 0: every read blocks until at least one byte arrives.
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        tcsetattr(tty, TCSAFLUSH, &raw)
        isRaw = true
        // Alternate screen, so quitting leaves the scrollback the user had before.
        write("\u{1B}[?1049h\u{1B}[?25l")
    }

    func restore() {
        guard isRaw else { return }
        write("\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(tty, TCSAFLUSH, &saved)
        isRaw = false
    }

    // MARK: - Output

    func write(_ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer -> Int in
                Darwin.write(tty, buffer.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard written > 0 else { break }
            offset += written
        }
    }

    /// Repaints from the top left, clearing each line as it goes and wiping whatever
    /// the previous frame left below.
    func draw(_ lines: [String]) {
        var frame = "\u{1B}[H"
        for line in lines {
            frame += line + "\u{1B}[K\r\n"
        }
        frame += "\u{1B}[J"
        write(frame)
    }

    // MARK: - Input

    func readKey() -> Key {
        var byte: UInt8 = 0
        guard read(tty, &byte, 1) == 1 else { return .unknown }
        switch byte {
        case 0x03, 0x04: return .interrupt
        case 0x0A, 0x0D: return .enter
        case 0x08, 0x7F: return .backspace
        case 0x1B: return escapeSequence()
        default:
            guard byte >= 0x20 else { return .unknown }
            return .character(character(startingWith: byte))
        }
    }

    /// An escape byte on its own is the Escape key; followed by `[` or `O` it is an
    /// arrow or navigation key, which is why the follow-up read is a short poll.
    private func escapeSequence() -> Key {
        guard let introducer = poll(), introducer == 0x5B || introducer == 0x4F,
              let code = poll()
        else { return .escape }

        switch code {
        case 0x41: return .up
        case 0x42: return .down
        case 0x48: return .home
        case 0x46: return .end
        case 0x35: _ = poll(); return .pageUp
        case 0x36: _ = poll(); return .pageDown
        default: return .unknown
        }
    }

    /// Reassembles a multi-byte UTF-8 character, so a search can be typed in Chinese.
    private func character(startingWith first: UInt8) -> Character {
        var bytes = [first]
        let continuations = switch first {
        case 0xC0...0xDF: 1
        case 0xE0...0xEF: 2
        case 0xF0...0xF7: 3
        default: 0
        }
        for _ in 0..<continuations {
            guard let next = poll() else { break }
            bytes.append(next)
        }
        return String(decoding: bytes, as: UTF8.self).first ?? "?"
    }

    private func poll(timeoutMilliseconds: Int32 = 40) -> UInt8? {
        var descriptor = pollfd(fd: tty, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&descriptor, 1, timeoutMilliseconds) > 0 else { return nil }
        var byte: UInt8 = 0
        guard read(tty, &byte, 1) == 1 else { return nil }
        return byte
    }
}

/// Column arithmetic for terminal output. CJK titles occupy two cells per character,
/// so counting `String` elements would misalign every row.
enum TextWidth {
    static func of(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + width(of: $1) }
    }

    static func truncate(_ text: String, to columns: Int) -> String {
        guard columns > 0 else { return "" }
        guard of(text) > columns else { return text }
        var result = ""
        var used = 0
        for character in text {
            let cell = of(String(character))
            if used + cell > columns - 1 { break }
            result.append(character)
            used += cell
        }
        return result + "…"
    }

    static func pad(_ text: String, to columns: Int) -> String {
        let clipped = truncate(text, to: columns)
        let missing = columns - of(clipped)
        return missing > 0 ? clipped + String(repeating: " ", count: missing) : clipped
    }

    /// Collapses the whitespace in a title, which can span several lines when the
    /// session opened with a pasted block of text.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    private static func width(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0x0300...0x036F: return 0
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x1F300...0x1F9FF, 0x20000...0x3FFFD:
            return 2
        default: return 1
        }
    }
}

/// ANSI styling, reduced to no-ops when colour is off.
enum Style {
    static func bold(_ text: String) -> String { wrap(text, "1") }
    static func dim(_ text: String) -> String { wrap(text, "2") }
    static func reverse(_ text: String) -> String { wrap(text, "7") }
    static func green(_ text: String) -> String { wrap(text, "32") }
    static func yellow(_ text: String) -> String { wrap(text, "33") }
    static func cyan(_ text: String) -> String { wrap(text, "36") }

    private static func wrap(_ text: String, _ code: String) -> String {
        Terminal.usesColor ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}
