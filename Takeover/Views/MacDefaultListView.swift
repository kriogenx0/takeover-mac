import SwiftUI
import SwiftData

struct MacDefaultListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MacDefault.name) private var macDefaults: [MacDefault]
    @State private var selection: MacDefault? = nil
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                Group {
                    if macDefaults.isEmpty {
                        Text("No Mac Defaults")
                            .foregroundColor(.secondary)
                    } else {
                        let grouped = Dictionary(grouping: macDefaults, by: { displayDomain($0.domain) })
                        let domains = grouped.keys.sorted { a, b in a == "Global" ? true : b == "Global" ? false : a < b }
                        List(selection: $selection) {
                            ForEach(domains, id: \.self) { domain in
                                Section {
                                    ForEach(grouped[domain]!.sorted { $0.key < $1.key }, id: \.self) { item in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name)
                                                    .fontWeight(.medium)
                                                HStack {
                                                    Text(item.key)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                    if !item.value.isEmpty {
                                                        Spacer()
                                                        Text(item.value)
                                                            .font(.caption)
                                                            .foregroundColor(.accentColor)
                                                            .lineLimit(1)
                                                    }
                                                }
                                            }
                                        }
                                        .tag(item)
                                        .contextMenu {
                                            Button("Capture") {
                                                MacDefaultInstaller.capture(macDefault: item)
                                                try? modelContext.save()
                                                Task { await saveToYAML() }
                                            }
                                            Button("Apply") {
                                                MacDefaultInstaller.apply(macDefault: item)
                                            }
                                            .disabled(item.value.isEmpty)
                                            Divider()
                                            Button("Delete", role: .destructive) { onDelete(item) }
                                        }
                                    }
                                } header: {
                                    Text(domain)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .listStyle(.sidebar)
                        .onAppear {
                            if selection == nil && !macDefaults.isEmpty {
                                selection = macDefaults.first
                            }
                        }
                    }
                }
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 300)
                Divider()
            }

            Group {
                if let item = selection {
                    MacDefaultDetailView(macDefault: item, onSave: onSave, onDelete: onDelete)
                } else {
                    Text("No Default Selected")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { withAnimation { sidebarVisible.toggle() } }) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: applyAll) {
                    Label("Apply All", systemImage: "checkmark.circle")
                }
                .help("Apply all captured defaults to the system")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: addItem) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    private func displayDomain(_ domain: String) -> String {
        (domain == "NSGlobalDomain" || domain == "-g") ? "Global" : domain
    }

    private func applyAll() {
        MacDefaultInstaller.applyAll(Array(macDefaults))
    }

    private func addItem() {
        let newItem = MacDefault(name: "New Default")
        modelContext.insert(newItem)
        selection = newItem
        Task { await saveToYAML() }
    }

    private func onSave(_ item: MacDefault) {
        try? modelContext.save()
        Task { await saveToYAML() }
    }

    private func onDelete(_ item: MacDefault) {
        let index = macDefaults.firstIndex(of: item)
        let nextSelection: MacDefault? = {
            guard let i = index else { return nil }
            if i < macDefaults.count - 1 { return macDefaults[i + 1] }
            if i > 0 { return macDefaults[i - 1] }
            return nil
        }()
        withAnimation {
            modelContext.delete(item)
            selection = nextSelection
        }
        Task { await saveToYAML() }
    }

    @MainActor
    private func saveToYAML() async {
        let configs = macDefaults
            .filter { !$0.value.isEmpty }
            .map {
                MacDefaultConfig(
                    name: $0.name,
                    domain: $0.domain,
                    key: $0.key,
                    type: $0.type,
                    value: $0.value,
                    hostFlag: $0.hostFlag.isEmpty ? nil : $0.hostFlag,
                    postCommand: $0.postCommand.isEmpty ? nil : $0.postCommand,
                    capturedOSMajorVersion: $0.capturedOSMajorVersion == 0 ? nil : $0.capturedOSMajorVersion
                )
            }
        guard var settings = SettingsManager.shared.settings else { return }
        settings.macDefaults = configs
        try? await SettingsManager.shared.saveSettings(settings)
    }
}

