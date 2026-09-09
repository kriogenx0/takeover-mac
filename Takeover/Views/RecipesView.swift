//
//  RecipesView.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingLinks: [LinkItem]
    private var repository = Repository.shared

    var onAdd: ((LinkItem) -> Void)?

    init(onAdd: ((LinkItem) -> Void)? = nil) {
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Available Recipes")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if repository.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading recipes...")
                    Spacer()
                }
            } else if let error = repository.error {
                VStack {
                    Spacer()
                    Text("Error loading recipes")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // App Recipes Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Applications")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top)

                            ForEach(sortedRecipes) { app in
                                AppRecipeRow(
                                    app: app,
                                    isAlreadyAdded: isRecipeAlreadyAdded(app),
                                    onAdd: {
                                        addRecipeToLinks(app)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var sortedRecipes: [AppConfig] {
        let apps = repository.response?.apps ?? []
        return apps.sorted { recipe1, recipe2 in
            let exists1 = isRecipeAlreadyAdded(recipe1)
            let exists2 = isRecipeAlreadyAdded(recipe2)

            // If one exists and the other doesn't, put the existing one last
            if exists1 != exists2 {
                return !exists1
            }

            // Otherwise sort alphabetically
            return recipe1.name < recipe2.name
        }
    }

    private func isRecipeAlreadyAdded(_ app: AppConfig) -> Bool {
        let existingNames = Set(existingLinks.map { $0.name })
        return existingNames.contains(app.name)
    }

    private func addRecipeToLinks(_ app: AppConfig) {
        var lastCreatedItem: LinkItem?

        print("DEBUG: Starting to add recipe '\(app.name)' with \(app.files.count) files")

        // For each file in the recipe, create a LinkItem
        for (index, file) in app.files.enumerated() {
            print("DEBUG: File path from recipe: '\(file.path)'")

            // Combine all defaults commands into one string
            let defaultsCommand = app.defaults?.joined(separator: " && ") ?? ""

            // Clean the app name for "to" field (remove spaces and special characters)
            let cleanName = app.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "/", with: "-")
            print("DEBUG: Clean app name for 'to' field: '\(cleanName)'")

            // Create unique name if multiple files
            var itemName = app.name
            if app.files.count > 1 {
                itemName = "\(app.name) (\(index + 1))"
            }

            // Ensure name is unique across all existing items
            var uniqueName = itemName
            var counter = 1
            while existingLinks.contains(where: { $0.name == uniqueName }) {
                uniqueName = "\(itemName) (\(counter))"
                counter += 1
            }

            let newItem = LinkItem(
                name: uniqueName,
                from: file.path,
                to: cleanName,
                defaults: defaultsCommand
            )

            print("DEBUG: Created LinkItem - name: '\(newItem.name)', from: '\(newItem.from)', to: '\(newItem.to)'")

            modelContext.insert(newItem)
            lastCreatedItem = newItem
        }

        // Save and wait for completion
        do {
            try modelContext.save()
            print("DEBUG: Save completed successfully")
        } catch {
            print("DEBUG: Save failed with error: \(error)")
        }

        // Notify parent with the last created item
        if let item = lastCreatedItem {
            print("DEBUG: Calling onAdd with item: '\(item.name)', from: '\(item.from)'")
            onAdd?(item)
        }

        dismiss()
    }
}

struct AppRecipeRow: View {
    let app: AppConfig
    let isAlreadyAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "app.fill")
                    .foregroundColor(isAlreadyAdded ? .gray : .blue)
                Text(app.name)
                    .font(.headline)
                    .foregroundColor(isAlreadyAdded ? .secondary : .primary)
                Spacer()
                Button("Add") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAlreadyAdded)
            }

            if !app.files.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(app.files.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "doc.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(app.files[index].path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                }
            }

            if let defaults = app.defaults, !defaults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Defaults:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(defaults, id: \.self) { defaultCommand in
                        HStack {
                            Image(systemName: "terminal.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(defaultCommand)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct OSRecipeRow: View {
    let recipe: OSRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.orange)
                Text(recipe.name)
                    .font(.headline)
                Spacer()
            }

            HStack {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("defaults \(recipe.defaults)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

#Preview {
    RecipesView()
}
