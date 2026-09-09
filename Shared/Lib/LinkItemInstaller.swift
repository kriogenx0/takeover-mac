//
//  LinkItemInstaller.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import Foundation

struct LinkItemInstaller {

    /// Installs a LinkItem by creating a backup and symlink
    @MainActor
    static func install(linkItem: LinkItem) {
        // Check if we have Full Disk Access permissions
        if !PermissionsHelper.checkAndRequestPermissions() {
            print("Installation cancelled: Full Disk Access required")
            return
        }

        // Generate the full destination path (backup location in iCloud)
        let toPath = "\(Config.expandedBackupPath)/\(linkItem.to)"

        // Expand the from path (original app location)
        let fromPath = PathUtility.expandTildeToRealHome(linkItem.from)

        // Use shell commands to check existence (bypasses sandbox restrictions)
        let escapedFromPath = fromPath.replacingOccurrences(of: "'", with: "'\\''")
        let escapedToPath = toPath.replacingOccurrences(of: "'", with: "'\\''")

        let fromExistsResult = Linker.shell("test -e '\(escapedFromPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)
        let toExistsResult = Linker.shell("test -e '\(escapedToPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)

        let fromExists = (fromExistsResult == "yes")
        let toExists = (toExistsResult == "yes")

        var isFromSymlink = false
        var isToSymlink = false

        if fromExists {
            let symlinkCheck = Linker.shell("test -L '\(escapedFromPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)
            isFromSymlink = (symlinkCheck == "yes")
        }

        if toExists {
            let symlinkCheck = Linker.shell("test -L '\(escapedToPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)
            isToSymlink = (symlinkCheck == "yes")
        }

        // Case 1: Both exist and neither is a symlink - rename old backup and proceed
        if fromExists && !isFromSymlink && toExists && !isToSymlink {
            print("Both locations exist. Renaming old backup at '\(toPath)'")

            // Generate a timestamped name for the old backup
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let oldBackupPath = "\(toPath)-old-\(timestamp)"

            // Try to rename the old backup
            let escapedToPathForOsascript = toPath.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedOldBackupPath = oldBackupPath.replacingOccurrences(of: "\"", with: "\\\"")
            let mvScript = "do shell script \"mv \\\"\(escapedToPathForOsascript)\\\" \\\"\(escapedOldBackupPath)\\\"\""
            let mvResult = Linker.shell("osascript -e '\(mvScript)'")
            print("DEBUG: mv result: '\(mvResult)'")

            // Verify the old backup was renamed
            let verifyResult = Linker.shell("test -e '\(escapedToPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)
            if verifyResult == "yes" {
                print("Error: Failed to rename old backup at '\(toPath)'")
                print("Old backup has been kept at: \(oldBackupPath)")
                print("You can manually delete it later using Finder.")
            } else {
                print("Old backup renamed to: \(oldBackupPath)")
                print("You can delete it later using Finder if no longer needed.")
            }
        }

        // Case 2: From exists and is not a symlink - move it to backup location
        if fromExists && !isFromSymlink {
            print("Moving '\(fromPath)' to '\(toPath)'")

            // Create parent directory if needed using osascript (has proper permissions)
            let parentDir = (toPath as NSString).deletingLastPathComponent
            let escapedParentDir = parentDir.replacingOccurrences(of: "\"", with: "\\\"")
            let createDirScript = "do shell script \"mkdir -p \\\"\(escapedParentDir)\\\"\""
            print("DEBUG: Creating directory with osascript")
            let osascriptResult = Linker.shell("osascript -e '\(createDirScript)'")
            if !osascriptResult.isEmpty {
                print("DEBUG: osascript result: \(osascriptResult)")
            }

            // Copy the file/folder using ditto (macOS native tool that handles permissions better)
            let escapedFromForOsascript = fromPath.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedToForOsascript = toPath.replacingOccurrences(of: "\"", with: "\\\"")
            let copyScript = "do shell script \"ditto \\\"\(escapedFromForOsascript)\\\" \\\"\(escapedToForOsascript)\\\"\""
            print("DEBUG: Copying with osascript and ditto")
            let cpResult = Linker.shell("osascript -e '\(copyScript)'").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cpResult.isEmpty && cpResult.contains("error") {
                print("Error copying file: \(cpResult)")
                return
            }
            print("DEBUG: Copy successful")

            // Remove the original - use sudo only for system paths
            let needsSudo = fromPath.hasPrefix("/Library/") || fromPath.hasPrefix("/System/") || fromPath.hasPrefix("/Applications/")
            let removeScript = needsSudo
                ? "do shell script \"rm -rf \\\"\(escapedFromForOsascript)\\\"\" with administrator privileges"
                : "do shell script \"rm -rf \\\"\(escapedFromForOsascript)\\\"\""
            print("DEBUG: Removing original with osascript\(needsSudo ? " and sudo" : "")")
            let rmResult = Linker.shell("osascript -e '\(removeScript)'")
            print("DEBUG: Remove result: '\(rmResult)'")

            // Verify removal was successful
            var verifyRemovalResult = Linker.shell("test -e '\(escapedFromPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)

            // If removal failed and we didn't use sudo, try again with sudo
            if verifyRemovalResult == "yes" && !needsSudo {
                print("DEBUG: Regular removal failed, trying with administrator privileges")
                let removeScriptSudo = "do shell script \"rm -rf \\\"\(escapedFromForOsascript)\\\"\" with administrator privileges"
                let rmResultSudo = Linker.shell("osascript -e '\(removeScriptSudo)'")
                print("DEBUG: Remove with sudo result: '\(rmResultSudo)'")

                // Check if password was cancelled
                if rmResultSudo.contains("-60005") || rmResultSudo.contains("incorrect") {
                    print("ERROR: Password prompt was cancelled or incorrect.")
                    print("The backup was created successfully, but the original directory couldn't be removed.")
                    print("Please manually remove the original directory:")
                    print("  Open Terminal and run:")
                    print("  sudo rm -rf \\\"\(fromPath)\\\"")
                    return
                }

                // Check again
                verifyRemovalResult = Linker.shell("test -e '\(escapedFromPath)' && echo 'yes' || echo 'no'").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if verifyRemovalResult == "yes" {
                print("Error: Failed to remove original at '\(fromPath)'. The directory still exists.")
                print("The backup was created successfully at '\(toPath)'")
                print("Please manually remove the original directory using Terminal:")
                print("  sudo rm -rf \\\"\(fromPath)\\\"")
                return
            }
            print("DEBUG: Remove successful")
        }

        // Case 3: Create symlink from original location to backup location
        print("Creating symlink at '\(fromPath)' -> '\(toPath)'")

        // Create symlink - use sudo only for system paths
        let escapedFromForSymlink = fromPath.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedToForSymlink = toPath.replacingOccurrences(of: "\"", with: "\\\"")
        let needsSudoForSymlink = fromPath.hasPrefix("/Library/") || fromPath.hasPrefix("/System/") || fromPath.hasPrefix("/Applications/")
        let symlinkScript = needsSudoForSymlink
            ? "do shell script \"ln -s \\\"\(escapedToForSymlink)\\\" \\\"\(escapedFromForSymlink)\\\"\" with administrator privileges"
            : "do shell script \"ln -s \\\"\(escapedToForSymlink)\\\" \\\"\(escapedFromForSymlink)\\\"\""
        print("DEBUG: Creating symlink with osascript\(needsSudoForSymlink ? " and sudo" : "")")
        let symlinkResult = Linker.shell("osascript -e '\(symlinkScript)'").trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: Symlink result: '\(symlinkResult)'")
        if !symlinkResult.isEmpty && symlinkResult.contains("error") {
            print("Error creating symlink: \(symlinkResult)")
            return
        }
        print("DEBUG: Symlink created successfully")

        // Verify symlink was created
        let verifyScript = "test -L '\(escapedFromPath)' && echo 'yes' || echo 'no'"
        let verifyResult = Linker.shell(verifyScript).trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: Symlink verification: \(verifyResult)")

        // Run defaults command if present
        if !linkItem.defaults.isEmpty {
            let result = Linker.shell(linkItem.defaults)
            print("Defaults command result: \(result)")
        }
    }

    /// Uninstalls a LinkItem by removing the symlink
    @MainActor
    static func uninstall(linkItem: LinkItem) {
        // Check if we have Full Disk Access permissions
        if !PermissionsHelper.checkAndRequestPermissions() {
            print("Uninstallation cancelled: Full Disk Access required")
            return
        }

        // Delete the symlink at the "from" path
        let fromPath = PathUtility.expandTildeToRealHome(linkItem.from)
        let escapedPath = fromPath.replacingOccurrences(of: "\"", with: "\\\"")

        // Use sudo only for system paths
        let needsSudo = fromPath.hasPrefix("/Library/") || fromPath.hasPrefix("/System/") || fromPath.hasPrefix("/Applications/")
        let uninstallScript = needsSudo
            ? "do shell script \"rm -rf \\\"\(escapedPath)\\\"\" with administrator privileges"
            : "do shell script \"rm -rf \\\"\(escapedPath)\\\"\""

        let result = Linker.shell("osascript -e '\(uninstallScript)'")
        print("Uninstall result: \(result)")
    }
}
