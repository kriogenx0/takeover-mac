import SwiftUI
import SwiftData

struct RestoreView: View {
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var sync: ProfileSyncManager
    @Environment(\.modelContext) private var modelContext
    @Query private var installers: [AppInstaller]

    @State private var showAccount = false
    @State private var selectedComputerID: Int?
    @State private var profile: Profile?
    @State private var loadingProfile = false

    @State private var pickedDefaults: Set<String> = []
    @State private var pickedLinks: Set<String> = []
    @State private var pickedApps: Set<String> = []

    @State private var isRestoring = false
    @State private var outcomes: [String: String] = [:]   // row id -> status text
    @State private var summary: String?

    private var localFolder: String? { installers.first?.path }

    var body: some View {
        VStack(spacing: 0) {
            TabActionBar(title: "Restore") {
                if account.isSignedIn {
                    Button {
                        Task { await sync.loadComputers() }
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(sync.isLoadingComputers)
                }
                AccountButton(showAccount: $showAccount)
            }

            if !account.isSignedIn {
                signedOut
            } else {
                HStack(spacing: 0) {
                    computerList
                        .frame(width: 240)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView(isPresented: $showAccount).environmentObject(account)
        }
        .task(id: account.isSignedIn) {
            if account.isSignedIn { await sync.loadComputers() }
        }
    }

    // MARK: signed out

    private var signedOut: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.icloud").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Sign in to restore").font(.headline)
            Text("Sync this Mac's setup to your account, then pick a Mac to restore from.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Sign In") { showAccount = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: computer list

    private var computerList: some View {
        List(selection: $selectedComputerID) {
            if sync.computers.isEmpty && !sync.isLoadingComputers {
                Text("No Macs on this account yet").foregroundStyle(.secondary)
            }
            ForEach(sync.computers) { c in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(c.name).fontWeight(.medium)
                        if sync.isThisMac(c) {
                            Text("this Mac").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15)).clipShape(Capsule())
                        }
                    }
                    Text("\(c.summary.defaults) defaults · \(c.summary.links) links · \(c.summary.apps) apps")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(c.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if sync.isLoadingComputers { ProgressView() }
        }
        .onChange(of: selectedComputerID) { _, id in
            Task { await loadProfile(id) }
        }
    }

    // MARK: detail

    @ViewBuilder
    private var detail: some View {
        if let err = sync.computersError, sync.computers.isEmpty {
            Text(err).foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedComputerID == nil {
            Text("Select a Mac to see its saved setup")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadingProfile {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let profile {
            VStack(spacing: 0) {
                List {
                    section("Mac Defaults", picked: $pickedDefaults, ids: profile.macDefaults.map(\.id)) {
                        ForEach(profile.macDefaults) { d in
                            row(id: d.id, picked: $pickedDefaults,
                                title: d.name, subtitle: "\(d.domain) \(d.key) = \(d.value)")
                        }
                    }
                    section("Links", picked: $pickedLinks, ids: profile.links.map(\.id)) {
                        ForEach(profile.links) { l in
                            row(id: l.id, picked: $pickedLinks, title: l.name, subtitle: "\(l.from) → \(l.to)")
                        }
                    }
                    section("Applications", picked: $pickedApps, ids: profile.apps.map(\.id)) {
                        ForEach(profile.apps) { a in
                            row(id: a.id, picked: $pickedApps,
                                title: a.name,
                                subtitle: a.source == .brew ? "brew · \(a.cask ?? "—")" : a.source.rawValue)
                        }
                    }
                }

                Divider()
                HStack {
                    if let summary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if isRestoring { ProgressView().scaleEffect(0.7) }
                    Button("Restore Selected") { Task { await restore(profile) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRestoring || (pickedDefaults.isEmpty && pickedLinks.isEmpty && pickedApps.isEmpty))
                }
                .padding(12)
            }
        } else {
            Text("Couldn't load this Mac's setup").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, picked: Binding<Set<String>>, ids: [String],
                                        @ViewBuilder content: () -> Content) -> some View {
        if !ids.isEmpty {
            Section {
                content()
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Button(picked.wrappedValue.isSuperset(of: ids) ? "None" : "All") {
                        if picked.wrappedValue.isSuperset(of: ids) { picked.wrappedValue.subtract(ids) }
                        else { picked.wrappedValue.formUnion(ids) }
                    }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func row(id: String, picked: Binding<Set<String>>, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { picked.wrappedValue.contains(id) },
                set: { picked.wrappedValue.toggle(id, on: $0) }
            )).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let status = outcomes[id] {
                Text(status).font(.caption)
                    .foregroundStyle(status.hasPrefix("✓") ? .green : status.hasPrefix("…") ? .secondary : .red)
            }
        }
    }

    // MARK: actions

    private func loadProfile(_ id: Int?) async {
        outcomes = [:]; summary = nil
        guard let id else { profile = nil; return }
        loadingProfile = true
        defer { loadingProfile = false }
        let p = await sync.profile(for: id, force: true)
        profile = p
        pickedDefaults = Set(p?.macDefaults.map(\.id) ?? [])
        pickedLinks = []
        pickedApps = Set(p?.apps.map(\.id) ?? [])
    }

    private func restore(_ profile: Profile) async {
        isRestoring = true
        summary = nil
        defer { isRestoring = false }
        var ok = 0, fail = 0

        for d in profile.macDefaults where pickedDefaults.contains(d.id) {
            outcomes[d.id] = "… applying"
            let model = MacDefault(name: d.name, domain: d.domain, key: d.key, type: d.type,
                                   value: d.value, hostFlag: d.hostFlag, postCommand: d.postCommand)
            MacDefaultInstaller.apply(macDefault: model)
            upsertDefault(d)
            outcomes[d.id] = "✓ applied"; ok += 1
        }

        for l in profile.links where pickedLinks.contains(l.id) {
            outcomes[l.id] = "… linking"
            let item = LinkItem(name: l.name, from: l.from, to: l.to, defaults: l.defaults)
            do {
                try LinkItemInstaller.install(linkItem: item)
                upsertLink(l)
                outcomes[l.id] = "✓ linked"; ok += 1
            } catch {
                outcomes[l.id] = "✗ \(error.localizedDescription)"; fail += 1
            }
        }

        for a in profile.apps where pickedApps.contains(a.id) {
            outcomes[a.id] = "… installing"
            let folder = localFolder
            let outcome = await Task.detached { AppRestoreEngine.install(a, localFolder: folder) }.value
            switch outcome {
            case .installed, .alreadyPresent:
                outcomes[a.id] = "✓ " + outcome.label; ok += 1
            case .needsHomebrew:
                outcomes[a.id] = "✗ Homebrew required"; fail += 1
            case .skipped(let s):
                outcomes[a.id] = "· \(s)"
            case .failed(let s):
                outcomes[a.id] = "✗ \(s)"; fail += 1
            }
        }

        try? modelContext.save()
        summary = "\(ok) applied" + (fail > 0 ? ", \(fail) failed" : "")
        if profile.apps.contains(where: { pickedApps.contains($0.id) && $0.source == .brew }),
           !AppRestoreEngine.homebrewInstalled {
            summary = (summary ?? "") + " — install Homebrew, then retry"
        }
    }

    private func upsertDefault(_ d: Profile.MacDefaultEntry) {
        let name = d.name
        let existing = (try? modelContext.fetch(FetchDescriptor<MacDefault>(
            predicate: #Predicate { $0.name == name }))) ?? []
        if let m = existing.first { m.value = d.value }
        else {
            modelContext.insert(MacDefault(name: d.name, domain: d.domain, key: d.key, type: d.type,
                                           value: d.value, hostFlag: d.hostFlag, postCommand: d.postCommand))
        }
    }

    private func upsertLink(_ l: Profile.LinkEntry) {
        let name = l.name
        let existing = (try? modelContext.fetch(FetchDescriptor<LinkItem>(
            predicate: #Predicate { $0.name == name }))) ?? []
        if existing.isEmpty {
            modelContext.insert(LinkItem(name: l.name, from: l.from, to: l.to, defaults: l.defaults))
        }
    }
}

private extension Set {
    mutating func toggle(_ element: Element, on: Bool) {
        if on { insert(element) } else { remove(element) }
    }
}

/// Shared account chip used in each tab's action bar.
struct AccountButton: View {
    @EnvironmentObject var account: AccountManager
    @Binding var showAccount: Bool

    var body: some View {
        if let user = account.currentUser {
            Menu {
                Text(user.email)
                Button("Sign Out") { account.signOut() }
            } label: {
                Label(user.username, systemImage: "person.crop.circle.fill")
            }
        } else {
            Button {
                showAccount = true
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
            }
        }
    }
}
