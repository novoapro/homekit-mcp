import SwiftUI

struct WorkflowBuilderView: View {
    let aiWorkflowService: AIWorkflowService
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let onSave: (Workflow) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var generatedWorkflow: Workflow?
    @State private var refinementFeedback = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingSaveConfirmation = false
    @State private var showingDiagnostics = false
    @State private var selectedDeviceIds: Set<String> = []
    @State private var selectedSceneIds: Set<String> = []
    @State private var showingDevicePicker = false

    private enum BuilderPhase {
        case describe
        case review
    }

    private var currentPhase: BuilderPhase {
        generatedWorkflow != nil ? .review : .describe
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentPhase {
                case .describe:
                    describePhase
                case .review:
                    reviewPhase
                }
            }
            .background(Theme.mainBackground)
            .navigationTitle("AI Workflow Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingDiagnostics = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showingDiagnostics) {
                AIInteractionLogView(loggingService: aiWorkflowService.loggingService)
            }
        }
    }

    // MARK: - Describe Phase

    private var describePhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Describe your automation", systemImage: "text.bubble")
                        .font(.headline)

                    Text("Describe what you want to happen in plain English. The AI will generate a workflow based on your available devices.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Input area
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Theme.contentBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    Text("\(description.count) characters")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Selected devices/scenes pills
                if !selectedDeviceIds.isEmpty || !selectedSceneIds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(devices.filter { selectedDeviceIds.contains($0.id) }) { device in
                                DevicePillView(device: device) {
                                    selectedDeviceIds.remove(device.id)
                                }
                            }
                            ForEach(scenes.filter { selectedSceneIds.contains($0.id) }) { scene in
                                ScenePillView(scene: scene) {
                                    selectedSceneIds.remove(scene.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Device/scene picker toggle
                Button {
                    showingDevicePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline)
                        Text("Add Devices & Scenes")
                            .font(.subheadline)
                        if !selectedDeviceIds.isEmpty || !selectedSceneIds.isEmpty {
                            Text("\(selectedDeviceIds.count + selectedSceneIds.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Tint.main)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Theme.contentBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .sheet(isPresented: $showingDevicePicker) {
                    DeviceScenePickerSheet(
                        devices: devices,
                        scenes: scenes,
                        selectedDeviceIds: $selectedDeviceIds,
                        selectedSceneIds: $selectedSceneIds
                    )
                }

                // Example hints
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    ForEach(examplePrompts, id: \.self) { example in
                        Button {
                            description = example
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(Theme.Tint.main)
                                    .font(.footnote)
                                Text(example)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Tint.main.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Error
                if let errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Button("View Diagnostics") {
                            showingDiagnostics = true
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Generate button
                Button {
                    generateWorkflow()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(isGenerating ? "Generating..." : "Generate Workflow")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating
                                ? Color.gray : Theme.Tint.main)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Review Phase

    private var reviewPhase: some View {
        List {
            if let workflow = generatedWorkflow {
                // Summary
                Section {
                    LabeledContent("Name", value: workflow.name)
                    if let desc = workflow.description {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Generated Workflow")
                }
                .listRowBackground(Theme.contentBackground)

                // Triggers
                Section {
                    ForEach(Array(workflow.triggers.enumerated()), id: \.offset) { _, trigger in
                        WorkflowBuilderTriggerRow(trigger: trigger, devices: devices)
                    }
                } header: {
                    Text("Triggers (\(workflow.triggers.count))")
                }
                .listRowBackground(Theme.contentBackground)

                // Conditions
                if let conditions = workflow.conditions, !conditions.isEmpty {
                    Section {
                        ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                            WorkflowBuilderConditionRow(condition: condition, devices: devices, scenes: scenes)
                        }
                    } header: {
                        Text("Execution Guards")
                    }
                    .listRowBackground(Theme.contentBackground)
                }

                // Blocks
                Section {
                    ForEach(Array(workflow.blocks.enumerated()), id: \.offset) { index, block in
                        WorkflowBuilderBlockRow(block: block, index: index, depth: 0, devices: devices, scenes: scenes)
                    }
                } header: {
                    Text("Blocks (\(workflow.blocks.count))")
                }
                .listRowBackground(Theme.contentBackground)

                // Refinement
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not quite right? Provide feedback to refine:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("e.g., also turn off after 10 minutes", text: $refinementFeedback)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            refineWorkflow()
                        } label: {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isGenerating ? "Refining..." : "Refine Workflow")
                            }
                        }
                        .disabled(refinementFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    }
                } header: {
                    Text("Refine")
                }
                .listRowBackground(Theme.contentBackground)

                // Error
                if let errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Button("View Diagnostics") {
                                showingDiagnostics = true
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(Theme.contentBackground)
                }

                // Actions
                Section {
                    Button {
                        showingSaveConfirmation = true
                    } label: {
                        Label("Save Workflow", systemImage: "checkmark.circle")
                            .fontWeight(.semibold)
                    }
                    .tint(Theme.Tint.main)

                    Button {
                        generatedWorkflow = nil
                        refinementFeedback = ""
                        errorMessage = nil
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                    }
                    .tint(.secondary)
                }
                .listRowBackground(Theme.contentBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .alert("Save Workflow?", isPresented: $showingSaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let workflow = generatedWorkflow {
                    onSave(workflow)
                    dismiss()
                }
            }
        } message: {
            Text("This will save \"\(generatedWorkflow?.name ?? "")\" to your workflows. You can edit it later.")
        }
    }

    // MARK: - Actions

    private func generateWorkflow() {
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                let dIds = selectedDeviceIds.isEmpty ? nil : Array(selectedDeviceIds)
                let sIds = selectedSceneIds.isEmpty ? nil : Array(selectedSceneIds)
                let workflow = try await aiWorkflowService.generateWorkflow(from: description, deviceIds: dIds, sceneIds: sIds)
                await MainActor.run {
                    self.generatedWorkflow = workflow
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }

    private func refineWorkflow() {
        guard let current = generatedWorkflow else { return }
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                let refined = try await aiWorkflowService.refineWorkflow(current, feedback: refinementFeedback)
                await MainActor.run {
                    self.generatedWorkflow = refined
                    self.refinementFeedback = ""
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }

    // MARK: - Example Prompts

    private var examplePrompts: [String] {
        [
            "When motion is detected in the bedroom, turn on the bedside lamp at 30% brightness",
            "When the front door opens, turn on the hallway light, wait 5 minutes, then turn it off",
            "If the living room temperature drops below 20 degrees, set the thermostat to 22"
        ]
    }
}

// MARK: - Trigger Row (Builder)

private struct WorkflowBuilderTriggerRow: View {
    let trigger: WorkflowTrigger
    let devices: [DeviceModel]

    var body: some View {
        switch trigger {
        case .deviceStateChange(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Device State Change")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Device: \(devices.resolvedName(deviceId: t.deviceId, serviceId: t.serviceId))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Characteristic: \(devices.resolvedCharacteristicName(deviceId: t.deviceId, characteristicId: t.characteristicId))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Condition: \(triggerConditionDescription(t.condition))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        case .schedule(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Schedule")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(scheduleDescription(t.scheduleType))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        case .webhook(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Webhook")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Token: \(String(t.token.prefix(8)))...")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        case .workflow(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Workflow Trigger")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Callable from other workflows")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        case .sunEvent(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sunrise.fill")
                        .font(.footnote)
                        .foregroundColor(.orange)
                    Text(t.name ?? "Sunrise/Sunset")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                let offsetDesc: String = {
                    if t.offsetMinutes == 0 { return "" }
                    if t.offsetMinutes > 0 { return " +\(t.offsetMinutes)min" }
                    return " \(t.offsetMinutes)min"
                }()
                Text("\(t.event.displayName)\(offsetDesc)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func triggerConditionDescription(_ condition: TriggerCondition) -> String {
        switch condition {
        case .changed: return "Any change"
        case .equals(let v): return "== \(v.value)"
        case .notEquals(let v): return "!= \(v.value)"
        case .transitioned(let from, let to):
            let fromStr = from.map { "\($0.value)" } ?? "any"
            let toStr = to.map { "\($0.value)" } ?? "any"
            return "\(fromStr) -> \(toStr)"
        case .greaterThan(let v): return "> \(v)"
        case .lessThan(let v): return "< \(v)"
        case .greaterThanOrEqual(let v): return ">= \(v)"
        case .lessThanOrEqual(let v): return "<= \(v)"
        }
    }

    private func scheduleDescription(_ scheduleType: ScheduleType) -> String {
        switch scheduleType {
        case .once(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Once at \(formatter.string(from: date))"
        case .daily(let time):
            return "Daily at \(String(format: "%02d:%02d", time.hour, time.minute))"
        case .weekly(let time, let days):
            let dayNames = days.sorted().map(\.displayName).joined(separator: ", ")
            return "\(dayNames) at \(String(format: "%02d:%02d", time.hour, time.minute))"
        case .interval(let seconds):
            if seconds >= 3600 {
                return "Every \(Int(seconds / 3600))h"
            } else {
                return "Every \(Int(seconds / 60))m"
            }
        }
    }
}

// MARK: - Condition Row (Builder)

private struct WorkflowBuilderConditionRow: View {
    let condition: WorkflowCondition
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        switch condition {
        case .deviceState(let c):
            VStack(alignment: .leading, spacing: 2) {
                Text("Device: \(devices.resolvedName(deviceId: c.deviceId, serviceId: c.serviceId))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("\(devices.resolvedCharacteristicName(deviceId: c.deviceId, characteristicId: c.characteristicId)) \(ConditionEvaluator.comparisonDescription(c.comparison))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case .timeCondition(let c):
            HStack(spacing: 6) {
                Image(systemName: c.mode.icon)
                    .foregroundStyle(.orange)
                if c.mode == .timeRange, let start = c.startTime, let end = c.endTime {
                    Text("\(start.formatted)–\(end.formatted)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text(c.mode.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        case .sceneActive(let c):
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.green)
                let sceneName = scenes.first(where: { $0.id == c.sceneId })?.name ?? c.sceneId
                Text("Scene \"\(sceneName)\" \(c.isActive ? "active" : "not active")")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case .and(let conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ALL of (\(conditions.count))")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    WorkflowBuilderConditionRow(condition: child, devices: devices, scenes: scenes)
                        .padding(.leading, 12)
                }
            }
        case .or(let conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ANY of (\(conditions.count))")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    WorkflowBuilderConditionRow(condition: child, devices: devices, scenes: scenes)
                        .padding(.leading, 12)
                }
            }
        case .not(let inner):
            VStack(alignment: .leading, spacing: 4) {
                Text("NOT")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                WorkflowBuilderConditionRow(condition: inner, devices: devices, scenes: scenes)
                    .padding(.leading, 12)
            }
        case .blockResult(let c):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.rectangle.stack")
                    .foregroundStyle(.purple)
                switch c.scope {
                case .specific(let blockId):
                    Text("Block \(blockId.uuidString.prefix(8)) is \(c.expectedStatus.displayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                case .all:
                    Text("All blocks are \(c.expectedStatus.displayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                case .any:
                    Text("Any block is \(c.expectedStatus.displayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }
}

// MARK: - Block Row (Builder)

private struct WorkflowBuilderBlockRow: View {
    let block: WorkflowBlock
    let index: Int
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        switch block {
        case .action(let action, _):
            BuilderActionBlockRow(action: action, depth: depth, devices: devices, scenes: scenes)
        case .flowControl(let flowControl, _):
            BuilderFlowControlBlockRow(flowControl: flowControl, depth: depth, devices: devices, scenes: scenes)
        }
    }
}

private struct BuilderActionBlockRow: View {
    let action: WorkflowAction
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: actionIcon)
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(actionDetail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var actionIcon: String {
        switch action {
        case .controlDevice: return "house.fill"
        case .webhook: return "globe"
        case .log: return "text.bubble"
        case .runScene: return "play.rectangle.fill"
        }
    }

    private var actionTitle: String {
        switch action {
        case .controlDevice(let a): return a.name ?? "Control Device"
        case .webhook(let a): return a.name ?? "Webhook"
        case .log(let a): return a.name ?? "Log Message"
        case .runScene(let a): return a.name ?? "Run Scene"
        }
    }

    private var actionDetail: String {
        switch action {
        case .controlDevice(let a):
            return "Set \(devices.resolvedCharacteristicName(deviceId: a.deviceId, characteristicId: a.characteristicId)) = \(a.value.value) on \(devices.resolvedName(deviceId: a.deviceId, serviceId: a.serviceId))"
        case .webhook(let a):
            return "\(a.method) \(a.url)"
        case .log(let a):
            return a.message
        case .runScene(let a):
            let sceneName = scenes.first(where: { $0.id == a.sceneId })?.name ?? a.sceneId
            return "Run scene \"\(sceneName)\""
        }
    }
}

private struct BuilderFlowControlBlockRow: View {
    let flowControl: FlowControlBlock
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                }

                Image(systemName: flowControlIcon)
                    .font(.footnote)
                    .foregroundColor(.indigo)
                Text(flowControlTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.indigo)
            }

            if let nestedBlocks = flowControlNestedBlocks {
                ForEach(Array(nestedBlocks.enumerated()), id: \.offset) { i, nested in
                    WorkflowBuilderBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var flowControlIcon: String {
        switch flowControl {
        case .delay: return "clock"
        case .waitForState: return "hourglass"
        case .conditional: return "arrow.triangle.branch"
        case .repeat: return "repeat"
        case .repeatWhile: return "repeat.circle"
        case .group: return "folder"
        case .stop: return "arrow.uturn.backward.circle.fill"
        case .executeWorkflow: return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }

    private var flowControlTitle: String {
        switch flowControl {
        case .delay(let b): return b.name ?? "Delay \(b.seconds)s"
        case .waitForState(let b):
            return b.name ?? "Wait for condition (timeout \(Int(b.timeoutSeconds))s)"
        case .conditional(let b): return b.name ?? "If/Else"
        case .repeat(let b): return b.name ?? "Repeat \(b.count) times"
        case .repeatWhile(let b): return b.name ?? "Repeat while (max \(b.maxIterations))"
        case .group(let b): return b.name ?? b.label ?? "Group"
        case .stop(let b): return b.name ?? "Return (\(b.outcome.rawValue))"
        case .executeWorkflow(let b): return b.name ?? "Execute Workflow (\(b.executionMode.rawValue))"
        }
    }

    private var flowControlNestedBlocks: [WorkflowBlock]? {
        switch flowControl {
        case .delay, .waitForState, .stop, .executeWorkflow: return nil
        case .conditional(let b): return b.thenBlocks + (b.elseBlocks ?? [])
        case .repeat(let b): return b.blocks
        case .repeatWhile(let b): return b.blocks
        case .group(let b): return b.blocks
        }
    }
}

// MARK: - Device Pill View

private struct DevicePillView: View {
    let device: DeviceModel
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: deviceIcon(for: device.categoryType))
                .font(.caption2)
                .foregroundColor(Theme.Category.color(for: device.categoryType))
            Text(device.name)
                .font(.caption)
                .fontWeight(.medium)
            if let room = device.roomName {
                Text(room)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.Category.color(for: device.categoryType).opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Scene Pill View

private struct ScenePillView: View {
    let scene: SceneModel
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.rectangle.fill")
                .font(.caption2)
                .foregroundColor(.green)
            Text(scene.name)
                .font(.caption)
                .fontWeight(.medium)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Device/Scene Picker Sheet

private struct DeviceScenePickerSheet: View {
    let devices: [DeviceModel]
    let scenes: [SceneModel]
    @Binding var selectedDeviceIds: Set<String>
    @Binding var selectedSceneIds: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredDevicesByRoom: [(String, [DeviceModel])] {
        let filtered: [DeviceModel]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = devices
        } else {
            let query = searchText.lowercased()
            filtered = devices.filter {
                $0.name.lowercased().contains(query) ||
                ($0.roomName?.lowercased().contains(query) ?? false) ||
                $0.services.contains { $0.effectiveDisplayName.lowercased().contains(query) }
            }
        }
        let grouped = Dictionary(grouping: filtered) { $0.roomName ?? "No Room" }
        return grouped.sorted { $0.key < $1.key }
    }

    private var filteredScenes: [SceneModel] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return scenes
        }
        let query = searchText.lowercased()
        return scenes.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                let roomGroups = filteredDevicesByRoom
                if !roomGroups.isEmpty {
                    ForEach(roomGroups, id: \.0) { room, roomDevices in
                        Section {
                            ForEach(roomDevices) { device in
                                DevicePickerRow(
                                    device: device,
                                    isSelected: selectedDeviceIds.contains(device.id),
                                    onToggle: {
                                        if selectedDeviceIds.contains(device.id) {
                                            selectedDeviceIds.remove(device.id)
                                        } else {
                                            selectedDeviceIds.insert(device.id)
                                        }
                                    }
                                )
                            }
                        } header: {
                            Text(room)
                        }
                        .listRowBackground(Theme.contentBackground)
                    }
                }

                let matchedScenes = filteredScenes
                if !matchedScenes.isEmpty {
                    Section {
                        ForEach(matchedScenes) { scene in
                            ScenePickerRow(
                                scene: scene,
                                isSelected: selectedSceneIds.contains(scene.id),
                                onToggle: {
                                    if selectedSceneIds.contains(scene.id) {
                                        selectedSceneIds.remove(scene.id)
                                    } else {
                                        selectedSceneIds.insert(scene.id)
                                    }
                                }
                            )
                        }
                    } header: {
                        Text("Scenes")
                    }
                    .listRowBackground(Theme.contentBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .searchable(text: $searchText, prompt: "Filter devices & scenes")
            .navigationTitle("Select Devices & Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Device Picker Row

private struct DevicePickerRow: View {
    let device: DeviceModel
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.Category.color(for: device.categoryType).opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: deviceIcon(for: device.categoryType))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.Category.color(for: device.categoryType))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(device.services.map { $0.effectiveDisplayName }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Theme.Tint.main : .secondary.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scene Picker Row

private struct ScenePickerRow: View {
    let scene: SceneModel
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.green)
                }

                Text(scene.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Theme.Tint.main : .secondary.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Shared Device Icon Helper

private func deviceIcon(for categoryType: String) -> String {
    switch categoryType {
    case "HMAccessoryCategoryTypeLightbulb": return "lightbulb.fill"
    case "HMAccessoryCategoryTypeSwitch": return "switch.2"
    case "HMAccessoryCategoryTypeOutlet": return "poweroutlet.type.b"
    case "HMAccessoryCategoryTypeThermostat": return "thermometer"
    case "HMAccessoryCategoryTypeFan": return "fan"
    case "HMAccessoryCategoryTypeDoor": return "door.left.hand.closed"
    case "HMAccessoryCategoryTypeWindow": return "window.vertical.closed"
    case "HMAccessoryCategoryTypeDoorLock": return "lock.fill"
    case "HMAccessoryCategoryTypeSensor": return "sensor"
    case "HMAccessoryCategoryTypeGarageDoorOpener": return "door.garage.closed"
    case "HMAccessoryCategoryTypeProgrammableSwitch": return "button.programmable"
    case "HMAccessoryCategoryTypeSecuritySystem": return "shield.fill"
    case "HMAccessoryCategoryTypeBridge": return "network"
    default: return "house.fill"
    }
}

#Preview {
    WorkflowBuilderView(
        aiWorkflowService: PreviewData.previewAIWorkflowService,
        devices: PreviewData.sampleDevices,
        scenes: PreviewData.sampleScenes,
        onSave: { _ in }
    )
}