struct MacDefaultDetailView: View {
    @Bindable var macDefault: MacDefault

    var onSave: ((MacDefault) -> Void)?
    var onDelete: ((MacDefault) -> Void)?

    @State private var captureStatus: String? = nil
    @State private var captureIsSuccess = false
    @State private var saveTask: Task<Void, Never>?
    @State private var systemValue: String? = nil

    let typeOptions = ["string", "int", "integer", "float", "bool"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Name", text: $macDefault.name)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Default Configuration")
                    .font(.headline)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Domain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("-g, com.apple.dock, NSGlobalDomain", text: $macDefault.domain)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $macDefault.type) {
                            ForEach(typeOptions, id: \.self) { Text($0) }
                        }
                        .frame(minWidth: 90)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("com.apple.trackpad.scaling", text: $macDefault.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Host Flag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("-currentHost", text: $macDefault.hostFlag)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 110)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Value")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let status = captureStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(captureIsSuccess ? .green : .orange)
                        }
                    }
                    TextField("captured value", text: $macDefault.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                if !macDefault.domain.isEmpty && !macDefault.key.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("System Value")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: refreshSystemValue) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.plain)
                            .help("Read the current system value without changing the stored value")
                        }
                        Text(systemValue.map { $0.isEmpty ? "Not set" : $0 } ?? "Unknown")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                    }
                }

                if macDefault.capturedOSMajorVersion != 0 {
                    HStack(spacing: 4) {
                        Text("Captured on macOS \(macDefault.capturedOSMajorVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if macDefault.capturedOSMajorVersion != SystemInfo.macOSMajorVersion {
                            Label("Running macOS \(SystemInfo.macOSMajorVersion)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            if !macDefault.domain.isEmpty && !macDefault.key.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commands")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(macDefault.readCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                    if !macDefault.value.isEmpty {
                        Text(macDefault.writeCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Post Command (Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $macDefault.postCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            Spacer()

            Divider()

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onDelete?(macDefault)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Spacer()

                Button {
                                    let result = MacDefaultInstaller.capture(macDefault: macDefault)
                                    let notFound = result.isEmpty
                                        || result.contains("does not exist")
                                        || result.contains("The domain/defaults pair")
                                    captureStatus = notFound ? "Not found" : "Captured"
                                    captureIsSuccess = !notFound
                                    onSave?(macDefault)
                                } label: {
                                    Label("Capture", systemImage: "arrow.down.circle")
                                }
                .disabled(macDefault.domain.isEmpty || macDefault.key.isEmpty)

                Button {
                    MacDefaultInstaller.apply(macDefault: macDefault)
                } label: {
                    Label("Apply", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(macDefault.value.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
        .onChange(of: macDefault.name)        { _, _ in scheduleSave() }
        .onChange(of: macDefault.domain)      { _, _ in scheduleSave() }
        .onChange(of: macDefault.key)         { _, _ in scheduleSave() }
        .onChange(of: macDefault.type)        { _, _ in scheduleSave() }
        .onChange(of: macDefault.value)       { _, _ in scheduleSave() }
        .onChange(of: macDefault.hostFlag)    { _, _ in scheduleSave() }
        .onChange(of: macDefault.postCommand) { _, _ in scheduleSave() }
        .onChange(of: macDefault.id)          { _, _ in refreshSystemValue() }
        .onAppear { refreshSystemValue() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { onSave?(macDefault) }
        }
    }

    private func refreshSystemValue() {
        guard !macDefault.domain.isEmpty, !macDefault.key.isEmpty else {
            systemValue = nil
            return
        }
        systemValue = MacDefaultInstaller.peekSystemValue(macDefault: macDefault)
    }
}
