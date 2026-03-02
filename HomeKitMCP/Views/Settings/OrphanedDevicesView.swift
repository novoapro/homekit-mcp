import SwiftUI

struct OrphanedDevicesView: View {
    let registryService: DeviceRegistryService
    let homeKitManager: HomeKitManager
    let workflowStorageService: WorkflowStorageService
    var viewModel: SettingsViewModel?

    @State private var orphanedDevices: [DeviceRegistryEntry] = []
    @State private var orphanedScenes: [SceneRegistryEntry] = []
    @State private var unresolvedServiceRefs: [(workflowName: String, deviceName: String, serviceId: String, location: String)] = []
    @State private var replaceDeviceEntry: DeviceRegistryEntry?
    @State private var replaceSceneEntry: SceneRegistryEntry?
    @State private var removeDeviceEntry: DeviceRegistryEntry?
    @State private var removeSceneEntry: SceneRegistryEntry?
    @State private var affectedWorkflowNames: [String] = []
    @State private var showingResetConfirmation = false
    @State private var isValidating = false
    @State private var lastValidationMessage: String?

    var body: some View {
        Form {
            if let vm = viewModel {
                Section {
                    Toggle("Hide Room Name in Device Names", isOn: Binding(
                        get: { vm.hideRoomNameInTheApp },
                        set: { vm.hideRoomNameInTheApp = $0 }
                    ))

                    Toggle("Use Service Type as Service Name", isOn: Binding(
                        get: { vm.useServiceTypeAsName },
                        set: { vm.useServiceTypeAsName = $0 }
                    ))
                } header: {
                    Label("Display", systemImage: "paintbrush")
                } footer: {
                    Text("\"Hide Room Name\" strips the room prefix from device names (e.g. \"Bedroom Light\" becomes \"Light\"). \"Use Service Type as Name\" replaces each service's default name with its generic type (e.g. \"Lightbulb\", \"Switch\"). Per-service custom names take precedence over both settings.")
                }

                Section {
                    Toggle("Enable State Polling", isOn: Binding(
                        get: { vm.pollingEnabled },
                        set: { vm.pollingEnabled = $0 }
                    ))

                    Picker("Polling Interval", selection: Binding(
                        get: { vm.pollingInterval },
                        set: { vm.pollingInterval = $0 }
                    )) {
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("120 seconds").tag(120)
                        Text("300 seconds").tag(300)
                    }
                    .disabled(!vm.pollingEnabled)
                    .opacity(vm.pollingEnabled ? 1 : 0.5)
                } header: {
                    Label("State Polling", systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text("Periodically reads device states from HomeKit to detect missed callbacks. Logs corrections when actual state differs from cached state.")
                }

                Section {
                    Button("Reset Device Settings", role: .destructive) {
                        showingResetConfirmation = true
                    }
                } header: {
                    Label("Data", systemImage: "externaldrive")
                } footer: {
                    Text("Resets all per-characteristic enabled/observed toggles to defaults (enabled: on, observed: off).")
                }
            }

            if orphanedDevices.isEmpty && orphanedScenes.isEmpty && unresolvedServiceRefs.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                            Text("All Entities Resolved")
                                .font(.headline)
                                .foregroundStyle(Theme.Text.primary)
                            Text("Every device, service, and scene reference is valid.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Text.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }
            }

            if !orphanedDevices.isEmpty {
                Section {
                    ForEach(orphanedDevices, id: \.stableId) { entry in
                        orphanedDeviceRow(entry)
                    }
                } header: {
                    Label("Orphaned Devices (\(orphanedDevices.count))", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("These devices were previously registered but can no longer be found in HomeKit. Replace them with a current device or remove them from the registry.")
                }
            }

            if !orphanedScenes.isEmpty {
                Section {
                    ForEach(orphanedScenes, id: \.stableId) { entry in
                        orphanedSceneRow(entry)
                    }
                } header: {
                    Label("Orphaned Scenes (\(orphanedScenes.count))", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("These scenes were previously registered but can no longer be found in HomeKit.")
                }
            }

            if !unresolvedServiceRefs.isEmpty {
                Section {
                    ForEach(Array(unresolvedServiceRefs.enumerated()), id: \.offset) { _, ref in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ref.workflowName)
                                .font(.body)
                                .foregroundStyle(Theme.Text.primary)
                            HStack(spacing: 4) {
                                Text("Device: \(ref.deviceName)")
                                Text("in \(ref.location)")
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.Text.secondary)
                            Text("Service ID: \(ref.serviceId)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Text.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("Orphaned Service References (\(unresolvedServiceRefs.count))", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("These workflows reference service IDs that don't exist in their device's registry entry. Use \"Validate & Repair\" below to attempt auto-repair.")
                }
            }

            Section {
                Button {
                    Task { await runValidation() }
                } label: {
                    HStack {
                        Label("Validate & Repair Workflows", systemImage: "wrench.and.screwdriver")
                        if isValidating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isValidating)
                if let message = lastValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }
            } footer: {
                Text("Checks all workflow references against the device registry and auto-repairs mismatched service IDs and characteristic type formats.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Device Registry")
        .task { await loadOrphans() }
        .sheet(item: $replaceDeviceEntry) { entry in
            ReplacementDevicePickerSheet(
                orphanedEntry: entry,
                devices: homeKitManager.getAllDevices()
            ) { selectedDevice in
                Task {
                    await registryService.remapDevice(stableId: entry.stableId, to: selectedDevice)
                    await loadOrphans()
                }
            }
        }
        .sheet(item: $replaceSceneEntry) { entry in
            ReplacementScenePickerSheet(
                orphanedEntry: entry,
                scenes: homeKitManager.getAllScenes()
            ) { selectedScene in
                Task {
                    await registryService.remapScene(stableId: entry.stableId, to: selectedScene)
                    await loadOrphans()
                }
            }
        }
        .alert(
            "Remove Device",
            isPresented: Binding(
                get: { removeDeviceEntry != nil },
                set: { if !$0 { removeDeviceEntry = nil; affectedWorkflowNames = [] } }
            ),
            presenting: removeDeviceEntry
        ) { entry in
            Button("Remove", role: .destructive) {
                Task {
                    await registryService.removeDevice(stableId: entry.stableId)
                    await loadOrphans()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            if affectedWorkflowNames.isEmpty {
                Text("Remove \"\(entry.name)\" from the registry? No workflows reference this device.")
            } else {
                Text("Remove \"\(entry.name)\"? The following workflows reference this device and will need to be updated:\n\n\(affectedWorkflowNames.joined(separator: "\n"))")
            }
        }
        .alert(
            "Remove Scene",
            isPresented: Binding(
                get: { removeSceneEntry != nil },
                set: { if !$0 { removeSceneEntry = nil; affectedWorkflowNames = [] } }
            ),
            presenting: removeSceneEntry
        ) { entry in
            Button("Remove", role: .destructive) {
                Task {
                    await registryService.removeScene(stableId: entry.stableId)
                    await loadOrphans()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            if affectedWorkflowNames.isEmpty {
                Text("Remove \"\(entry.name)\" from the registry? No workflows reference this scene.")
            } else {
                Text("Remove \"\(entry.name)\"? The following workflows reference this scene and will need to be updated:\n\n\(affectedWorkflowNames.joined(separator: "\n"))")
            }
        }
        .alert("Reset Device Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    await registryService.resetAllSettings()
                }
            }
        } message: {
            Text("This will reset all enabled/observed toggles to their defaults (enabled: on, observed: off).")
        }
    }

    // MARK: - Rows

    private func orphanedDeviceRow(_ entry: DeviceRegistryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: categoryIcon(for: entry.categoryType))
                    .foregroundStyle(.orange)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                        .foregroundStyle(Theme.Text.primary)

                    HStack(spacing: 8) {
                        if let room = entry.roomName {
                            Label(room, systemImage: "location")
                        }
                        Label("\(entry.services.count) service\(entry.services.count == 1 ? "" : "s")", systemImage: "square.stack.3d.up")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Text.secondary)
                }

                Spacer()
            }

            if let hwKey = entry.hardwareKey {
                Text(hwKey)
                    .font(.caption2)
                    .foregroundStyle(Theme.Text.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                Button {
                    replaceDeviceEntry = entry
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.swap")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    Task {
                        let workflows = await workflowStorageService.getAllWorkflows()
                        let affected = registryService.findWorkflowsReferencing(deviceStableId: entry.stableId, in: workflows)
                        affectedWorkflowNames = affected.map { "\($0.workflowName) (\($0.locations.joined(separator: ", ")))" }
                        removeDeviceEntry = entry
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func orphanedSceneRow(_ entry: SceneRegistryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 20)

                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(Theme.Text.primary)

                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    replaceSceneEntry = entry
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.swap")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    Task {
                        let workflows = await workflowStorageService.getAllWorkflows()
                        let affected = registryService.findWorkflowsReferencing(sceneStableId: entry.stableId, in: workflows)
                        affectedWorkflowNames = affected.map { "\($0.workflowName) (\($0.locations.joined(separator: ", ")))" }
                        removeSceneEntry = entry
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func loadOrphans() async {
        orphanedDevices = await registryService.unresolvedDevices()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        orphanedScenes = await registryService.unresolvedScenes()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let workflows = await workflowStorageService.getAllWorkflows()
        unresolvedServiceRefs = await registryService.unresolvedServiceReferences(in: workflows)
    }

    private func runValidation() async {
        isValidating = true
        defer { isValidating = false }

        let workflows = await workflowStorageService.getAllWorkflows()
        let validation = await WorkflowMigrationService.validateAndRepairReferences(
            workflows, registry: registryService
        )

        if !validation.autoFixed.isEmpty {
            await workflowStorageService.replaceAll(workflows: validation.updatedWorkflows)
        }

        let fixedCount = validation.autoFixed.count
        let unresolvedCount = validation.unresolvable.count
        if fixedCount == 0 && unresolvedCount == 0 {
            lastValidationMessage = "All workflow references are valid."
        } else {
            var parts: [String] = []
            if fixedCount > 0 { parts.append("Auto-fixed \(fixedCount) issue(s).") }
            if unresolvedCount > 0 { parts.append("\(unresolvedCount) issue(s) need manual reconfiguration.") }
            lastValidationMessage = parts.joined(separator: " ")
        }

        await loadOrphans()
    }

    private func categoryIcon(for categoryType: String) -> String {
        switch categoryType.lowercased() {
        case "lightbulb": return "lightbulb.fill"
        case "switch", "outlet": return "switch.2"
        case "thermostat": return "thermometer"
        case "sensor": return "sensor.fill"
        case "fan": return "fan.fill"
        case "lock", "lock-mechanism": return "lock.fill"
        case "garage-door-opener": return "door.garage.closed"
        case "door": return "door.left.hand.closed"
        case "window": return "window.vertical.closed"
        case "window-covering": return "blinds.vertical.closed"
        case "security-system": return "shield.fill"
        case "camera", "ip-camera", "video-doorbell": return "camera.fill"
        case "air-purifier": return "aqi.medium"
        case "humidifier-dehumidifier": return "humidity.fill"
        case "sprinkler": return "sprinkler.and.droplets.fill"
        case "programmable-switch": return "button.programmable"
        default: return "house.fill"
        }
    }
}

// MARK: - Identifiable Conformances

extension DeviceRegistryEntry: Identifiable {
    var id: String { stableId }
}

extension SceneRegistryEntry: Identifiable {
    var id: String { stableId }
}

#Preview {
    NavigationStack {
        OrphanedDevicesView(
            registryService: DeviceRegistryService(),
            homeKitManager: PreviewData.previewHomeKitManager,
            workflowStorageService: PreviewData.previewWorkflowStorageService
        )
    }
}

// MARK: - Replacement Device Picker Sheet

private struct ReplacementDevicePickerSheet: View {
    let orphanedEntry: DeviceRegistryEntry
    let devices: [DeviceModel]
    let onSelect: (DeviceModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private struct DeviceGroup: Identifiable {
        let roomName: String
        var id: String { roomName }
        let devices: [DeviceModel]
    }

    private var filteredDevicesByRoom: [DeviceGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [DeviceModel]
        if query.isEmpty {
            filtered = devices
        } else {
            filtered = devices.filter {
                $0.name.lowercased().contains(query) ||
                ($0.roomName ?? "").lowercased().contains(query)
            }
        }
        let grouped = Dictionary(grouping: filtered) { $0.roomName ?? "No Room" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { DeviceGroup(roomName: $0.key, devices: $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replacing: \(orphanedEntry.name)")
                                .font(.subheadline.bold())
                            if let room = orphanedEntry.roomName {
                                Text(room)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                ForEach(filteredDevicesByRoom) { group in
                    Section(group.roomName) {
                        ForEach(group.devices) { device in
                            Button {
                                onSelect(device)
                                dismiss()
                            } label: {
                                HStack {
                                    Label {
                                        Text(device.name)
                                            .foregroundColor(Theme.Text.primary)
                                    } icon: {
                                        Image(systemName: categoryIcon(for: device.categoryType))
                                    }
                                    Spacer()
                                    if !device.isReachable {
                                        Text("Offline")
                                            .font(.footnote)
                                            .foregroundColor(Theme.Text.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search devices")
            .navigationTitle("Select Replacement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func categoryIcon(for categoryType: String) -> String {
        switch categoryType.lowercased() {
        case "lightbulb": return "lightbulb.fill"
        case "switch", "outlet": return "switch.2"
        case "thermostat": return "thermometer"
        case "sensor": return "sensor.fill"
        case "fan": return "fan.fill"
        case "lock", "lock-mechanism": return "lock.fill"
        case "garage-door-opener": return "door.garage.closed"
        case "door": return "door.left.hand.closed"
        case "window": return "window.vertical.closed"
        case "window-covering": return "blinds.vertical.closed"
        case "security-system": return "shield.fill"
        case "camera", "ip-camera", "video-doorbell": return "camera.fill"
        case "air-purifier": return "aqi.medium"
        case "humidifier-dehumidifier": return "humidity.fill"
        case "sprinkler": return "sprinkler.and.droplets.fill"
        case "programmable-switch": return "button.programmable"
        default: return "house.fill"
        }
    }
}

// MARK: - Replacement Scene Picker Sheet

private struct ReplacementScenePickerSheet: View {
    let orphanedEntry: SceneRegistryEntry
    let scenes: [SceneModel]
    let onSelect: (SceneModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredScenes: [SceneModel] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            return scenes.sorted { $0.name < $1.name }
        }
        return scenes.filter { $0.name.lowercased().contains(query) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Replacing: \(orphanedEntry.name)")
                            .font(.subheadline.bold())
                    }
                }

                Section("Available Scenes") {
                    ForEach(filteredScenes) { scene in
                        Button {
                            onSelect(scene)
                            dismiss()
                        } label: {
                            Label {
                                Text(scene.name)
                                    .foregroundColor(Theme.Text.primary)
                            } icon: {
                                Image(systemName: "play.rectangle.fill")
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search scenes")
            .navigationTitle("Select Replacement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
