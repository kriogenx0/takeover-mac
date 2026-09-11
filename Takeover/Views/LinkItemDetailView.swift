//
//  ItemDetail.swift
//  Takeover
//
//  Created by Alex Vaos on 2/13/25.
//

import SwiftUI
import SwiftData
import AppKit

struct LinkItemDetailView: View {
    @Bindable var linkItem: LinkItem

    private var onSave: ((LinkItem) -> Void)?
    private var onRun: ((LinkItem) -> Void)?
    private var onDelete: ((LinkItem) -> Void)?
    private var onUninstall: ((LinkItem) -> Void)?

    @State private var saveTask: Task<Void, Never>?

    init(linkItem: LinkItem,
         onSave: ((LinkItem) -> Void)? = nil,
         onRun: ((LinkItem) -> Void)? = nil,
         onDelete: ((LinkItem) -> Void)? = nil,
         onUninstall: ((LinkItem) -> Void)? = nil) {
        self.linkItem = linkItem
        self.onSave = onSave
        self.onRun = onRun
        self.onDelete = onDelete
        self.onUninstall = onUninstall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // App Name Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("App Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                TextField("Name", text: $linkItem.name)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Symlink Paths Section
            VStack(alignment: .leading, spacing: 20) {
                Text("Sync Setting Configuration")
                    .font(.headline)

                // FROM Path (Source)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("From:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(Source path to be linked)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !linkItem.from.isEmpty {
                            Button(action: {
                                openInFinder(path: linkItem.from)
                            }) {
                                Image(systemName: "folder")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Open in Finder")
                        }
                    }

                    HStack(spacing: 8) {
                        Text(linkItem.from.isEmpty ? "No path selected" : linkItem.from)
                            .textSelection(.enabled)
                            .foregroundColor(linkItem.from.isEmpty ? .secondary : .primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)

                        Button("Browse...") {
                            Task {
                                if let path = try await selectFile() {
                                    linkItem.from = path
                                }
                            }
                        }
                    }
                }

                // Arrow indicator
                HStack {
                    Spacer()
                    Image(systemName: "arrow.down")
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // TO Path (Destination)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("To:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("(Destination for the link)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !linkItem.to.isEmpty {
                            Button(action: {
                                openInFinder(path: linkItem.to)
                            }) {
                                Image(systemName: "folder")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Open in Finder")
                        }
                    }

                    HStack(spacing: 8) {
                        Text(linkItem.to.isEmpty ? "No path selected" : displayToPath)
                            .textSelection(.enabled)
                            .foregroundColor(linkItem.to.isEmpty ? .secondary : .primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)

                        Button("Browse...") {
                            Task {
                                if let path = try await selectFile() {
                                    linkItem.to = path
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            // Defaults Command Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Defaults Command (Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("defaults write ...", text: $linkItem.defaults)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("This command will be executed when clicking Install")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Divider()

            // Action Buttons
            HStack(spacing: 12) {
                Button("Delete", role: .destructive) {
                    onDelete?(linkItem)
                }

                Spacer()

                if symlinkIsValid {
                    Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                        .foregroundColor(.green)
                        .help("Symlink is installed and points to the correct location")
                } else if !linkItem.from.isEmpty || !linkItem.to.isEmpty {
                    Image(systemName: "square.and.arrow.down.badge.xmark.fill")
                        .foregroundColor(.red)
                        .help("Symlink is not installed")
                }

                if symlinkIsValid {
                    Button("Uninstall") {
                        onUninstall?(linkItem)
                    }
                    .disabled(!symlinkIsValid)
                } else {
                    Button("Install") {
                        onRun?(linkItem)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(linkItem.from.isEmpty || linkItem.to.isEmpty || symlinkIsValid)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 400)
        .onChange(of: linkItem.name) { oldValue, newValue in
            if oldValue != newValue {
                saveChangesToYAML()
            }
        }
        .onChange(of: linkItem.from) { oldValue, newValue in
            if oldValue != newValue {
                saveChangesToYAML()
            }
        }
        .onChange(of: linkItem.to) { oldValue, newValue in
            if oldValue != newValue {
                saveChangesToYAML()
            }
        }
        .onChange(of: linkItem.defaults) { oldValue, newValue in
            if oldValue != newValue {
                saveChangesToYAML()
            }
        }
    }

    private func saveChangesToYAML() {
        // Cancel previous save task
        saveTask?.cancel()

        // Create new debounced save task
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

            // Check if task was cancelled
            if !Task.isCancelled {
                // Trigger save callback to persist to YAML
                onSave?(linkItem)
            }
        }
    }

    private var symlinkIsValid: Bool {
        // Check if symlink exists at "from" path and points to generated destination
        guard !linkItem.from.isEmpty && !linkItem.to.isEmpty else {
            return false
        }

        let fromPath = PathUtility.expandTildeToRealHome(linkItem.from)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Check if the from path exists
        guard fileManager.fileExists(atPath: fromPath, isDirectory: &isDirectory) else {
            return false
        }

        // Check if it's a symbolic link
        guard let attributes = try? fileManager.attributesOfItem(atPath: fromPath),
              let fileType = attributes[.type] as? FileAttributeType,
              fileType == .typeSymbolicLink else {
            return false
        }

        // Check if the destination matches
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: fromPath) else {
            return false
        }

        // Generate the expected destination path from iCloud + to field
        let expectedDestination = "\(Config.expandedBackupPath)/\(linkItem.to)"

        return destination == expectedDestination
    }

    private var displayToPath: String {
        guard !linkItem.to.isEmpty else {
            return ""
        }

        // Show path inside the chosen settings folder
        return "\(Config.backupPath)/\(linkItem.to)"
    }

    func selectFile() async throws -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = true
        panel.message = "Select the path for the link"

        var filename: String?
        if panel.runModal() == .OK {
            filename = panel.url?.path
        }
        return filename
    }

    func openInFinder(path: String) {
        // A "from" field is a full path; a "to" field is just a backup name.
        let target: String
        if path.contains("/") {
            target = PathUtility.expandTildeToRealHome(path)
        } else {
            target = PathUtility.expandTildeToRealHome("\(Config.backupPath)/\(path)")
        }

        // If the target exists, reveal (and select) it in Finder. Otherwise walk
        // up to the nearest existing ancestor and open that.
        if FileOps.exists(target) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
            return
        }

        var ancestor = (target as NSString).deletingLastPathComponent
        while !ancestor.isEmpty, ancestor != "/", !FileOps.exists(ancestor) {
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        if FileOps.exists(ancestor) {
            NSWorkspace.shared.open(URL(fileURLWithPath: ancestor))
        } else {
            print("openInFinder: no existing path found for '\(path)'")
        }
    }
}

#Preview("With Data") {
    let linkItem: LinkItem = LinkItem(
        name: "Fonts",
        from: "/Users/user/Library/Fonts",
        to: "/Users/user/Documents/Takeover/Fonts"
    )
    LinkItemDetailView(linkItem: linkItem)
}

#Preview("Empty") {
    let linkItem: LinkItem = LinkItem.empty()
    LinkItemDetailView(linkItem: linkItem)
}

