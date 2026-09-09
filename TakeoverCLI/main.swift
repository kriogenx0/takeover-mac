import Darwin
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

// Non-interactive CLI mode when arguments are provided
if !args.isEmpty {
    do {
        let links = try loadSettings()
        CLI.run(args: args, links: links)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

// Interactive TUI mode (no arguments)
let terminal = RawTerminal()

// Restore terminal on Ctrl-C
signal(SIGINT) { _ in
    var t = termios()
    tcgetattr(STDIN_FILENO, &t)
    t.c_lflag |= tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
    print("\u{001B}[?25h", terminator: "")  // show cursor
    fflush(stdout)
    exit(0)
}

do {
    let links = try loadSettings()

    if links.isEmpty {
        print("No links configured in \(Config.settingsPath)")
        print("Add entries to your takeover-settings.yaml file.")
        exit(0)
    }

    terminal.enable()
    defer { terminal.disable() }

    var menu = Menu(terminal: terminal, links: links)
    menu.run()

} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
