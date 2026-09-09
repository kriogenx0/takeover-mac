//
//  SystemOps.swift
//  Takeover
//
//  Native replacements for the old "route everything through
//  `osascript -e "do shell script …"`" approach:
//
//    • Proc            – run a known tool with an argv array (no shell, no quoting)
//    • Shell           – run a TRUSTED command line via /bin/sh (catalog/settings text only)
//    • PrivilegedShell – run one argv command with administrator privileges (one auth prompt)
//    • FileOps         – FileManager wrappers that transparently escalate on EPERM
//

import Foundation

enum SystemOpError: LocalizedError {
    case launchFailed(tool: String, underlying: Error)
    case commandFailed(tool: String, args: [String], status: Int32, message: String)
    case privilegedFailed(argv: [String], status: Int32, message: String)
    case fileOperationFailed(operation: String, path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(tool, underlying):
            return "Couldn't launch \(tool): \(underlying.localizedDescription)"
        case let .commandFailed(tool, _, status, message):
            let detail = message.isEmpty ? "" : " — \(message)"
            return "\((tool as NSString).lastPathComponent) exited with code \(status)\(detail)"
        case let .privilegedFailed(argv, status, message):
            let name = (argv.first as NSString?)?.lastPathComponent ?? "command"
            if message.contains("-128") || message.lowercased().contains("user canceled") {
                return "Authentication was cancelled."
            }
            let detail = message.isEmpty ? "" : " — \(message)"
            return "\(name) (privileged) exited with code \(status)\(detail)"
        case let .fileOperationFailed(operation, path, underlying):
            return "\(operation) failed for \(path): \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Proc

/// Runs an executable directly with an argument vector — no shell is involved,
/// so paths and values never need escaping and can't be re-interpreted.
enum Proc {
    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var ok: Bool { exitCode == 0 }
        var combined: String {
            [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = nil

        do {
            try process.run()
        } catch {
            return Result(stdout: "", stderr: "failed to launch \(launchPath): \(error.localizedDescription)", exitCode: -1)
        }

        // Drain both pipes concurrently so a large stream on one can't deadlock the child.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "takeover.proc.io", attributes: .concurrent)
        group.enter()
        queue.async { outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data(); group.leave() }
        group.enter()
        queue.async { errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data(); group.leave() }
        process.waitUntilExit()
        group.wait()

        return Result(
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: process.terminationStatus
        )
    }

    /// Like `run`, but throws `SystemOpError.commandFailed` on a non-zero exit and returns stdout.
    @discardableResult
    static func require(_ launchPath: String, _ args: [String]) throws -> String {
        let result = run(launchPath, args)
        guard result.ok else {
            throw SystemOpError.commandFailed(
                tool: launchPath, args: args, status: result.exitCode,
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result.stdout
    }
}

// MARK: - Shell

/// Runs a command line that is authored by us or by the user's own settings/catalog
/// (e.g. `killall Finder`, a `defaults …` snippet, `git pull`). Never pass a
/// caller-controlled filesystem path through here — use `Proc` or `FileOps`.
enum Shell {
    struct Output {
        let text: String
        let exitCode: Int32
        var ok: Bool { exitCode == 0 }
    }

    @discardableResult
    static func runTrusted(_ command: String) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = nil

        do {
            try process.run()
        } catch {
            return Output(text: "failed to launch: \(error.localizedDescription)", exitCode: -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(
            text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: process.terminationStatus
        )
    }
}

// MARK: - PrivilegedShell

/// Runs a single command, as its own argv, with administrator privileges. The
/// arguments are handed to AppleScript via `on run argv` and shell-quoted with
/// `quoted form of`, so there is no shell- or AppleScript-injection surface even
/// when a path contains quotes, spaces or `$(…)`.
enum PrivilegedShell {
    private static let runner = """
    on run argv
        set cmd to ""
        repeat with a in argv
            set cmd to cmd & quoted form of (a as text) & " "
        end repeat
        do shell script cmd with administrator privileges
    end run
    """

    @discardableResult
    static func run(_ argv: [String]) throws -> String {
        precondition(!argv.isEmpty, "PrivilegedShell.run requires at least the tool path")

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("takeover-\(UUID().uuidString).applescript")
        do {
            try runner.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            throw SystemOpError.launchFailed(tool: "osascript", underlying: error)
        }
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let result = Proc.run("/usr/bin/osascript", [scriptURL.path] + argv)
        guard result.ok else {
            throw SystemOpError.privilegedFailed(
                argv: argv, status: result.exitCode,
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result.stdout
    }
}

// MARK: - FileOps

/// Thin, native FileManager operations. Each mutating call first tries the
/// unprivileged path and, only if it's blocked by permissions and
/// `allowPrivileged` is set, retries the same operation via `PrivilegedShell`
/// (which prompts for authentication).
enum FileOps {
    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func makeDirectory(_ path: String, allowPrivileged: Bool = false) throws {
        if exists(path) { return }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            try escalateOrThrow(error, operation: "Create directory", path: path, allowPrivileged: allowPrivileged) {
                try PrivilegedShell.run(["/bin/mkdir", "-p", path])
            }
        }
    }

    static func move(from source: String, to destination: String, allowPrivileged: Bool = false) throws {
        do {
            if exists(destination) || isSymlink(destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.moveItem(atPath: source, toPath: destination)
        } catch {
            try escalateOrThrow(error, operation: "Move", path: source, allowPrivileged: allowPrivileged) {
                try PrivilegedShell.run(["/bin/mv", "-f", source, destination])
            }
        }
    }

    static func copy(from source: String, to destination: String, allowPrivileged: Bool = false) throws {
        do {
            if exists(destination) || isSymlink(destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.copyItem(atPath: source, toPath: destination)
        } catch {
            try escalateOrThrow(error, operation: "Copy", path: source, allowPrivileged: allowPrivileged) {
                try PrivilegedShell.run(["/usr/bin/ditto", source, destination])
            }
        }
    }

    static func remove(_ path: String, allowPrivileged: Bool = false) throws {
        guard exists(path) || isSymlink(path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            try escalateOrThrow(error, operation: "Remove", path: path, allowPrivileged: allowPrivileged) {
                try PrivilegedShell.run(["/bin/rm", "-rf", path])
            }
        }
    }

    static func symlink(at linkPath: String, to target: String, allowPrivileged: Bool = false) throws {
        do {
            try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
        } catch {
            try escalateOrThrow(error, operation: "Create symlink", path: linkPath, allowPrivileged: allowPrivileged) {
                try PrivilegedShell.run(["/bin/ln", "-s", target, linkPath])
            }
        }
    }

    // MARK: Escalation plumbing

    private static func escalateOrThrow(
        _ error: Error, operation: String, path: String,
        allowPrivileged: Bool, _ privilegedRetry: () throws -> Void
    ) throws {
        guard allowPrivileged, isPermissionError(error) else {
            throw SystemOpError.fileOperationFailed(operation: operation, path: path, underlying: error)
        }
        try privilegedRetry()
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let posixCodes = Set([EPERM, EACCES, EROFS].map { Int($0) })

        if nsError.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, posixCodes.contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, posixCodes.contains(underlying.code) {
            return true
        }
        return false
    }
}
