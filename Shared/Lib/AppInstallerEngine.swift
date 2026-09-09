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

    private static let ditto = "/usr/bin/ditto"
    private static let hdiutil = "/usr/bin/hdiutil"
    private static let installerTool = "/usr/sbin/installer"

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
        do {
            // Unprivileged first (works when /Applications is group-writable),
            // then fall back to an authenticated remove.
            try FileOps.remove(appPath, allowPrivileged: true)
        } catch {
            return (false, error.localizedDescription)
        }
        let success = !FileManager.default.fileExists(atPath: appPath)
        return (success, success ? "Uninstalled \(name)" : "Uninstall failed")
    }

    private static func installZip(_ app: DiscoveredApp) -> (Bool, String, String?) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("takeover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try Proc.require(ditto, ["-x", "-k", app.fileURL.path, tempDir.path])
        } catch {
            return (false, "Unzip failed: \(error.localizedDescription)", nil)
        }

        guard let appURL = findApp(in: tempDir) else {
            return (false, "No .app found in zip", nil)
        }

        let appName = appURL.deletingPathExtension().lastPathComponent
        let destPath = "/Applications/\(appName).app"

        if FileManager.default.fileExists(atPath: destPath) {
            return (false, "\(appName) is already installed", appName)
        }

        let r = copyApp(from: appURL)
        return (r.0, r.1, appName)
    }

    private static func installDmg(_ app: DiscoveredApp) -> (Bool, String, String?) {
        let attach = Proc.run(hdiutil, ["attach", app.fileURL.path, "-nobrowse", "-noverify", "-plist"])
        guard attach.ok, let mountPath = parseMountPoint(from: attach.stdout) else {
            return (false, "Could not mount DMG: \(attach.combined.prefix(160))", nil)
        }
        defer { Proc.run(hdiutil, ["detach", mountPath, "-quiet"]) }

        let mountURL = URL(fileURLWithPath: mountPath)
        guard let appURL = findApp(in: mountURL) else {
            return (false, "No .app found in DMG", nil)
        }

        let appName = appURL.deletingPathExtension().lastPathComponent
        let r = copyApp(from: appURL)
        return (r.0, r.1, appName)
    }

    private static func installPkg(_ app: DiscoveredApp) -> (Bool, String) {
        do {
            try PrivilegedShell.run([installerTool, "-pkg", app.fileURL.path, "-target", "/"])
            return (true, "Installed \(app.name)")
        } catch {
            return (false, "Install failed: \(error.localizedDescription)")
        }
    }

    // Returns (success, message, bundleNameWithoutDotApp)
    private static func copyApp(from appURL: URL) -> (Bool, String, String) {
        let appBundle = appURL.lastPathComponent
        let appName = appURL.deletingPathExtension().lastPathComponent
        let destPath = "/Applications/\(appBundle)"

        // Try an unprivileged copy first; only prompt for authentication if that
        // is actually denied.
        var copied = Proc.run(ditto, [appURL.path, destPath]).ok
        if !copied {
            do {
                try PrivilegedShell.run([ditto, appURL.path, destPath])
                copied = true
            } catch {
                return (false, error.localizedDescription, appName)
            }
        }

        let success = copied && FileManager.default.fileExists(atPath: destPath)
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
