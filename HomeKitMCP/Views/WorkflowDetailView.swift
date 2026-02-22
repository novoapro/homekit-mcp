import SwiftUI

struct WorkflowDetailView: View {
    let workflow: Workflow
    let executionLogs: [WorkflowExecutionLog]
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var workflows: [Workflow] = []
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTrigger: () -> Void
    let onUpdate: (WorkflowDraft) -> Void
    var onCancelExecution: ((UUID) -> Void)?

    @State private var showingDeleteConfirmation = false
    @State private var showingEditor = false
    @State private var isEnabled: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            statusSection
            triggersSection
            if let conditions = workflow.conditions, !conditions.isEmpty {
                conditionsSection(conditions)
            }
            blocksSection
            if !executionLogs.isEmpty {
                executionHistorySection
            }
            actionsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle(workflow.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            WorkflowEditorView(
                mode: .edit(workflow),
                devices: devices,
                scenes: scenes,
                workflows: workflows,
                onSave: { draft in onUpdate(draft) }
            )
        }
        .onAppear { isEnabled = workflow.isEnabled }
        .onChange(of: workflow.isEnabled) { newValue in isEnabled = newValue }
        .alert("Delete Workflow?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This will permanently delete \"\(workflow.name)\" and its execution history.")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            Toggle("Enabled", isOn: $isEnabled)
                .tint(Theme.Tint.main)
                .onChange(of: isEnabled) { newValue in
                    if newValue != workflow.isEnabled {
                        onToggle()
                    }
                }

