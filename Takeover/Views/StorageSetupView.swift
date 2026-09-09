import AppKit
import SwiftUI

extension Notification.Name {
    static let storageLocationChanged = Notification.Name("TakeoverStorageLocationChanged")
}

/// Lets the user pick where their settings live: iCloud Drive, Dropbox,
/// Takeover Cloud or a folder. Shown on first launch and in Settings.
struct StorageSetupView: View {
    var isFirstLaunch: Bool
    var onDone: (() -> Void)?

    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var cloud = TakeoverCloud.shared

    @State private var provider: StorageProvider
    @State private var folderPath: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(isFirstLaunch: Bool, onDone: (() -> Void)? = nil) {
        self.isFirstLaunch = isFirstLaunch
        self.onDone = onDone
        let current = StorageLocation.current
        _provider = State(initialValue: current.provider)
        _folderPath = State(initialValue: current.folderPath ?? StorageLocation.defaultFolderPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isFirstLaunch ? "Where should Takeover keep your settings?" : "Settings Storage")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Your links, macOS defaults and apps are saved as YAML files in this location, so another Mac can pick them up.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(StorageProvider.allCases) { option in
                    ProviderRow(
                        provider: option,
                        isSelected: provider == option,
                        isAvailable: StorageLocation.isAvailable(option)
                    ) {
                        provider = option
                    }
                }
            }

            Group {
                switch provider {
                case .folder:
                    HStack {
                        Text(folderPath)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                    }
                case .takeoverCloud:
                    CloudAccountView()
                case .iCloud, .dropbox:
                    Text(StorageLocation(provider: provider).rootPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 4)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button(isFirstLaunch ? "Continue" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var selectedLocation: StorageLocation {
        StorageLocation(provider: provider, folderPath: provider == .folder ? folderPath : nil)
    }

    private var canSave: Bool {
        guard StorageLocation.isAvailable(provider) else { return false }
        if provider == .takeoverCloud { return cloud.isSignedIn }
        return true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for your Takeover settings"
        if panel.runModal() == .OK, let url = panel.url {
            let home = PathUtility.getRealHomeDirectory()
            folderPath = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let location = selectedLocation
                try settingsManager.changeLocation(to: location)
                if location.provider == .takeoverCloud {
                    try await restoreFromCloudIfEmpty()
                }
                NotificationCenter.default.post(name: .storageLocationChanged, object: nil)
                onDone?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// On a new Mac, seed the local copy from the account's latest profile.
    private func restoreFromCloudIfEmpty() async throws {
        let settings = try await settingsManager.loadSettings()
        let isEmpty = settings.links.isEmpty
            && (settings.macDefaults ?? []).isEmpty
            && (settings.appInstallers ?? []).isEmpty
        if isEmpty, let restored = try await cloud.latestProfile() {
            try await settingsManager.saveSettings(restored)
        } else if !isEmpty {
            await cloud.push(settings)
        }
    }
}

private struct ProviderRow: View {
    let provider: StorageProvider
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.systemImage)
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .fontWeight(.medium)
                    Text(isAvailable ? provider.summary : "\(provider.title) isn't set up on this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
    }
}

/// Sign-in and trial/subscription state for Takeover Cloud.
struct CloudAccountView: View {
    @ObservedObject private var cloud = TakeoverCloud.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cloud.isSignedIn {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloud.account?.email ?? "Signed in")
                            .fontWeight(.medium)
                        if let subscription = cloud.account?.subscription {
                            Text(subscription.summary)
                                .font(.caption)
                                .foregroundColor(subscription.needsPayment ? .orange : .secondary)
                        }
                        if let lastError = cloud.lastError {
                            Text("Last sync failed: \(lastError)")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if let lastSyncedAt = cloud.lastSyncedAt {
                            Text("Last synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if let subscription = cloud.account?.subscription, subscription.needsPayment {
                        Button("Subscribe") { openCheckout(subscription) }
                    }
                    Button("Sign Out") { cloud.signOut() }
                }
            } else {
                Text("Takeover Cloud is optional. Start with a 30-day free trial, then $3/month.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Email or username", text: $email)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                HStack {
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                    Button("Create Account") { run { try await cloud.register(email: email, password: password) } }
                    Button("Sign In") { run { try await cloud.signIn(login: email, password: password) } }
                }
                .disabled(email.isEmpty || password.isEmpty || isWorking)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .textFieldStyle(.roundedBorder)
        .task {
            if cloud.isSignedIn { try? await cloud.refreshAccount() }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await action()
                password = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openCheckout(_ subscription: CloudSubscription) {
        let url = subscription.checkoutURL.flatMap(URL.init(string:))
            ?? Config.apiBaseURL.appendingPathComponent("pricing")
        NSWorkspace.shared.open(url)
    }
}
