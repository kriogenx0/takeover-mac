//
//  ContentView.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case links
    case macDefaults
    case applications
    case restore

    var title: String {
        switch self {
        case .links: return "Links"
        case .macDefaults: return "Mac Defaults"
        case .applications: return "Applications"
        case .restore: return "Restore"
        }
    }

    var icon: String {
        switch self {
        case .links: return "link"
        case .macDefaults: return "gearshape"
        case .applications: return "app.badge.checkmark"
        case .restore: return "arrow.clockwise.icloud"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var account: AccountManager
    @AppStorage("takeover.activeTab") private var activeTab: AppTab = .links
    @AppStorage("takeover.hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showAccount = false
    @State private var showWelcome = false
    @State private var welcomeWantsSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            MainTabBar(activeTab: $activeTab, showAccount: $showAccount)

            Group {
                switch activeTab {
                case .links:
                    LinkItemListView()
                case .macDefaults:
                    MacDefaultListView()
                case .applications:
                    AppInstallerListView()
                case .restore:
                    RestoreView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("macOS \(SystemInfo.macOSVersionString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView(isPresented: $showAccount)
        }
        // Offer to sign in (or not) exactly once, the first time the app is
        // opened signed out — but only once we actually know it's signed
        // out (hasCheckedAuth), not on the initial always-signed-out state.
        .onChange(of: account.hasCheckedAuth) { _, checked in
            if checked && !account.isSignedIn && !hasSeenWelcome {
                hasSeenWelcome = true
                showWelcome = true
            }
        }
        .sheet(isPresented: $showWelcome, onDismiss: {
            if welcomeWantsSignIn {
                welcomeWantsSignIn = false
                showAccount = true
            }
        }) {
            WelcomeView(
                onSignIn: { welcomeWantsSignIn = true; showWelcome = false },
                onContinue: { showWelcome = false }
            )
        }
    }
}

// MARK: - Top-level tab bar

/// Rendered as ordinary content (not a window toolbar item), so its position
/// never shifts when the active tab swaps in its own toolbar buttons — the way
/// the native `TabView` selector does, since it shares the unified toolbar with
/// each tab's `.toolbar` content.
struct MainTabBar: View {
    @Binding var activeTab: AppTab
    @Binding var showAccount: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer()
                AccountButton(showAccount: $showAccount)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)

            Divider()
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = activeTab == tab
        return Button {
            activeTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15))
                Text(tab.title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(minWidth: 84)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keeps macOS from parking a focus ring on a tab button at launch.
        // The buttons stay fully clickable; this only drops them from tab order.
        .focusable(false)
    }
}

// MARK: - Per-tab action bar

/// A tab's own title + actions, rendered as ordinary content directly below
/// `MainTabBar` instead of in the window's unified toolbar. Keeps `MainTabBar`
/// at a fixed position regardless of what controls the active tab needs.
struct TabActionBar<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                Spacer()
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
        }
        .background(.bar)
    }
}

#Preview {
    ContentView()
        .environmentObject(AccountManager.shared)
        .environmentObject(ProfileSyncManager.shared)
        .modelContainer(for: [LinkItem.self, MacDefault.self, AppInstaller.self, AppEntryModel.self], inMemory: true)
}
