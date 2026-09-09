import Darwin
import Foundation

// MARK: - ANSI codes

enum ANSI {
    static let reset      = "\u{001B}[0m"
    static let bold       = "\u{001B}[1m"
    static let dim        = "\u{001B}[2m"
    static let green      = "\u{001B}[32m"
    static let red        = "\u{001B}[31m"
    static let clearScreen = "\u{001B}[2J\u{001B}[H"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
}

// MARK: - Key input

enum Key {
    case up, down, enter, escape, char(Character), other
}

// MARK: - Terminal raw mode

final class RawTerminal {
    private var originalTermios = termios()
    private(set) var isRaw = false

    func enable() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        withUnsafeMutableBytes(of: &raw.c_cc) { ptr in
            ptr[16] = 1  // VMIN  – block until 1 byte available
            ptr[17] = 0  // VTIME – no timeout
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRaw = true
        output(ANSI.hideCursor)
    }

    func disable() {
        guard isRaw else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        isRaw = false
        output(ANSI.showCursor)
    }

    func readKey() -> Key {
        var c: UInt8 = 0
        guard read(STDIN_FILENO, &c, 1) == 1 else { return .other }

        if c == 27 {  // ESC – try to read arrow key sequence
            let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
            fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
            var a: UInt8 = 0
            var b: UInt8 = 0
            let n1 = read(STDIN_FILENO, &a, 1)
            let n2 = read(STDIN_FILENO, &b, 1)
            fcntl(STDIN_FILENO, F_SETFL, flags)

            if n1 == 1, n2 == 1, a == 91 {
                switch b {
                case 65: return .up
                case 66: return .down
                default: break
                }
            }
            return .escape
        }

        switch c {
        case 10, 13:
            return .enter
        default:
            return .char(Character(Unicode.Scalar(c)))
        }
    }

    func output(_ s: String) {
        Swift.print(s, terminator: "")
        fflush(stdout)
    }

    func outputLine(_ s: String = "") {
        Swift.print(s)
        fflush(stdout)
    }
}