            if let description = workflow.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(Theme.Text.secondary)
            }

            LabeledContent("Executions", value: "\(workflow.metadata.totalExecutions)")
            LabeledContent("Continue on Error", value: workflow.continueOnError ? "Yes" : "No")
            LabeledContent("Concurrent Execution", value: workflow.retriggerPolicy.displayName)

            if let lastTriggered = workflow.metadata.lastTriggeredAt {
                LabeledContent("Last Triggered") {
                    Text(lastTriggered, style: .relative)
                        .foregroundColor(Theme.Text.secondary)
                }
            }

            if workflow.metadata.consecutiveFailures > 0 {
                LabeledContent("Consecutive Failures") {
                    Text("\(workflow.metadata.consecutiveFailures)")
                        .foregroundColor(Theme.Status.error)
                }
            }

            if let tags = workflow.metadata.tags, !tags.isEmpty {
                WorkflowTagsRow(tags: tags)
            }
        } header: {
            Text("Status")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Triggers Section

    private var triggersSection: some View {
        Section {
            ForEach(Array(workflow.triggers.enumerated()), id: \.offset) { _, trigger in
                WorkflowTriggerRow(trigger: trigger, devices: devices)
            }
        } header: {
            Text("Triggers (\(workflow.triggers.count))")
        } footer: {
            Text("Any trigger firing will start the workflow.")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Conditions Section

    private func conditionsSection(_ conditions: [WorkflowCondition]) -> some View {
        Section {
            ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                WorkflowConditionRow(condition: condition, devices: devices, scenes: scenes, depth: 0)
            }
        } header: {
            Text("Guard Conditions")
        } footer: {
            Text("Conditions are evaluated before the workflow proceeds.")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Blocks Section

    private var blocksSection: some View {
        Section {
            ForEach(Array(workflow.blocks.enumerated()), id: \.offset) { index, block in
                WorkflowBlockRow(block: block, index: index, depth: 0, devices: devices, scenes: scenes)
            }
        } header: {
            Text("Blocks (\(workflow.blocks.count))")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Execution History

    private var executionHistorySection: some View {
        Section {
            ForEach(executionLogs.prefix(10)) { log in
                NavigationLink {
                    WorkflowExecutionLogDetailView(log: log, onCancel: onCancelExecution)
                } label: {
                    WorkflowExecutionLogRow(log: log)
                }
            }
        } header: {
            Text("Recent Executions (\(executionLogs.count))")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            Button {
                onTrigger()
            } label: {
                Label("Test Run", systemImage: "play.circle")
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Workflow", systemImage: "trash")
            }
        }
        .listRowBackground(Theme.contentBackground)
    }
}

// MARK: - Tags Row

private struct WorkflowTagsRow: View {
    let tags: [String]

    var body: some View {
        HStack {
            Text("Tags")
            Spacer()
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Tint.main.opacity(0.1))
                    .foregroundColor(Theme.Tint.main)
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Trigger Row

private struct WorkflowTriggerRow: View {
    let trigger: WorkflowTrigger
    let devices: [DeviceModel]

    var body: some View {
        switch trigger {
        case let .deviceStateChange(t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Device State Change")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Device: \(devices.resolvedName(deviceId: t.deviceId, serviceId: t.serviceId))")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                Text("Characteristic: \(CharacteristicTypes.displayName(for: t.characteristicType))")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                Text("Condition: \(Self.triggerConditionDescription(t.condition))")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
            .padding(.vertical, 2)
        case let .compound(t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Compound (\(t.logicOperator.rawValue.uppercased()))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("\(t.triggers.count) sub-triggers")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
        case let .schedule(t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Schedule")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(Self.scheduleDescription(t.scheduleType))
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
            .padding(.vertical, 2)
        case let .webhook(t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Webhook")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Token: \(String(t.token.prefix(8)))...")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
            .padding(.vertical, 2)
        case let .workflow(t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(t.name ?? "Workflow Trigger")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Callable from other workflows")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
            .padding(.vertical, 2)
        case let .sunEvent(t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sunrise.fill")
                        .font(.caption)
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
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    static func scheduleDescription(_ scheduleType: ScheduleType) -> String {
        switch scheduleType {
        case let .once(date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Once at \(formatter.string(from: date))"
        case let .daily(time):
            return "Daily at \(String(format: "%02d:%02d", time.hour, time.minute))"
        case let .weekly(time, days):
            let dayNames = days.sorted().map(\.displayName).joined(separator: ", ")
            return "\(dayNames) at \(String(format: "%02d:%02d", time.hour, time.minute))"
        case let .interval(seconds):
            if seconds >= 3600 {
                return "Every \(Int(seconds / 3600))h"
            } else {
                return "Every \(Int(seconds / 60))m"
            }
        }
    }

    static func triggerConditionDescription(_ condition: TriggerCondition) -> String {
        switch condition {
        case .changed: return "Any change"
        case let .equals(v): return "== \(v.value)"
        case let .notEquals(v): return "!= \(v.value)"
        case let .transitioned(from, to):
            if let from { return "\(from.value) → \(to.value)" }
            return "→ \(to.value)"
        case let .greaterThan(v): return "> \(v)"
        case let .lessThan(v): return "< \(v)"
        case let .greaterThanOrEqual(v): return ">= \(v)"
        case let .lessThanOrEqual(v): return "<= \(v)"
        }
    }
}

// MARK: - Condition Row

private struct WorkflowConditionRow: View {
    let condition: WorkflowCondition
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var depth: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            if depth > 0 {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Theme.Tint.secondary.opacity(0.3))
                        .frame(width: 2)
                        .padding(.trailing, 8)
                }
            }

            conditionContent
        }
    }

    @ViewBuilder
    private var conditionContent: some View {
        switch condition {
        case let .deviceState(c):
            VStack(alignment: .leading, spacing: 2) {
                Text("Device: \(devices.resolvedName(deviceId: c.deviceId, serviceId: c.serviceId))")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                Text("\(CharacteristicTypes.displayName(for: c.characteristicType)) \(ConditionEvaluator.comparisonDescription(c.comparison))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case let .sunEvent(c):
            HStack(spacing: 6) {
                Image(systemName: "sunrise.fill")
                    .foregroundStyle(.orange)
                Text("\(c.comparison.displayName) \(c.event.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case let .sceneActive(c):
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.green)
                let sceneName = scenes.first(where: { $0.id == c.sceneId })?.name ?? c.sceneId
                Text("Scene \(c.isActive ? "Active" : "Not Active"): \(sceneName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case let .and(conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ALL of (\(conditions.count))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    WorkflowConditionRow(condition: child, devices: devices, scenes: scenes, depth: depth + 1)
                }
            }
        case let .or(conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ANY of (\(conditions.count))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    WorkflowConditionRow(condition: child, devices: devices, scenes: scenes, depth: depth + 1)
                }
            }
        case let .not(inner):
            VStack(alignment: .leading, spacing: 4) {
                Text("NOT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                WorkflowConditionRow(condition: inner, devices: devices, scenes: scenes, depth: depth + 1)
            }
        }
    }
}

// MARK: - Block Row

private struct WorkflowBlockRow: View {
    let block: WorkflowBlock
    let index: Int
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        switch block {
        case let .action(action):
            ActionBlockRow(action: action, depth: depth, devices: devices, scenes: scenes)
        case let .flowControl(flowControl):
            FlowControlBlockRow(flowControl: flowControl, depth: depth, devices: devices, scenes: scenes)
        }
    }
}

// MARK: - Action Block Row

private struct ActionBlockRow: View {
    let action: WorkflowAction
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        HStack(spacing: 4) {
            depthIndicators

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: actionIcon)
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(actionDetail)
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var depthIndicators: some View {
        ForEach(0 ..< depth, id: \.self) { _ in
            Rectangle()
                .fill(Theme.Tint.main.opacity(0.3))
                .frame(width: 3)
                .cornerRadius(1.5)
        }
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
        case let .controlDevice(a): return a.name ?? "Control Device"
        case let .webhook(a): return a.name ?? "Webhook"
        case let .log(a): return a.name ?? "Log Message"
        case let .runScene(a): return a.name ?? "Run Scene"
        }
    }

    private var actionDetail: String {
        switch action {
        case let .controlDevice(a):
            return "Set \(devices.resolvedName(deviceId: a.deviceId, serviceId: a.serviceId)) \(CharacteristicTypes.displayName(for: a.characteristicType)) = \(a.value.value)"
        case let .webhook(a):
            return "\(a.method) \(a.url)"
        case let .log(a):
            return a.message
        case let .runScene(a):
            let sceneName = scenes.first(where: { $0.id == a.sceneId })?.name ?? a.sceneId
            return "Scene: \(sceneName)"
        }
    }
}

// MARK: - Flow Control Block Row

private struct FlowControlBlockRow: View {
    let flowControl: FlowControlBlock
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            nestedBlocksView
        }
        .padding(.vertical, 2)
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< depth, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.Tint.main.opacity(0.3))
                    .frame(width: 3)
                    .cornerRadius(1.5)
            }

            Image(systemName: flowControlIcon)
                .font(.caption)
                .foregroundColor(Theme.Tint.secondary)
            Text(flowControlTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Theme.Tint.secondary)
        }
    }

    @ViewBuilder
    private var nestedBlocksView: some View {
        switch flowControl {
        case let .conditional(b):
            if !b.thenBlocks.isEmpty {
                Text("Then")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Text.tertiary)
                    .padding(.leading, CGFloat((depth + 1) * 7))
                ForEach(Array(b.thenBlocks.enumerated()), id: \.offset) { i, nested in
                    WorkflowBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
            if let elseBlocks = b.elseBlocks, !elseBlocks.isEmpty {
                Text("Else")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Text.tertiary)
                    .padding(.leading, CGFloat((depth + 1) * 7))
                ForEach(Array(elseBlocks.enumerated()), id: \.offset) { i, nested in
                    WorkflowBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
        default:
            if let nestedBlocks = flowControlNestedBlocks {
                ForEach(Array(nestedBlocks.enumerated()), id: \.offset) { i, nested in
                    WorkflowBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
        }
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
        case let .delay(b): return b.name ?? "Delay \(b.seconds)s"
        case let .waitForState(b):
            return b.name ?? "Wait \(devices.resolvedName(deviceId: b.deviceId, serviceId: b.serviceId)) \(CharacteristicTypes.displayName(for: b.characteristicType)) \(ConditionEvaluator.comparisonDescription(b.condition))"
        case let .conditional(b): return b.name ?? "If/Else"
        case let .repeat(b): return b.name ?? "Repeat \(b.count) times"
        case let .repeatWhile(b): return b.name ?? "Repeat while (max \(b.maxIterations))"
        case let .group(b): return b.name ?? b.label ?? "Group"
        case let .stop(b): return b.name ?? "Stop (\(b.outcome.rawValue))"
        case let .executeWorkflow(b): return b.name ?? "Execute Workflow (\(b.executionMode.rawValue))"
        }
    }

    private var flowControlNestedBlocks: [WorkflowBlock]? {
        switch flowControl {
        case .delay, .waitForState, .stop, .executeWorkflow: return nil
        case .conditional: return nil // handled separately in nestedBlocksView
        case let .repeat(b): return b.blocks
        case let .repeatWhile(b): return b.blocks
        case let .group(b): return b.blocks
        }
    }
}
