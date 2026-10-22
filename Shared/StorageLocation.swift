import Foundation
import Yams

/// Where the user keeps their Takeover settings (links, chosen macOS defaults,
/// app installers). Picked on first launch and changeable later in Settings.
enum StorageProvider: String, Codable, CaseIterable, Identifiable {
    case iCloud = "icloud"
    case dropbox
    case takeoverCloud = "takeover_cloud"
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return "iCloud Drive"
        case .dropbox: return "Dropbox"
        case .takeoverCloud: return "Takeover Cloud"
        case .folder: return "A Folder"
        }
    }

    var summary: String {
        switch self {
        case .iCloud: return "Keep settings in iCloud Drive so every Mac on your Apple ID sees them."
        case .dropbox: return "Keep settings in your Dropbox folder."
        case .takeoverCloud: return "Sync settings to your Takeover account. 30-day free trial, then $3/month."
        case .folder: return "Keep settings in a folder you choose, on this Mac or any synced drive."
        }
    }

    var systemImage: String {
        switch self {
        case .iCloud: return "icloud"
        case .dropbox: return "shippingbox"
        case .takeoverCloud: return "cloud"
        case .folder: return "folder"
        }
    }
}

/// The user's storage choice, persisted in a small pointer file outside the
/// settings folder itself so the app and the CLI both find it.
struct StorageLocation: Codable, Equatable {
    var provider: StorageProvider
    /// Only used for `.folder`; tilde-prefixed paths are allowed.
    var folderPath: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case folderPath = "folder_path"
    }

    static let iCloudPath = "~/Library/Mobile Documents/com~apple~CloudDocs/Takeover"
    static let localSupportPath = "~/Library/Application Support/Takeover"
    /// Working copy for Takeover Cloud; the API holds the synced profile.
    static let cloudCachePath = "\(localSupportPath)/Cloud"
    static let defaultFolderPath = "~/Takeover"

    /// Dropbox's modern File Provider location first, then the legacy one.
    static let dropboxCandidates = [
        "~/Library/CloudStorage/Dropbox",
        "~/Dropbox",
    ]

    static var pointerFilePath: String {
        PathUtility.expandTildeToRealHome("\(localSupportPath)/storage.yaml")
    }

    /// Settings folder for this choice, tilde-prefixed when under home.
    var rootPath: String {
        switch provider {
        case .iCloud:
            return Self.iCloudPath
        case .dropbox:
            return "\(Self.dropboxRoot ?? Self.dropboxCandidates[0])/Takeover"
        case .takeoverCloud:
            return Self.cloudCachePath
        case .folder:
            return folderPath ?? Self.defaultFolderPath
        }
    }

    var expandedRootPath: String {
        PathUtility.expandTildeToRealHome(rootPath)
    }

    static var dropboxRoot: String? {
        dropboxCandidates.first { directoryExists($0) }
    }

    static func isAvailable(_ provider: StorageProvider) -> Bool {
        switch provider {
        case .iCloud:
            return directoryExists((iCloudPath as NSString).deletingLastPathComponent)
        case .dropbox:
            return dropboxRoot != nil
        case .takeoverCloud, .folder:
            return true
        }
    }

    private static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: PathUtility.expandTildeToRealHome(path), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    // MARK: - Persistence

    private static var cached: StorageLocation??

    /// The saved choice, or nil before the user has picked one.
    static func load() -> StorageLocation? {
        if let cached { return cached }
        let loaded = readPointerFile()
        cached = .some(loaded)
        return loaded
    }

    private static func readPointerFile() -> StorageLocation? {
        guard let data = FileManager.default.contents(atPath: pointerFilePath),
              let yaml = String(data: data, encoding: .utf8) else {
            return nil
        }
        return try? YAMLDecoder().decode(StorageLocation.self, from: yaml)
    }

    /// The saved choice; before one is saved, the most recently updated
    /// settings found on disk, then the pre-picker default (iCloud when
    /// present, otherwise the local Application Support folder).
    static var current: StorageLocation {
        if let saved = load() { return saved }
        if let found = detectExisting().first { return found.location }
        if isAvailable(.iCloud) { return StorageLocation(provider: .iCloud) }
        return StorageLocation(provider: .folder, folderPath: localSupportPath)
    }

    func save() throws {
        let url = URL(fileURLWithPath: Self.pointerFilePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(self)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        Self.cached = .some(self)
    }
}

/// Takeover settings already on disk, e.g. synced from another Mac before the
/// user has picked a location on this one.
struct DetectedStorage: Equatable, Identifiable {
    var location: StorageLocation
    /// When the settings file was last written, to rank multiple finds.
    var modifiedAt: Date

    var id: String { location.expandedRootPath }
}

extension StorageLocation {
    private static let settingsFileNames = ["takeover-settings.yaml", "mac-defaults.yaml"]

    private static var detectedCache: [DetectedStorage]?

    /// Every known place that already holds Takeover settings, most recently
    /// updated first. Scanned once per launch.
    static func detectExisting() -> [DetectedStorage] {
        if let detectedCache { return detectedCache }
        var seen = Set<String>()
        var found: [DetectedStorage] = []
        for location in detectionCandidates() {
            let root = location.expandedRootPath
            let resolved = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            guard !seen.contains(resolved), let modifiedAt = settingsModifiedAt(in: root) else { continue }
            seen.insert(resolved)
            found.append(DetectedStorage(location: location, modifiedAt: modifiedAt))
        }
        found.sort { $0.modifiedAt > $1.modifiedAt }
        detectedCache = found
        return found
    }

    /// iCloud Drive, Dropbox, other File Provider drives (Google Drive,
    /// OneDrive, Box…), then plain folders, in that order of preference.
    private static func detectionCandidates() -> [StorageLocation] {
        var candidates = [StorageLocation(provider: .iCloud)]
        if dropboxRoot != nil { candidates.append(StorageLocation(provider: .dropbox)) }
        // A second Dropbox folder (legacy ~/Dropbox) only shows up when it
        // isn't the same folder as the one above.
        candidates += dropboxCandidates.map { StorageLocation(provider: .folder, folderPath: "\($0)/Takeover") }

        let cloudStorage = PathUtility.expandTildeToRealHome("~/Library/CloudStorage")
        let drives = (try? FileManager.default.contentsOfDirectory(atPath: cloudStorage)) ?? []
        for drive in drives.sorted() where !drive.hasPrefix("Dropbox") && !drive.hasPrefix(".") {
            // Google Drive nests the user's files under "My Drive".
            for sub in ["Takeover", "My Drive/Takeover"] {
                candidates.append(StorageLocation(provider: .folder, folderPath: "~/Library/CloudStorage/\(drive)/\(sub)"))
            }
        }

        candidates += [defaultFolderPath, "~/Documents/Takeover", localSupportPath].map {
            StorageLocation(provider: .folder, folderPath: $0)
        }
        return candidates
    }

    private static func settingsModifiedAt(in directory: String) -> Date? {
        settingsFileNames.compactMap { name -> Date? in
            let path = (directory as NSString).appendingPathComponent(name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            return attributes[.modificationDate] as? Date ?? .distantPast
        }.max()
    }
}
