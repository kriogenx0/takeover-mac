//
//  PermissionsHelper.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import Foundation
import AppKit

struct PermissionsHelper {

    enum FullDiskAccessStatus {
        case granted
        /// A protected file exists but the OS refused the read — FDA is off.
        case denied
        /// Couldn't reach a conclusion (no probe file present). Don't block the user on this.
        case unknown
    }

    /// Files that are only readable with Full Disk Access. TCC.db exists on every
    /// normal macOS install; the Safari entries are fallbacks in case it doesn't.
    private static var probePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "Library/Application Support/com.apple.TCC/TCC.db",
            "Library/Safari/CloudTabs.db",
            "Library/Safari/Bookmarks.plist",
        ].map { home.appendingPathComponent($0).path }
    }

    /// Attempt an actual 1-byte read (not just a POSIX permission check, which
    /// `FileManager.isReadableFile` does and which is unreliable for TCC).
    static func fullDiskAccessStatus() -> FullDiskAccessStatus {
        for path in probePaths {
            let url = URL(fileURLWithPath: path)
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                _ = try handle.read(upToCount: 1)
                return .granted
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
                    return .denied
                }
                if error.domain == NSPOSIXErrorDomain,
                   error.code == Int(EPERM) || error.code == Int(EACCES) {
                    return .denied
                }
                // Missing file or any other error: inconclusive, try the next probe.
            }
        }

        // No probe file was readable and none reported a permission error
        // (e.g. fresh account with no Safari data). Don't nag on this.
        return .unknown
    }

    /// Check if the app has Full Disk Access.
    static func hasFullDiskAccess() -> Bool {
        fullDiskAccessStatus() == .granted
    }

    /// So the startup nag fires at most once per launch.
    private static var alertShownThisLaunch = false

    /// Show an alert guiding the user to grant Full Disk Access
    @MainActor
    static func showFullDiskAccessAlert(force: Bool = false) {
        if alertShownThisLaunch && !force { return }
        alertShownThisLaunch = true

        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = """
        Takeover needs Full Disk Access to install and manage symlinks in protected directories.

        To grant access:
        1. Open System Settings
        2. Go to Privacy & Security > Full Disk Access
        3. Click the lock icon and authenticate
        4. Click the '+' button
        5. Navigate to Applications and select Takeover
        6. Restart Takeover
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Called when the app regains focus (e.g. the user just came back from
    /// System Settings after granting access). Once access is confirmed, re-arm
    /// the one-shot guard so that a *later* revocation can alert again — callers
    /// only surface the alert on `.denied`, so this never re-nags a granted app.
    @MainActor
    static func refreshAfterActivation() {
        if hasFullDiskAccess() {
            alertShownThisLaunch = false
        }
    }

    /// Check permissions and show alert if needed.
    /// Returns true if the app can proceed (granted, or the check was inconclusive).
    @MainActor
    static func checkAndRequestPermissions() -> Bool {
        switch fullDiskAccessStatus() {
        case .granted, .unknown:
            return true
        case .denied:
            showFullDiskAccessAlert()
            return false
        }
    }
}
