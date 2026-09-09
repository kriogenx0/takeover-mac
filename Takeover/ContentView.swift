//
//  ContentView.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            LinkItemListView()
                .tabItem { Label("Sync App Settings", systemImage: "link") }
            MacDefaultListView()
                .tabItem { Label("macOS Tweaks", systemImage: "gearshape") }
            AppInstallerListView()
                .tabItem { Label("Install Apps", systemImage: "app.badge.checkmark") }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("macOS \(SystemInfo.macOSVersionString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: [LinkItem.self, MacDefault.self, AppInstaller.self], inMemory: true)
}
