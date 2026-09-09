//
//  TakeoverApp.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import SwiftUI
import SwiftData

@main
struct TakeoverApp: App {
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var needsStorageSetup = StorageLocation.load() == nil

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LinkItem.self,
            MacDefault.self,
            AppInstaller.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await checkPermissionsOnStartup()
                    await Repository.shared.load()
                    if !needsStorageSetup {
                        await loadFromStorage()
                    }
                }
                .sheet(isPresented: $needsStorageSetup) {
                    StorageSetupView(isFirstLaunch: true) {
                        needsStorageSetup = false
                    }
                    .interactiveDismissDisabled()
                }
                .onReceive(NotificationCenter.default.publisher(for: .storageLocationChanged)) { _ in
                    Task { await loadFromStorage() }
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            StorageSetupView(isFirstLaunch: false)
        }
    }

    private func loadFromStorage() async {
        await ensureStorageDirectoryExists()
        await loadSettingsAndPopulate()
    }

    @MainActor
    private func checkPermissionsOnStartup() async {
        if !PermissionsHelper.hasFullDiskAccess() {
            print("⚠️ Full Disk Access not granted")
            PermissionsHelper.showFullDiskAccessAlert()
        } else {
            print("✅ Full Disk Access granted")
        }
    }

    private func ensureStorageDirectoryExists() async {
        let iCloudPath = Config.expandedBackupPath

        print("DEBUG: Checking storage directory at: \(iCloudPath)")

        // Use shell command to check if directory exists
        let escapedPath = iCloudPath.replacingOccurrences(of: "'", with: "'\\''")
        let checkCommand = "test -d '\(escapedPath)' && echo 'exists' || echo 'not_exists'"
        let checkResult = Linker.shell(checkCommand).trimmingCharacters(in: .whitespacesAndNewlines)

        if checkResult == "not_exists" {
            // Directory doesn't exist, create it using osascript (has proper permissions)
            let escapedPathForOsascript = iCloudPath.replacingOccurrences(of: "\"", with: "\\\"")
            let createDirScript = "do shell script \"mkdir -p \\\"\(escapedPathForOsascript)\\\"\""
            print("DEBUG: Creating directory with osascript")
            let createResult = Linker.shell("osascript -e '\(createDirScript)'")

            if createResult.isEmpty {
                print("Created Takeover storage directory at: \(iCloudPath)")
            } else {
                print("DEBUG: osascript result: \(createResult)")
            }
        } else {
            print("DEBUG: Storage directory already exists at: \(iCloudPath)")
        }
    }

    private func loadSettingsAndPopulate() async {
        do {
            let settings = try await settingsManager.loadSettings()
            do {
                try await MacDefaultCatalog.shared.load()
            } catch {
                print("Error loading macOS defaults catalog: \(error)")
            }
            await syncSettingsToDatabase(settings: settings)
        } catch {
            print("Error loading settings: \(error)")
        }
    }

    @MainActor
    private func syncSettingsToDatabase(settings: SettingsYaml) async {
        let context = sharedModelContainer.mainContext

        // Sync LinkItems
        let descriptor = FetchDescriptor<LinkItem>()
        let existingItems = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existingItems.map { $0.name })

        for linkConfig in settings.links {
            if !existingNames.contains(linkConfig.name) {
                let newItem = LinkItem(
                    name: linkConfig.name,
                    from: expandTilde(linkConfig.from),
                    to: expandTilde(linkConfig.to),
                    defaults: linkConfig.defaults ?? ""
                )
                context.insert(newItem)
            }
        }

        // Sync MacDefaults: catalog is source of metadata, user settings supply values
        let defaultsDescriptor = FetchDescriptor<MacDefault>()
        let existingDefaults = (try? context.fetch(defaultsDescriptor)) ?? []
        let existingDefaultNames = Set(existingDefaults.map { $0.name })

        // Catalog entries for this macOS first, then any custom defaults the
        // user's file describes that the catalog doesn't (or no longer) list.
        let userConfigs = settings.macDefaults ?? []
        let userByName = Dictionary(userConfigs.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        let catalogNames = Set(MacDefaultCatalog.shared.entries.map { $0.name })

        for entry in MacDefaultCatalog.shared.entries where !existingDefaultNames.contains(entry.name) {
            let user = userByName[entry.name]
            context.insert(MacDefault(
                name: entry.name,
                domain: entry.domain,
                key: entry.key,
                type: entry.type,
                value: user?.value ?? "",
                hostFlag: entry.hostFlag ?? "",
                postCommand: entry.postCommand ?? "",
                capturedOSMajorVersion: user?.capturedOSMajorVersion ?? 0
            ))
        }

        for config in userConfigs where !catalogNames.contains(config.name) && !existingDefaultNames.contains(config.name) {
            guard let domain = config.domain, let key = config.key else { continue }
            context.insert(MacDefault(
                name: config.name,
                domain: domain,
                key: key,
                type: config.type ?? "string",
                value: config.value ?? "",
                hostFlag: config.hostFlag ?? "",
                postCommand: config.postCommand ?? "",
                capturedOSMajorVersion: config.capturedOSMajorVersion ?? 0
            ))
        }

        // Sync AppInstallers
        let installersDescriptor = FetchDescriptor<AppInstaller>()
        let existingInstallers = (try? context.fetch(installersDescriptor)) ?? []
        let existingInstallerNames = Set(existingInstallers.map { $0.name })

        for config in settings.appInstallers ?? [] {
            if !existingInstallerNames.contains(config.name) {
                context.insert(AppInstaller(name: config.name, path: expandTilde(config.path)))
            }
        }

        try? context.save()
    }

    private func expandTilde(_ path: String) -> String {
        return PathUtility.expandTildeToRealHome(path)
    }
}
