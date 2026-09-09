import Darwin
import Foundation

struct Installer {

    // MARK: - Status

    static func isInstalled(_ link: LinkConfig) -> Bool {
        isSymlink(atPath: PathUtility.expandTildeToRealHome(link.from))
    }

    static func isSymlink(atPath path: String) -> Bool {
        var st = Darwin.stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    // MARK: - Shell helpers

    /// Runs a command, captures and returns its output + exit code.
    @discardableResult
    static func shell(_ command: String) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, task.terminationStatus)
    }

    /// Runs a command with the terminal inherited (stdout/stderr visible, stdin works for sudo).
    @discardableResult
    static func run(_ command: String) -> Int32 {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

    // MARK: - Install

    static func install(_ link: LinkConfig) -> Result<Void, InstallError> {
        let fromPath = PathUtility.expandTildeToRealHome(link.from)
        let toPath = "\(Config.expandedBackupPath)/\(link.to)"

        if isSymlink(atPath: fromPath) {
            return .failure(.alreadyInstalled)
        }

        let fm = FileManager.default
        let fromExists = fm.fileExists(atPath: fromPath)
        let toExists = fm.fileExists(atPath: toPath)

        let escapedFrom = escaped(fromPath)
        let escapedTo = escaped(toPath)
        let needsSudo = requiresSudo(fromPath)

        // Ensure backup parent directory exists
        let parentDir = (toPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // If both locations exist and neither is a symlink, rename the old backup
        if fromExists && toExists && !isSymlink(atPath: toPath) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd-HHmmss"
            let oldBackup = "\(toPath)-old-\(df.string(from: Date()))"
            run("mv '\(escapedTo)' '\(escaped(oldBackup))'")
        }

        // Move original to backup location
        if fromExists && !isSymlink(atPath: fromPath) {
            let cmd = needsSudo
                ? "sudo mv '\(escapedFrom)' '\(escapedTo)'"
                : "mv '\(escapedFrom)' '\(escapedTo)'"
            let code = run(cmd)
            if code != 0 { return .failure(.moveFailed) }
        }

        // Create symlink: from → to (backup)
        let linkCmd = needsSudo
            ? "sudo ln -s '\(escapedTo)' '\(escapedFrom)'"
            : "ln -s '\(escapedTo)' '\(escapedFrom)'"
        let code = run(linkCmd)
        if code != 0 { return .failure(.symlinkFailed) }

        // Run defaults command if present
        if let defaults = link.defaults, !defaults.isEmpty {
            shell(defaults)
        }

        return .success(())
    }

    // MARK: - Uninstall

    static func uninstall(_ link: LinkConfig) -> Result<Void, InstallError> {
        let fromPath = PathUtility.expandTildeToRealHome(link.from)

        guard isSymlink(atPath: fromPath) else {
            return .failure(.notInstalled)
        }

        let needsSudo = requiresSudo(fromPath)
        let cmd = needsSudo
            ? "sudo rm '\(escaped(fromPath))'"
            : "rm '\(escaped(fromPath))'"
        let code = run(cmd)
        return code == 0 ? .success(()) : .failure(.removeFailed)
    }

    // MARK: - Helpers

    private static func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func requiresSudo(_ path: String) -> Bool {
        path.hasPrefix("/Library/") || path.hasPrefix("/System/") || path.hasPrefix("/Applications/")
    }
}

enum InstallError: LocalizedError {
    case alreadyInstalled
    case notInstalled
    case moveFailed
    case symlinkFailed
    case removeFailed

    var errorDescription: String? {
        switch self {
        case .alreadyInstalled: return "Already installed"
        case .notInstalled:     return "Not installed (no symlink found)"
        case .moveFailed:       return "Failed to move original to backup location"
        case .symlinkFailed:    return "Failed to create symlink"
        case .removeFailed:     return "Failed to remove symlink"
        }
    }
}
