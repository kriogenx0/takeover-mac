//
//  LinkItemInstaller.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import Foundation

enum LinkInstallError: LocalizedError {
    case fullDiskAccessRequired
    case archiveOldBackupFailed(String)
    case moveToBackupFailed(String)
    case symlinkFailed(String)
    case removeFailed(String)
    case defaultsCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .fullDiskAccessRequired:
            return "Full Disk Access is required to manage this link."
        case let .archiveOldBackupFailed(detail):
            return "Couldn't archive the existing backup: \(detail)"
        case let .moveToBackupFailed(detail):
            return "Couldn't move the original into the backup location: \(detail)"
        case let .symlinkFailed(detail):
            return "Couldn't create the symlink: \(detail)"
        case let .removeFailed(detail):
            return "Couldn't remove the symlink: \(detail)"
        case let .defaultsCommandFailed(detail):
            return "The linked defaults command failed: \(detail)"
        }
    }
}

struct LinkItemInstaller {

    /// Moves the original aside into the iCloud backup location and replaces it
    /// with a symlink. Throws `LinkInstallError` on any failure.
    @MainActor
    static func install(linkItem: LinkItem) throws {
        guard PermissionsHelper.checkAndRequestPermissions() else {
            throw LinkInstallError.fullDiskAccessRequired
        }

        let backupPath = "\(Config.expandedBackupPath)/\(linkItem.to)"
        let originalPath = PathUtility.expandTildeToRealHome(linkItem.from)

        let originalExists = FileOps.exists(originalPath)
        let originalIsSymlink = FileOps.isSymlink(originalPath)
        let backupExists = FileOps.exists(backupPath)
        let backupIsSymlink = FileOps.isSymlink(backupPath)

        // A real original *and* a real backup already sit side by side — archive
        // the stale backup with a timestamp rather than clobbering it.
        if originalExists, !originalIsSymlink, backupExists, !backupIsSymlink {
            let archived = "\(backupPath)-old-\(timestamp())"
            do {
                try FileOps.move(from: backupPath, to: archived, allowPrivileged: true)
                print("Archived existing backup to \(archived)")
            } catch {
                throw LinkInstallError.archiveOldBackupFailed(error.localizedDescription)
            }
        }

        // Move the real original into the backup location.
        if originalExists, !originalIsSymlink {
            let parent = (backupPath as NSString).deletingLastPathComponent
            do {
                try FileOps.makeDirectory(parent, allowPrivileged: true)
                try FileOps.move(from: originalPath, to: backupPath, allowPrivileged: true)
            } catch {
                throw LinkInstallError.moveToBackupFailed(error.localizedDescription)
            }
        }

        // Clear a pre-existing (stale) symlink so createSymbolicLink can succeed.
        if originalIsSymlink {
            do {
                try FileOps.remove(originalPath, allowPrivileged: true)
            } catch {
                throw LinkInstallError.symlinkFailed(error.localizedDescription)
            }
        }

        do {
            try FileOps.symlink(at: originalPath, to: backupPath, allowPrivileged: true)
        } catch {
            throw LinkInstallError.symlinkFailed(error.localizedDescription)
        }
        print("Linked \(originalPath) -> \(backupPath)")

        if !linkItem.defaults.isEmpty {
            let result = Shell.runTrusted(linkItem.defaults)
            if !result.ok {
                throw LinkInstallError.defaultsCommandFailed(result.text)
            }
        }
    }

    /// Removes the symlink at the original location. A no-op if nothing is linked.
    /// Never deletes a real file/directory.
    @MainActor
    static func uninstall(linkItem: LinkItem) throws {
        guard PermissionsHelper.checkAndRequestPermissions() else {
            throw LinkInstallError.fullDiskAccessRequired
        }

        let originalPath = PathUtility.expandTildeToRealHome(linkItem.from)
        guard FileOps.isSymlink(originalPath) else {
            print("Nothing to uninstall — \(originalPath) is not a symlink")
            return
        }

        do {
            try FileOps.remove(originalPath, allowPrivileged: true)
            print("Removed symlink at \(originalPath)")
        } catch {
            throw LinkInstallError.removeFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
