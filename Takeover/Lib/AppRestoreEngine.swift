import Foundation
import AppKit

enum AppRestoreOutcome: Equatable {
    case installed(String)
    case alreadyPresent
    case skipped(String)
    case failed(String)
    case needsHomebrew

    var label: String {
        switch self {
        case .installed(let s): return "Installed \(s)"
        case .alreadyPresent:   return "Already installed"
        case .skipped(let s):   return "Skipped — \(s)"
        case .failed(let s):    return "Failed — \(s)"
        case .needsHomebrew:    return "Homebrew required"
        }
    }

    var ok: Bool {
        switch self {
        case .installed, .alreadyPresent: return true
        default: return false
        }
    }
}

/// Installs the apps in a restored `Profile`: Homebrew casks primarily, the
/// existing local-installer-folder flow as a fallback. Mac App Store (`mas`) is
/// reserved for a later pass.
enum AppRestoreEngine {

    static func brewURL() -> URL? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        let which = Proc.run("/usr/bin/which", ["brew"])
        if which.ok, !which.stdout.isEmpty {
            return URL(fileURLWithPath: which.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static var homebrewInstalled: Bool { brewURL() != nil }

    /// One app. Synchronous (each brew/installer call blocks) — run off the main
    /// thread from the caller.
    static func install(_ app: Profile.AppEntry, localFolder: String?) -> AppRestoreOutcome {
        switch app.source {
        case .brew:
            guard let brew = brewURL() else { return .needsHomebrew }
            guard let cask = app.cask?.trimmingCharacters(in: .whitespaces), !cask.isEmpty else {
                return .failed("no Homebrew cask id set")
            }
            if Proc.run(brew.path, ["list", "--cask", cask]).ok { return .alreadyPresent }

            let r = Proc.run(brew.path, ["install", "--cask", cask])
            if r.ok || r.combined.localizedCaseInsensitiveContains("already installed") {
                return .installed(cask)
            }
            return .failed(String(r.combined.prefix(300)))

        case .local:
            guard let folder = localFolder, !folder.isEmpty else {
                return .skipped("set a local installer folder in the Applications tab")
            }
            let discovered = AppInstallerEngine.scan(at: folder)
            guard let match = discovered.first(where: { $0.name.caseInsensitiveCompare(app.name) == .orderedSame }) else {
                return .skipped("\(app.name) not found in \(folder)")
            }
            if match.isInstalled() { return .alreadyPresent }
            let res = AppInstallerEngine.install(match)
            return res.success ? .installed(app.name) : .failed(res.message)

        case .mas:
            return .skipped("Mac App Store restore isn't wired up yet")
        }
    }

    /// Opens Terminal running the official Homebrew installer.
    static func launchHomebrewInstall() {
        let cmd = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let osa = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", osa]
        try? p.run()
    }
}
