//
//  TakeoverApp.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct TakeoverApp: App {
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var needsStorageSetup = StorageLocation.load() == nil
    @StateObject private var account = AccountManager.shared
    @StateObject private var profileSync = ProfileSyncManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LinkItem.self,
            MacDefault.self,
            AppInstaller.self,
            AppEntryModel.self,
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
                .environmentObject(account)
                .environmentObject(profileSync)
                .task {
                    await checkPermissionsOnStartup()
                    await Repository.shared.load()
                    await account.refresh()
                    if account.isSignedIn {
                        await profileSync.registerThisMac()
                    }
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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // The user may have just granted access in System Settings —
                    // clear the stale nag so it doesn't keep reappearing.
                    PermissionsHelper.refreshAfterActivation()
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
        switch PermissionsHelper.fullDiskAccessStatus() {
        case .granted:
            print("✅ Full Disk Access granted")
        case .unknown:
            print("ℹ️ Full Disk Access status unknown (no probe file present) — not prompting")
        case .denied:
            print("⚠️ Full Disk Access not granted")
            PermissionsHelper.showFullDiskAccessAlert()
        }
    }

    private func ensureStorageDirectoryExists() async {
        let iCloudPath = Config.expandedBackupPath

        if FileOps.isDirectory(iCloudPath) {
            return
        }
        do {
            try FileOps.makeDirectory(iCloudPath)
            print("Created Takeover storage directory at: \(iCloudPath)")
        } catch {
            print("⚠️ Could not create Takeover storage directory at \(iCloudPath): \(error.localizedDescription)")
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

        // Sync the app restore-list
        let entryDescriptor = FetchDescriptor<AppEntryModel>()
        let existingEntries = (try? context.fetch(entryDescriptor)) ?? []
        let existingEntryNames = Set(existingEntries.map { $0.name })
        for config in settings.apps ?? [] {
            if !existingEntryNames.contains(config.name) {
                context.insert(AppEntryModel(
                    name: config.name,
                    source: config.source,
                    cask: config.cask ?? "",
                    masID: config.masID ?? ""
                ))
            }
        }

        try? context.save()
    }

    private func expandTilde(_ path: String) -> String {
        return PathUtility.expandTildeToRealHome(path)
    }
}
