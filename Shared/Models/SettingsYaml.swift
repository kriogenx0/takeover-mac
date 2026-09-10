//
//  SettingsYaml.swift
//  Takeover
//
//  Created by Alex Vaos on 11/4/25.
//

import Foundation
import Yams

struct SettingsYaml: Codable {
    var links: [LinkConfig]
    var macDefaults: [MacDefaultConfig]?
    var appInstallers: [AppInstallerConfig]?
    /// The synced "restore list" (see AppEntryModel).
    var apps: [AppEntryConfig]?

    enum CodingKeys: String, CodingKey {
        case links
        case macDefaults = "mac_defaults"
        case appInstallers = "app_installers"
        case apps
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    @Published var settings: SettingsYaml?
    @Published var location: StorageLocation = .current

    private let fileName = "takeover-settings.yaml"
    private let macDefaultsFileName = "mac-defaults.yaml"

    private init() {}

    var storageDirectoryURL: URL {
        URL(fileURLWithPath: location.expandedRootPath)
    }

    var settingsFileURL: URL {
        storageDirectoryURL.appendingPathComponent(fileName)
    }

    var macDefaultsFileURL: URL {
        storageDirectoryURL.appendingPathComponent(macDefaultsFileName)
    }

    /// Switches to a new storage location, copying the current settings files
    /// across when the new folder doesn't have its own yet.
    @MainActor
    func changeLocation(to newLocation: StorageLocation) throws {
        let oldDirectory = storageDirectoryURL
        try newLocation.save()
        location = newLocation

        let newDirectory = storageDirectoryURL
        guard oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL else { return }
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        for name in [fileName, macDefaultsFileName] {
            let from = oldDirectory.appendingPathComponent(name)
            let to = newDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: from.path) && !FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
    }

    func loadSettings() async throws -> SettingsYaml {
        let fileURL = settingsFileURL

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: storageDirectoryURL,
            withIntermediateDirectories: true
        )

        // Check if file exists, if not create a default one
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try createEmptySettings(at: fileURL)
            print("Created default settings at: \(fileURL.path)")
        }

        let data = try Data(contentsOf: fileURL)
        let yamlString = String(data: data, encoding: .utf8) ?? ""

        let decoder = YAMLDecoder()
        var settings = try decoder.decode(SettingsYaml.self, from: yamlString)

        // macOS defaults live in their own file; older installs kept them under
        // `mac_defaults` in the settings file, so move them over once.
        if let macDefaults = try loadMacDefaults() {
            settings.macDefaults = macDefaults
        } else if let legacy = settings.macDefaults {
            try writeMacDefaults(legacy)
            try writeSettingsFile(settings)
        }

        await MainActor.run {
            self.settings = settings
        }

        return settings
    }

    func saveSettings(_ settings: SettingsYaml) async throws {
        try writeSettingsFile(settings)
        try writeMacDefaults(settings.macDefaults ?? [])

        await MainActor.run {
            self.settings = settings
        }

        syncProfileToAccount(settings)
        if location.provider == .takeoverCloud {
            await TakeoverCloud.shared.push(settings)
        }
    }

    private func writeSettingsFile(_ settings: SettingsYaml) throws {
        var fileContents = settings
        fileContents.macDefaults = nil
        let yamlString = try YAMLEncoder().encode(fileContents)
        try yamlString.write(to: settingsFileURL, atomically: true, encoding: .utf8)
    }

    private func loadMacDefaults() throws -> [MacDefaultConfig]? {
        let url = macDefaultsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let yaml = String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        return try YAMLDecoder().decode(MacDefaultsYaml.self, from: yaml).macDefaults
    }

    private func writeMacDefaults(_ macDefaults: [MacDefaultConfig]) throws {
        let yaml = try YAMLEncoder().encode(MacDefaultsYaml(macDefaults: macDefaults))
        try yaml.write(to: macDefaultsFileURL, atomically: true, encoding: .utf8)
    }

    /// When signed in, push this Mac's setup to the account (debounced). No-op
    /// otherwise. Mac-default rows are enriched with domain/key/type from the
    /// catalog so the profile is self-contained on the restoring Mac.
    private func syncProfileToAccount(_ settings: SettingsYaml) {
        let catalog = Dictionary(
            MacDefaultCatalog.shared.entries.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let defaults: [Profile.MacDefaultEntry] = (settings.macDefaults ?? []).compactMap { cfg in
            guard let value = cfg.value, !value.isEmpty, let e = catalog[cfg.name] else { return nil }
            return Profile.MacDefaultEntry(
                name: e.name, domain: e.domain, key: e.key, type: e.type,
                value: value, hostFlag: e.hostFlag ?? "", postCommand: e.postCommand ?? "")
        }
        let links = settings.links.map {
            Profile.LinkEntry(name: $0.name, from: $0.from, to: $0.to, defaults: $0.defaults ?? "")
        }
        let apps = (settings.apps ?? []).map {
            Profile.AppEntry(
                name: $0.name,
                source: Profile.AppSource(rawValue: $0.source) ?? .brew,
                cask: $0.cask, masID: $0.masID)
        }
        let profile = Profile(version: 1, macDefaults: defaults, links: links, apps: apps)

        Task { @MainActor in
            ProfileSyncManager.shared.schedulePush(profile)
        }
    }

    private func createEmptySettings(at url: URL) throws {
        let defaultSettings = """
        links: []
        """

        try defaultSettings.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum SettingsError: Error {
    case iCloudNotAvailable
    case fileNotFound
    case invalidYAML
}
