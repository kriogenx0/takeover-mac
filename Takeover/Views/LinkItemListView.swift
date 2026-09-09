//
//  LinkItemList.swift
//  Takeover
//
//  Created by Alex Vaos on 3/4/25.
//

import Foundation
import SwiftUI
import SwiftData

struct LinkItemListView: View {
    
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LinkItem.name) private var linkItems: [LinkItem] // Use @Query to fetch data
    //    var linkItems: [LinkItem] = []
//    @Binding var linkItems: [LinkItem]
    @State private var linkItemSelection: LinkItem? = nil
    @State private var showRecipesView = false
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible && !linkItems.isEmpty {
                List(selection: $linkItemSelection) {
                    ForEach(linkItems, id: \.self) { linkItem in
                        Text(linkItem.name)
                            .tag(linkItem)
                            .contextMenu {
                                Button("Install") { onRun(linkItem: linkItem) }
                                Button("Uninstall") { onUninstall(linkItem: linkItem) }
                                Divider()
                                Button("Delete", role: .destructive) { onDelete(linkItem: linkItem) }
                            }
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(.sidebar)
                .onAppear {
                    if linkItemSelection == nil && !linkItems.isEmpty {
                        linkItemSelection = linkItems.first
                    }
                }
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 300)
                Divider()
            }

            Group {
                if let selectedItem = linkItemSelection {
                    LinkItemDetailView(
                        linkItem: selectedItem,
                        onSave: onSave,
                        onRun: onRun,
                        onDelete: onDelete,
                        onUninstall: onUninstall
                    )
                } else {
                    Text("No Link Items")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar(content: {
            ToolbarItem(placement: .navigation) {
                Button(action: { withAnimation { sidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showRecipesView = true }) {
                    Label("Browse Recipes", systemImage: "books.vertical")
                }
                .help("Browse available app configurations")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        })
        .sheet(isPresented: $showRecipesView) {
            RecipesView(onAdd: { newItem in
                linkItemSelection = newItem
            })
        }
    }

    private func pullFromRepository() {
        Task {
            let result = Linker.shell("git pull")
            print("Git pull result: \(result)")

            // Reload settings after pull
            do {
                let settings = try await SettingsManager.shared.loadSettings()
                await syncSettingsToDatabase(settings: settings)
            } catch {
                print("Error reloading settings after pull: \(error)")
            }
        }
    }

    @MainActor
    private func syncSettingsToDatabase(settings: SettingsYaml) async {
        // Fetch existing items
        let descriptor = FetchDescriptor<LinkItem>()
        let existingItems = (try? modelContext.fetch(descriptor)) ?? []

        // Create a set of existing names for quick lookup
        let existingNames = Set(existingItems.map { $0.name })

        // Add new items from YAML that don't exist in database
        for linkConfig in settings.links {
            if !existingNames.contains(linkConfig.name) {
                let newItem = LinkItem(
                    name: linkConfig.name,
                    from: linkConfig.from,
                    to: linkConfig.to
                )
                modelContext.insert(newItem)
            }
        }

        try? modelContext.save()
    }

    private func onRun(linkItem: LinkItem) -> Void {
        LinkItemInstaller.install(linkItem: linkItem)
    }

    private func onUninstall(linkItem: LinkItem) -> Void {
        LinkItemInstaller.uninstall(linkItem: linkItem)
    }

    private func onSave(linkItem: LinkItem) -> Void {
        // Check for duplicate names
        let duplicates = linkItems.filter { $0.name == linkItem.name && $0 != linkItem }
        if !duplicates.isEmpty {
            // Make name unique by appending a number
            var counter = 1
            var uniqueName = "\(linkItem.name) (\(counter))"
            while linkItems.contains(where: { $0.name == uniqueName && $0 != linkItem }) {
                counter += 1
                uniqueName = "\(linkItem.name) (\(counter))"
            }
            linkItem.name = uniqueName
        }

        // With @Bindable, changes are automatically tracked
        // Save to database
        try? modelContext.save()

        // Also save to YAML file
        Task {
            await saveToYAML()
        }
    }

    @MainActor
    private func saveToYAML() async {
        // Convert all LinkItems to YAML format
        let linkConfigs = linkItems.map { item in
            LinkConfig(
                name: item.name,
                from: item.from,
                to: item.to,
                defaults: item.defaults.isEmpty ? nil : item.defaults
            )
        }

        let settings = SettingsYaml(links: linkConfigs)

        do {
            try await SettingsManager.shared.saveSettings(settings)
            print("Settings saved to YAML")
        } catch {
            print("Error saving settings to YAML: \(error)")
        }
    }

    private func onDelete(linkItem: LinkItem) -> Void {
        // First uninstall the symlink
        onUninstall(linkItem: linkItem)

        // Find the index of the item to delete
        guard let index = linkItems.firstIndex(of: linkItem) else { return }

        // Determine next selection
        let nextSelection: LinkItem? = {
            if index < linkItems.count - 1 {
                // Select next item if available
                return linkItems[index + 1]
            } else if index > 0 {
                // Select previous item if we're deleting the last item
                return linkItems[index - 1]
            } else {
                // No items left
                return nil
            }
        }()

        // Then delete from database
        withAnimation {
            modelContext.delete(linkItem)
            linkItemSelection = nextSelection
        }
        // Save to YAML after deletion
        Task {
            await saveToYAML()
        }
    }

    private func addItem() {
        withAnimation {
            // Generate a unique name
            var baseName = Date().formatted()
            var uniqueName = baseName
            var counter = 1

            // Check if name already exists
            while linkItems.contains(where: { $0.name == uniqueName }) {
                uniqueName = "\(baseName) (\(counter))"
                counter += 1
            }

            let newItem = LinkItem(name: uniqueName)
            modelContext.insert(newItem)
            linkItemSelection = newItem
        }
        // Save to YAML after adding
        Task {
            await saveToYAML()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(linkItems[index])
            }
        }
    }
}



#Preview("LinkItemList filled") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: LinkItem.self, configurations: config)

    let sampleItems = [
        LinkItem(name: "Dropbox", from: "/Users/user/Dropbox", to: "/opt/dropbox"),
        LinkItem(name: "Adobe Fonts", from: "/Library/Application Support/Adobe/CoreSync/plugins/livetype", to: "/System/Library/Fonts"),
        LinkItem(name: "Audio Plugins", from: "/Library/Audio/Plug-Ins", to: "/usr/local/audio")
    ]

    for item in sampleItems {
        container.mainContext.insert(item)
    }

    return LinkItemListView()
        .modelContainer(container)
}

#Preview("LinkItemList empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: LinkItem.self, configurations: config)

    return LinkItemListView()
        .modelContainer(container)
}
