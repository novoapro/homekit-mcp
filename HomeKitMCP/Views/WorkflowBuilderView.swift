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
                AIInteractionLogView(interactionLog: aiWorkflowService.interactionLog)
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
                        Text("Guard Conditions")
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
                let workflow = try await aiWorkflowService.generateWorkflow(from: description)
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
                Text("Characteristic: \(CharacteristicTypes.displayName(for: t.characteristicType))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Condition: \(triggerConditionDescription(t.condition))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        case .compound(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Compound (\(t.logicOperator.rawValue.uppercased()))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("\(t.triggers.count) sub-triggers")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
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
            if let from { return "\(from.value) -> \(to.value)" }
            return "-> \(to.value)"
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
                Text("\(CharacteristicTypes.displayName(for: c.characteristicType)) \(ConditionEvaluator.comparisonDescription(c.comparison))")
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
        case .action(let action):
            BuilderActionBlockRow(action: action, depth: depth, devices: devices, scenes: scenes)
        case .flowControl(let flowControl):
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
            return "Set \(CharacteristicTypes.displayName(for: a.characteristicType)) = \(a.value.value) on \(devices.resolvedName(deviceId: a.deviceId, serviceId: a.serviceId))"
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
        case .stop: return "stop.circle.fill"
        case .executeWorkflow: return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }

    private var flowControlTitle: String {
        switch flowControl {
        case .delay(let b): return b.name ?? "Delay \(b.seconds)s"
        case .waitForState(let b):
            return b.name ?? "Wait \(devices.resolvedName(deviceId: b.deviceId, serviceId: b.serviceId)) \(CharacteristicTypes.displayName(for: b.characteristicType)) \(ConditionEvaluator.comparisonDescription(b.condition))"
        case .conditional(let b): return b.name ?? "If/Else"
        case .repeat(let b): return b.name ?? "Repeat \(b.count) times"
        case .repeatWhile(let b): return b.name ?? "Repeat while (max \(b.maxIterations))"
        case .group(let b): return b.name ?? b.label ?? "Group"
        case .stop(let b): return b.name ?? "Stop (\(b.outcome.rawValue))"
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
