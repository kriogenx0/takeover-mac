import SwiftUI
import SwiftData

struct AppInstallerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var installers: [AppInstaller]

    var body: some View {
        VSplitView {
            Group {
                if let installer = installers.first {
                    AppInstallerContentView(installer: installer, onSave: save)
                } else {
                    Text("Loading…")
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 260)

            AppRestoreListEditor()
                .frame(minHeight: 140, idealHeight: 200)
        }
        .onAppear {
            if installers.isEmpty {
                let item = AppInstaller(name: "Apps", path: "")
                modelContext.insert(item)
            }
        }
    }

    private func save() {
        try? modelContext.save()
        Task { await saveToYAML() }
    }

    @MainActor
    private func saveToYAML() async {
        let configs = installers.map { AppInstallerConfig(name: $0.name, path: $0.path) }
        guard var settings = SettingsManager.shared.settings else { return }
        settings.appInstallers = configs
        try? await SettingsManager.shared.saveSettings(settings)
    }
}

struct AppInstallerContentView: View {
    @Bindable var installer: AppInstaller
    var onSave: (() -> Void)?

    @State private var discoveredApps: [DiscoveredApp] = []
    @State private var isScanning = false
    @State private var installStatus: [String: String] = [:]
    @State private var installing: Set<String> = []
    @State private var installedNames: [String: String] = [:]
    @State private var installError: String? = nil
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabActionBar(title: "Applications") {
                TextField("~/Downloads/Apps", text: $installer.path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 260)
                Button("Browse") { browseForFolder() }
                Button("Scan") { scanApps() }
                    .disabled(installer.path.isEmpty)
                if isScanning { ProgressView().scaleEffect(0.7) }
            }

            if discoveredApps.isEmpty && !isScanning {
                Text(installer.path.isEmpty ? "Set a folder path and tap Scan" : "No apps found — tap Scan")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(discoveredApps) { app in
                    let resolved = installedNames[app.id]
                    AppRowView(
                        app: app,
                        status: installStatus[app.id],
                        isInstalling: installing.contains(app.id),
                        isInstalled: app.isInstalled(resolvedName: resolved),
                        onInstall: { installApp(app) },
                        onUninstall: { uninstallApp(app) },
                        onOpen: {
                            let name = resolved ?? app.name
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(name).app"))
                        }
                    )
                    .contextMenu {
                        Button("Install") { installApp(app) }
                            .disabled(app.isInstalled(resolvedName: resolved) || installing.contains(app.id))
                        Button("Uninstall", role: .destructive) { uninstallApp(app) }
                            .disabled(!app.isInstalled(resolvedName: resolved))
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([app.fileURL])
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Install All") { installAll() }
                    .disabled(discoveredApps.filter { !$0.isInstalled(resolvedName: installedNames[$0.id]) }.isEmpty)
            }
            .padding(16)
        }
        .alert("Installation Error", isPresented: Binding(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("OK") { installError = nil }
        } message: {
            Text(installError ?? "")
        }
        .onChange(of: installer.path) { _, _ in scheduleSave() }
        .onAppear { if !installer.path.isEmpty { scanApps() } }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            installer.path = url.path
            scheduleSave()
            scanApps()
        }
    }

    private func scanApps() {
        guard !installer.path.isEmpty else { return }
        isScanning = true
        Task {
            let apps = AppInstallerEngine.scan(at: installer.path)
            await MainActor.run {
                discoveredApps = apps
                isScanning = false
            }
        }
    }

    private func installApp(_ app: DiscoveredApp) {
        installing.insert(app.id)
        Task {
            let result = AppInstallerEngine.install(app)
            await MainActor.run {
                installing.remove(app.id)
                if result.success {
                    installStatus[app.id] = result.message
                } else {
                    installError = result.message
                }
                if let name = result.installedName {
                    installedNames[app.id] = name
                }
                discoveredApps = AppInstallerEngine.scan(at: installer.path)
            }
        }
    }

    private func uninstallApp(_ app: DiscoveredApp) {
        installing.insert(app.id)
        Task {
            let result = AppInstallerEngine.uninstall(app, installedName: installedNames[app.id])
            await MainActor.run {
                installing.remove(app.id)
                if result.success {
                    installStatus[app.id] = result.message
                    installedNames.removeValue(forKey: app.id)
                } else {
                    installError = result.message
                }
                discoveredApps = AppInstallerEngine.scan(at: installer.path)
            }
        }
    }

    private func installAll() {
        let pending = discoveredApps.filter { !$0.isInstalled(resolvedName: installedNames[$0.id]) }
        for app in pending { installApp(app) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { onSave?() }
        }
    }
}

struct AppRowView: View {
    let app: DiscoveredApp
    let status: String?
    let isInstalling: Bool
    let isInstalled: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.fileType.systemImage)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.fileType.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isInstalling {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 60)
            } else if status != nil {
                Button("Open", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if isInstalled {
                Button("Uninstall", action: onUninstall)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
            } else {
                Button("Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Restore list editor

/// The curated "restore list" — synced in the profile and (re)installed on
/// another Mac. Separate from the folder scanner above.
struct AppRestoreListEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppEntryModel.name) private var entries: [AppEntryModel]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Sync & Restore list").font(.headline)
                Text("installed on another Mac via Homebrew or a local installer")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    modelContext.insert(AppEntryModel(name: "New App"))
                    persist()
                } label: { Label("Add App", systemImage: "plus") }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            if entries.isEmpty {
                Text("No apps yet — Add App, set its Homebrew cask, and it'll be part of every restore.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        RestoreListRow(entry: entry, onChange: persist, onDelete: {
                            modelContext.delete(entry); persist()
                        })
                    }
                }
            }
        }
        .background(.bar)
    }

    private func persist() {
        try? modelContext.save()
        Task { @MainActor in
            guard var settings = SettingsManager.shared.settings else { return }
            settings.apps = entries.map {
                AppEntryConfig(name: $0.name, source: $0.source,
                               cask: $0.cask.isEmpty ? nil : $0.cask,
                               masID: $0.masID.isEmpty ? nil : $0.masID)
            }
            try? await SettingsManager.shared.saveSettings(settings)
        }
    }
}

private struct RestoreListRow: View {
    @Bindable var entry: AppEntryModel
    var onChange: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $entry.name).textFieldStyle(.roundedBorder).frame(width: 160)
                .onSubmit(onChange)

            Picker("", selection: $entry.source) {
                Text("Homebrew").tag("brew")
                Text("Local").tag("local")
                Text("App Store").tag("mas")
            }
            .labelsHidden().frame(width: 110)
            .onChange(of: entry.source) { _, _ in onChange() }

            if entry.source == "brew" {
                TextField("cask id, e.g. rectangle", text: $entry.cask)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .onSubmit(onChange)
            } else if entry.source == "mas" {
                TextField("App Store id", text: $entry.masID)
                    .textFieldStyle(.roundedBorder).onSubmit(onChange)
            } else {
                Text("matched by name in the folder above")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
