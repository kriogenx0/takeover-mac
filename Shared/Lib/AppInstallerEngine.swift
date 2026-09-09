import Foundation

enum AppFileType {
    case zip, dmg, app, pkg

    var systemImage: String {
        switch self {
        case .zip: return "archivebox"
        case .dmg: return "opticaldiscdrive"
        case .app: return "app.badge"
        case .pkg: return "shippingbox"
        }
    }

    var label: String {
        switch self {
        case .zip: return "ZIP"
        case .dmg: return "DMG"
        case .app: return "APP"
        case .pkg: return "PKG"
        }
    }
}

struct DiscoveredApp: Identifiable {
    var id: String { fileURL.path }
    var name: String
    var fileURL: URL
    var fileType: AppFileType

    func isInstalled(resolvedName: String? = nil) -> Bool {
        let n = resolvedName ?? name
        return FileManager.default.fileExists(atPath: "/Applications/\(n).app")
    }
}

struct AppInstallerEngine {

    static func scan(at path: String) -> [DiscoveredApp] {
        let expanded = PathUtility.expandTildeToRealHome(path)
        let dirURL = URL(fileURLWithPath: expanded)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                let ext = url.pathExtension.lowercased()
                let baseName = url.deletingPathExtension().lastPathComponent
                switch ext {
                case "zip": return DiscoveredApp(name: baseName, fileURL: url, fileType: .zip)
                case "dmg": return DiscoveredApp(name: baseName, fileURL: url, fileType: .dmg)
                case "app": return DiscoveredApp(name: baseName, fileURL: url, fileType: .app)
                case "pkg": return DiscoveredApp(name: baseName, fileURL: url, fileType: .pkg)
                default: return nil
                }
            }
    }

    // Returns (success, message, installedAppName) — installedAppName is the bundle name without .app
    static func install(_ app: DiscoveredApp) -> (success: Bool, message: String, installedName: String?) {
        switch app.fileType {
        case .zip:
            let r = installZip(app); return (r.0, r.1, r.2)
        case .dmg:
            let r = installDmg(app); return (r.0, r.1, r.2)
        case .app:
            let r = copyApp(from: app.fileURL)
            return (r.0, r.1, r.0 ? r.2 : nil)
        case .pkg:
            let r = installPkg(app); return (r.0, r.1, nil)
        }
    }

    static func uninstall(_ app: DiscoveredApp, installedName: String? = nil) -> (success: Bool, message: String) {
        let name = installedName ?? app.name
        let appPath = "/Applications/\(name).app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            return (false, "Not found in /Applications")
        }
        let script = "do shell script \"rm -rf \" & quoted form of \"\(appPath)\" with administrator privileges"
        if let err = runAppleScript(script) { return (false, err) }
        let success = !FileManager.default.fileExists(atPath: appPath)
        return (success, success ? "Uninstalled \(name)" : "Uninstall failed")
    }

    // Writes AppleScript to a temp file and runs via osascript — thread-safe, no shell quoting issues.
    // Returns nil on success, or an error string on failure.
    private static func runAppleScript(_ script: String) -> String? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("takeover-\(UUID().uuidString).applescript")
        guard (try? script.write(to: tmpURL, atomically: true, encoding: .utf8)) != nil else {
            return "Could not write script file"
        }
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let output = Linker.shell("osascript '\(tmpURL.path)'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func installZip(_ app: DiscoveredApp) -> (Bool, String, String?) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("takeover-\(UUID().uuidString)")

        let srcEsc = app.fileURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let dstEsc = tempDir.path.replacingOccurrences(of: "'", with: "'\\''")
        let unzipResult = Linker.shell("ditto -xk '\(srcEsc)' '\(dstEsc)'")
        if unzipResult.lowercased().contains("error") {
            return (false, "Unzip failed: \(unzipResult)", nil)
        }

        guard let appURL = findApp(in: tempDir) else {
            Linker.shell("rm -rf '\(dstEsc)'")
            return (false, "No .app found in zip", nil)
        }

        let appName = appURL.deletingPathExtension().lastPathComponent
        let destPath = "/Applications/\(appName).app"

        if FileManager.default.fileExists(atPath: destPath) {
            Linker.shell("rm -rf '\(dstEsc)'")
            return (false, "\(appName) is already installed", appName)
        }

        let r = copyApp(from: appURL)
        Linker.shell("rm -rf '\(dstEsc)'")
        return (r.0, r.1, appName)
    }

    private static func installDmg(_ app: DiscoveredApp) -> (Bool, String, String?) {
        let escapedPath = app.fileURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let attachOutput = Linker.shell("hdiutil attach '\(escapedPath)' -nobrowse -noverify -plist")

        guard let mountPath = parseMountPoint(from: attachOutput) else {
            return (false, "Could not mount DMG: \(attachOutput.prefix(120))", nil)
        }

        let mountURL = URL(fileURLWithPath: mountPath)
        guard let appURL = findApp(in: mountURL) else {
            Linker.shell("hdiutil detach '\(mountPath)' -quiet")
            return (false, "No .app found in DMG", nil)
        }

        let appName = appURL.deletingPathExtension().lastPathComponent
        let r = copyApp(from: appURL)
        Linker.shell("hdiutil detach '\(mountPath)' -quiet")
        return (r.0, r.1, appName)
    }

    private static func installPkg(_ app: DiscoveredApp) -> (Bool, String) {
        let script = "do shell script \"installer -pkg \" & quoted form of \"\(app.fileURL.path)\" & \" -target /\" with administrator privileges"
        if let err = runAppleScript(script) { return (false, "Install failed: \(err)") }
        return (true, "Installed \(app.name)")
    }

    // Returns (success, message, bundleNameWithoutDotApp)
    private static func copyApp(from appURL: URL) -> (Bool, String, String) {
        let appBundle = appURL.lastPathComponent
        let appName = appURL.deletingPathExtension().lastPathComponent
        let destPath = "/Applications/\(appBundle)"
        let script = "do shell script \"ditto \" & quoted form of \"\(appURL.path)\" & \" \" & quoted form of \"\(destPath)\" with administrator privileges"
        if let err = runAppleScript(script) { return (false, err, appName) }
        let success = FileManager.default.fileExists(atPath: destPath)
        return (success, success ? "Installed \(appName)" : "Installation failed", appName)
    }

    private static func findApp(in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        if let direct = contents.first(where: { $0.pathExtension.lowercased() == "app" }) {
            return direct
        }

        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir, let found = findApp(in: item) { return found }
        }

        return nil
    }

    private static func parseMountPoint(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return output.components(separatedBy: "\n").compactMap { line -> String? in
                let parts = line.components(separatedBy: "\t")
                let point = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
                return point.hasPrefix("/Volumes/") ? point : nil
            }.first
        }

        return entities.compactMap { $0["mount-point"] as? String }
            .first { $0.hasPrefix("/Volumes/") }
    }
}
