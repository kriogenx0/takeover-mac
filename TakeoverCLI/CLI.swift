import Foundation

struct CLI {

    static func run(args: [String], links: [LinkConfig]) {
        switch args.count {
        case 1:
            let cmd = args[0].lowercased()
            switch cmd {
            case "list", "ls":
                listLinks(links)
            case "help", "--help", "-h":
                printUsage()
            default:
                showLink(name: args[0], links: links)
            }
        case 2:
            let name = args[0]
            let action = args[1].lowercased()
            switch action {
            case "install", "enable":
                installLink(name: name, links: links)
            case "uninstall", "disable":
                uninstallLink(name: name, links: links)
            default:
                print("Unknown action '\(args[1])'. Use 'install' or 'uninstall'.")
                printUsage()
                exit(1)
            }
        default:
            printUsage()
            exit(1)
        }
    }

    // MARK: - Commands

    private static func listLinks(_ links: [LinkConfig]) {
        if links.isEmpty {
            print("No links configured.")
            return
        }
        for link in links {
            let status = Installer.isInstalled(link) ? "✓" : "·"
            print("  \(status) \(link.name)")
        }
    }

    private static func showLink(name: String, links: [LinkConfig]) {
        guard let link = find(name: name, in: links) else {
            print("Error: '\(name)' not found.")
            print("")
            listLinks(links)
            exit(1)
        }
        let installed = Installer.isInstalled(link)
        print("\(link.name)")
        print("  Status:  \(installed ? "installed ✓" : "not installed")")
        print("  From:    \(link.from)")
        print("  To:      \(Config.backupPath)/\(link.to)")
        if let defaults = link.defaults, !defaults.isEmpty {
            print("  Command: \(defaults)")
        }
    }

    private static func installLink(name: String, links: [LinkConfig]) {
        guard let link = find(name: name, in: links) else {
            print("Error: '\(name)' not found.")
            exit(1)
        }
        print("Installing \(link.name)…")
        switch Installer.install(link) {
        case .success:
            print("✓ \(link.name) installed.")
        case .failure(let error):
            print("✗ \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func uninstallLink(name: String, links: [LinkConfig]) {
        guard let link = find(name: name, in: links) else {
            print("Error: '\(name)' not found.")
            exit(1)
        }
        print("Uninstalling \(link.name)…")
        switch Installer.uninstall(link) {
        case .success:
            print("✓ \(link.name) uninstalled.")
        case .failure(let error):
            print("✗ \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Helpers

    private static func find(name: String, in links: [LinkConfig]) -> LinkConfig? {
        links.first { $0.name.lowercased() == name.lowercased() }
    }

    static func printUsage() {
        print("""
        Usage: takeover [command]

        No arguments      Interactive TUI menu
        list              List all links with install status
        <name>            Show details for a link
        <name> install    Install (create symlink + backup)
        <name> uninstall  Uninstall (remove symlink)

        Settings: \(Config.settingsPath)
        """)
    }
}
