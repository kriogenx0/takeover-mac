import Foundation

struct Menu {
    let terminal: RawTerminal
    var links: [LinkConfig]
    var selected: Int = 0

    mutating func run() {
        while true {
            renderList()
            switch terminal.readKey() {
            case .up:
                if selected > 0 { selected -= 1 }
            case .down:
                if selected < links.count - 1 { selected += 1 }
            case .enter where !links.isEmpty:
                showDetail(for: links[selected])
            case .char("q"), .escape:
                terminal.output(ANSI.clearScreen)
                return
            default:
                break
            }
        }
    }

    // MARK: - List screen

    private func renderList() {
        terminal.output(ANSI.clearScreen)
        terminal.outputLine("\(ANSI.bold)Takeover\(ANSI.reset)")
        terminal.outputLine(String(repeating: "─", count: 40))
        terminal.outputLine()

        for (i, link) in links.enumerated() {
            let installed = Installer.isInstalled(link)
            let cursor = i == selected ? "▶" : " "
            let check  = installed
                ? "\(ANSI.green)✓\(ANSI.reset)"
                : "\(ANSI.dim)·\(ANSI.reset)"
            let name = installed
                ? "\(ANSI.green)\(link.name)\(ANSI.reset)"
                : link.name
            let row = i == selected
                ? "\(ANSI.bold)\(cursor) \(check) \(name)\(ANSI.reset)"
                : "\(cursor) \(check) \(name)"
            terminal.outputLine(row)
        }

        terminal.outputLine()
        terminal.outputLine("\(ANSI.dim)↑↓ navigate  Enter select  q quit\(ANSI.reset)")
    }

    // MARK: - Detail screen

    private func showDetail(for link: LinkConfig) {
        while true {
            let installed = Installer.isInstalled(link)

            terminal.output(ANSI.clearScreen)
            terminal.outputLine("\(ANSI.bold)\(link.name)\(ANSI.reset)")
            terminal.outputLine(String(repeating: "─", count: 40))
            terminal.outputLine()

            let status = installed
                ? "\(ANSI.green)Installed ✓\(ANSI.reset)"
                : "\(ANSI.dim)Not installed\(ANSI.reset)"
            terminal.outputLine("Status:  \(status)")
            terminal.outputLine("From:    \(link.from)")
            terminal.outputLine("To:      \(Config.backupPath)/\(link.to)")
            if let defaults = link.defaults, !defaults.isEmpty {
                terminal.outputLine("Command: \(defaults)")
            }
            terminal.outputLine()

            if installed {
                terminal.outputLine("[u] Uninstall    [b] Back")
            } else {
                terminal.outputLine("[i] Install    [b] Back")
            }

            switch terminal.readKey() {
            case .char("b"), .escape:
                return

            case .char("i") where !installed:
                performAction(label: "Installing \(link.name)") {
                    Installer.install(link)
                }
                return

            case .char("u") where installed:
                performAction(label: "Uninstalling \(link.name)") {
                    Installer.uninstall(link)
                }
                return

            default:
                break
            }
        }
    }

    // MARK: - Action runner

    private func performAction(
        label: String,
        action: () -> Result<Void, InstallError>
    ) {
        terminal.disable()
        terminal.output(ANSI.clearScreen)
        terminal.outputLine("\(label)…")
        terminal.outputLine()

        let result = action()

        switch result {
        case .success:
            terminal.outputLine("\(ANSI.green)✓ Done\(ANSI.reset)")
        case .failure(let error):
            terminal.outputLine("\(ANSI.red)✗ \(error.localizedDescription)\(ANSI.reset)")
        }

        terminal.outputLine()
        terminal.output("Press any key to continue…")
        fflush(stdout)
        terminal.enable()
        _ = terminal.readKey()
    }
}
