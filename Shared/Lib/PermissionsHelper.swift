//
//  PermissionsHelper.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import Foundation
import AppKit

struct PermissionsHelper {

    /// Check if the app has Full Disk Access
    static func hasFullDiskAccess() -> Bool {
        // Try to read a protected file that requires Full Disk Access
        // We'll try to read the user's Safari history database
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let safariHistoryPath = homeDir.appendingPathComponent("Library/Safari/History.db").path

        // Try to check if we can access this file
        let fileManager = FileManager.default
        return fileManager.isReadableFile(atPath: safariHistoryPath)
    }

    /// Show an alert guiding the user to grant Full Disk Access
    @MainActor
    static func showFullDiskAccessAlert() {
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

        Would you like to open System Settings now?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings to Privacy & Security > Full Disk Access
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Check permissions and show alert if needed
    /// Returns true if app has required permissions, false otherwise
    @MainActor
    static func checkAndRequestPermissions() -> Bool {
        if !hasFullDiskAccess() {
            showFullDiskAccessAlert()
            return false
        }
        return true
    }
}
