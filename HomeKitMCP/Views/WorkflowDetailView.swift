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
    var onClone: (() -> Void)?
    var onCancelExecution: ((UUID) -> Void)?

    @State private var showingDeleteConfirmation = false
    @State private var showingEditor = false
    @State private var isEnabled: Bool = false
    @State private var showClonedToast = false
    @State private var clonedToastTask: Task<Void, Never>?
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
        .overlay(alignment: .bottom) {
            if showClonedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Workflow duplicated")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 24)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showClonedToast)
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
            Text("Execution Guards")
        } footer: {
            Text("Execution guards are evaluated after any trigger fires. Failure marks the workflow as skipped.")
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

            if let onClone {
                Button {
                    onClone()
                    clonedToastTask?.cancel()
                    showClonedToast = true
                    clonedToastTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled {
                            showClonedToast = false
                        }
                    }
                } label: {
                    Label("Duplicate Workflow", systemImage: "doc.on.doc")
                }
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
                    .font(.footnote)
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
        VStack(alignment: .leading, spacing: 4) {
            triggerContent
            triggerConditionsBadge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var triggerConditionsBadge: some View {
        if let conditions = trigger.conditions, !conditions.isEmpty {
            let count = Self.countLeafConditions(conditions)
            HStack(spacing: 4) {
                Image(systemName: "shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.indigo)
                Text("\(count) guard condition\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }
        }
    }

    private static func countLeafConditions(_ conditions: [WorkflowCondition]) -> Int {
        conditions.reduce(0) { sum, cond in
            switch cond {
            case .and(let children), .or(let children):
                return sum + countLeafConditions(children)
            case .not(let inner):
                return sum + countLeafConditions([inner])
            default:
                return sum + 1
            }
        }
    }

    @ViewBuilder
    private var triggerContent: some View {
        switch trigger {
        case let .deviceStateChange(t):
            let isOrphaned = !t.deviceId.isEmpty && !devices.contains(where: { $0.id == t.deviceId })
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.footnote)
                    .foregroundColor(Theme.Tint.main)
                Text(t.name ?? "Device State Change")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isOrphaned {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Text("Device: \(devices.resolvedName(deviceId: t.deviceId, serviceId: t.serviceId))")
                .font(.footnote)
                .foregroundColor(isOrphaned ? .orange : Theme.Text.secondary)
            Text("Characteristic: \(devices.resolvedCharacteristicName(deviceId: t.deviceId, characteristicId: t.characteristicId))")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
            Text("Condition: \(Self.triggerConditionDescription(t.condition))")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        case let .schedule(t):
            HStack {
                Image(systemName: "clock.fill")
                    .font(.footnote)
                    .foregroundColor(Theme.Tint.main)
                Text(t.name ?? "Schedule")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text(Self.scheduleDescription(t.scheduleType))
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        case let .webhook(t):
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
                .foregroundColor(Theme.Text.secondary)
        case let .workflow(t):
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
                .foregroundColor(Theme.Text.secondary)
        case let .sunEvent(t):
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
                .foregroundColor(Theme.Text.secondary)
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
            let fromStr = from.map { "\($0.value)" } ?? "any"
            let toStr = to.map { "\($0.value)" } ?? "any"
            return "\(fromStr) → \(toStr)"
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
            let isOrphaned = !c.deviceId.isEmpty && !devices.contains(where: { $0.id == c.deviceId })
            HStack(spacing: 4) {
                if isOrphaned {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Device: \(devices.resolvedName(deviceId: c.deviceId, serviceId: c.serviceId))")
                        .font(.footnote)
                        .foregroundColor(isOrphaned ? .orange : Theme.Text.secondary)
                    Text("\(devices.resolvedCharacteristicName(deviceId: c.deviceId, characteristicId: c.characteristicId)) \(ConditionEvaluator.comparisonDescription(c.comparison))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        case let .timeCondition(c):
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
        case let .sceneActive(c):
            let isOrphaned = !c.sceneId.isEmpty && !scenes.contains(where: { $0.id == c.sceneId })
            HStack(spacing: 6) {
                if isOrphaned {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(isOrphaned ? .orange : .green)
                let sceneName = scenes.first(where: { $0.id == c.sceneId })?.name ?? c.sceneId
                Text("Scene \(c.isActive ? "Active" : "Not Active"): \(sceneName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case let .and(conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ALL of (\(conditions.count))")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    WorkflowConditionRow(condition: child, devices: devices, scenes: scenes, depth: depth + 1)
                }
            }
        case let .or(conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ANY of (\(conditions.count))")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    WorkflowConditionRow(condition: child, devices: devices, scenes: scenes, depth: depth + 1)
                }
            }
        case let .not(inner):
            VStack(alignment: .leading, spacing: 4) {
                Text("NOT")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                WorkflowConditionRow(condition: inner, devices: devices, scenes: scenes, depth: depth + 1)
            }
        case let .blockResult(c):
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

// MARK: - Block Row

private struct WorkflowBlockRow: View {
    let block: WorkflowBlock
    let index: Int
    let depth: Int
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        switch block {
        case let .action(action, _):
            ActionBlockRow(action: action, depth: depth, devices: devices, scenes: scenes)
        case let .flowControl(flowControl, _):
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

    private var isOrphaned: Bool {
        switch action {
        case let .controlDevice(a):
            return !a.deviceId.isEmpty && !devices.contains(where: { $0.id == a.deviceId })
        case let .runScene(a):
            return !a.sceneId.isEmpty && !scenes.contains(where: { $0.id == a.sceneId })
        default:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            depthIndicators

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: actionIcon)
                        .font(.footnote)
                        .foregroundColor(isOrphaned ? .orange : Theme.Tint.main)
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isOrphaned {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Text(actionDetail)
                    .font(.footnote)
                    .foregroundColor(isOrphaned ? .orange : Theme.Text.secondary)
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
            return "Set \(devices.resolvedName(deviceId: a.deviceId, serviceId: a.serviceId)) \(devices.resolvedCharacteristicName(deviceId: a.deviceId, characteristicId: a.characteristicId)) = \(a.value.value)"
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

    private var hasOrphanedConditionRef: Bool {
        let deviceIds = Set(devices.map(\.id))
        switch flowControl {
        case let .waitForState(b):
            return Self.conditionHasOrphan(b.condition, deviceIds: deviceIds)
        case let .conditional(b):
            return Self.conditionHasOrphan(b.condition, deviceIds: deviceIds)
        case let .repeatWhile(b):
            return Self.conditionHasOrphan(b.condition, deviceIds: deviceIds)
        default:
            return false
        }
    }

    private static func conditionHasOrphan(_ condition: WorkflowCondition, deviceIds: Set<String>) -> Bool {
        switch condition {
        case let .deviceState(c):
            return !c.deviceId.isEmpty && !deviceIds.contains(c.deviceId)
        case let .and(conditions):
            return conditions.contains { conditionHasOrphan($0, deviceIds: deviceIds) }
        case let .or(conditions):
            return conditions.contains { conditionHasOrphan($0, deviceIds: deviceIds) }
        case let .not(inner):
            return conditionHasOrphan(inner, deviceIds: deviceIds)
        default:
            return false
        }
    }

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
                .font(.footnote)
                .foregroundColor(hasOrphanedConditionRef ? .orange : Theme.Tint.secondary)
            Text(flowControlTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(hasOrphanedConditionRef ? .orange : Theme.Tint.secondary)
            if hasOrphanedConditionRef {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var nestedBlocksView: some View {
        switch flowControl {
        case let .conditional(b):
            if !b.thenBlocks.isEmpty {
                Text("Then")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Text.tertiary)
                    .padding(.leading, CGFloat((depth + 1) * 7))
                ForEach(Array(b.thenBlocks.enumerated()), id: \.offset) { i, nested in
                    WorkflowBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
            if let elseBlocks = b.elseBlocks, !elseBlocks.isEmpty {
                Text("Else")
                    .font(.footnote)
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
        case .stop: return "arrow.uturn.backward.circle.fill"
        case .executeWorkflow: return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }

    private var flowControlTitle: String {
        switch flowControl {
        case let .delay(b): return b.name ?? "Delay \(b.seconds)s"
        case let .waitForState(b):
            return b.name ?? "Wait for condition (timeout \(Int(b.timeoutSeconds))s)"
        case let .conditional(b): return b.name ?? "If/Else"
        case let .repeat(b): return b.name ?? "Repeat \(b.count) times"
        case let .repeatWhile(b): return b.name ?? "Repeat while (max \(b.maxIterations))"
        case let .group(b): return b.name ?? b.label ?? "Group"
        case let .stop(b): return b.name ?? "Return (\(b.outcome.rawValue))"
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

#Preview {
    NavigationStack {
        WorkflowDetailView(
            workflow: PreviewData.sampleWorkflows[0],
            executionLogs: PreviewData.sampleWorkflowLogs,
            devices: PreviewData.sampleDevices,
            scenes: PreviewData.sampleScenes,
            onToggle: { },
            onDelete: { },
            onTrigger: { },
            onUpdate: { _ in }
        )
    }
}
