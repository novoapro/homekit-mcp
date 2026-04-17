import SwiftUI

struct AutomationDetailView: View {
    let automation: Automation
    let executionLogs: [AutomationExecutionLog]
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var automations: [Automation] = []
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTrigger: () -> Void
    let onUpdate: (AutomationDraft) -> Void
    var onClone: (() -> Void)?
    var onCancelExecution: ((UUID) -> Void)?
    var onResetStatistics: (() -> Void)?
    var onImproveWithAI: ((String?) async throws -> Automation)?
    var controllerStates: [StateVariable] = []

    @State private var showingDeleteConfirmation = false
    @State private var showingResetConfirmation = false
    @State private var showingEditor = false
    @State private var isEnabled: Bool = false
    @State private var showClonedToast = false
    @State private var clonedToastTask: Task<Void, Never>?
    @State private var showingImproveSheet = false
    @State private var improvePrompt = ""
    @State private var isImproving = false
    @State private var improvedAutomation: Automation?
    @State private var improveError: String?
    @State private var aiDraftForEditor: Automation?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            statusSection
            triggersSection
            if let conditions = automation.conditions, !conditions.isEmpty {
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
        .navigationTitle(automation.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { aiDraftForEditor = nil }) {
            AutomationEditorView(
                mode: .edit(aiDraftForEditor ?? automation),
                devices: devices,
                scenes: scenes,
                automations: automations,
                controllerStates: controllerStates,
                onSave: { draft in onUpdate(draft) }
            )
        }
        .onAppear { isEnabled = automation.isEnabled }
        .onChange(of: automation.isEnabled) { newValue in isEnabled = newValue }
        .alert("Delete Automation?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This will permanently delete \"\(automation.name)\" and its execution history.")
        }
        .alert("Reset Statistics?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                onResetStatistics?()
            }
        } message: {
            Text("This will reset all execution counters and remove all execution logs for \"\(automation.name)\".")
        }
        .overlay(alignment: .bottom) {
            if showClonedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Automation duplicated")
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
        .sheet(isPresented: $showingImproveSheet) {
            AutomationImproveSheet(
                automationName: automation.name,
                prompt: $improvePrompt,
                isImproving: isImproving,
                improvedAutomation: improvedAutomation,
                error: improveError,
                onImprove: {
                    guard let onImproveWithAI else { return }
                    isImproving = true
                    improveError = nil
                    improvedAutomation = nil
                    Task {
                        do {
                            let result = try await onImproveWithAI(improvePrompt.isEmpty ? nil : improvePrompt)
                            improvedAutomation = result
                        } catch {
                            improveError = error.localizedDescription
                        }
                        isImproving = false
                    }
                },
                onOpenInEditor: {
                    guard let improved = improvedAutomation else { return }
                    aiDraftForEditor = improved
                    showingImproveSheet = false
                    improvedAutomation = nil
                    improvePrompt = ""
                    improveError = nil
                    // Small delay to allow sheet dismissal before presenting editor
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingEditor = true
                    }
                },
                onDismiss: {
                    showingImproveSheet = false
                    improvedAutomation = nil
                    improvePrompt = ""
                    improveError = nil
                }
            )
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            Toggle("Enabled", isOn: $isEnabled)
                .tint(Theme.Tint.main)
                .onChange(of: isEnabled) { newValue in
                    if newValue != automation.isEnabled {
                        onToggle()
                    }
                }

            if let description = automation.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(Theme.Text.secondary)
            }

            LabeledContent("Executions", value: "\(automation.metadata.totalExecutions)")
            LabeledContent("Continue on Error", value: automation.continueOnError ? "Yes" : "No")

            if let lastTriggered = automation.metadata.lastTriggeredAt {
                LabeledContent("Last Triggered") {
                    Text(lastTriggered, style: .relative)
                        .foregroundColor(Theme.Text.secondary)
                }
            }

            if automation.metadata.consecutiveFailures > 0 {
                LabeledContent("Consecutive Failures") {
                    Text("\(automation.metadata.consecutiveFailures)")
                        .foregroundColor(Theme.Status.error)
                }
            }

            if let tags = automation.metadata.tags, !tags.isEmpty {
                AutomationTagsRow(tags: tags)
            }
        } header: {
            Text("Status")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Triggers Section

    private var triggersSection: some View {
        Section {
            ForEach(Array(automation.triggers.enumerated()), id: \.offset) { _, trigger in
                AutomationTriggerRow(trigger: trigger, devices: devices)
            }
        } header: {
            Text("Triggers (\(automation.triggers.count))")
        } footer: {
            Text("Any trigger firing will start the automation.")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Conditions Section

    private func conditionsSection(_ conditions: [AutomationCondition]) -> some View {
        Section {
            ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                AutomationConditionRow(condition: condition, devices: devices, scenes: scenes, depth: 0)
            }
        } header: {
            Text("Execution Guards")
        } footer: {
            Text("Execution guards are evaluated after any trigger fires. Failure marks the automation as skipped.")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Blocks Section

    private var blocksSection: some View {
        Section {
            ForEach(Array(automation.blocks.enumerated()), id: \.offset) { index, block in
                AutomationBlockRow(block: block, index: index, depth: 0, devices: devices, scenes: scenes)
            }
        } header: {
            Text("Blocks (\(automation.blocks.count))")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Execution History

    private var executionHistorySection: some View {
        Section {
            ForEach(executionLogs.prefix(10)) { log in
                NavigationLink {
                    AutomationExecutionLogDetailView(log: log, onCancel: onCancelExecution)
                } label: {
                    AutomationExecutionLogRow(log: log)
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

            if onImproveWithAI != nil {
                Button {
                    showingImproveSheet = true
                } label: {
                    Label("Improve with AI", systemImage: "sparkles")
                }
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
                    Label("Duplicate Automation", systemImage: "doc.on.doc")
                }
            }

            if let onResetStatistics, automation.metadata.totalExecutions > 0 || automation.metadata.lastTriggeredAt != nil {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Statistics", systemImage: "arrow.counterclockwise")
                }
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Automation", systemImage: "trash")
            }
        }
        .listRowBackground(Theme.contentBackground)
    }
}

// MARK: - Tags Row

private struct AutomationTagsRow: View {
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

private struct AutomationTriggerRow: View {
    let trigger: AutomationTrigger
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

    private static func countLeafConditions(_ conditions: [AutomationCondition]) -> Int {
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
            Text("Match: \(Self.triggerConditionDescription(t.matchOperator))")
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
        case let .automation(t):
            HStack {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.footnote)
                    .foregroundColor(Theme.Tint.main)
                Text(t.name ?? "Automation Trigger")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text("Callable from other automations")
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

private struct AutomationConditionRow: View {
    let condition: AutomationCondition
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
                    AutomationConditionRow(condition: child, devices: devices, scenes: scenes, depth: depth + 1)
                }
            }
        case let .or(conditions):
            VStack(alignment: .leading, spacing: 4) {
                Text("ANY of (\(conditions.count))")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, child in
                    AutomationConditionRow(condition: child, devices: devices, scenes: scenes, depth: depth + 1)
                }
            }
        case let .not(inner):
            VStack(alignment: .leading, spacing: 4) {
                Text("NOT")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                AutomationConditionRow(condition: inner, devices: devices, scenes: scenes, depth: depth + 1)
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
        case let .engineState(c):
            HStack(spacing: 6) {
                Image(systemName: "cylinder.split.1x2")
                    .foregroundStyle(.teal)
                Text("State \(c.variableRef.displayDescription) \(ConditionEvaluator.comparisonDescription(c.comparison))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Block Row

private struct AutomationBlockRow: View {
    let block: AutomationBlock
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
    let action: AutomationAction
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
        case .timedControl: return "timer"
        case .webhook: return "globe"
        case .log: return "text.bubble"
        case .runScene: return "play.rectangle.fill"
        case .stateVariable: return "cylinder.split.1x2"
        }
    }

    private var actionTitle: String {
        switch action {
        case let .controlDevice(a): return a.name ?? "Control Device"
        case let .timedControl(a): return a.name ?? "Timed Control"
        case let .webhook(a): return a.name ?? "Webhook"
        case let .log(a): return a.name ?? "Log Message"
        case let .runScene(a): return a.name ?? "Run Scene"
        case let .stateVariable(a): return a.name ?? "Global Value"
        }
    }

    private var actionDetail: String {
        switch action {
        case let .controlDevice(a):
            return "Set \(devices.resolvedName(deviceId: a.deviceId, serviceId: a.serviceId)) \(devices.resolvedCharacteristicName(deviceId: a.deviceId, characteristicId: a.characteristicId)) = \(a.value.value)"
        case let .timedControl(a):
            let secs = a.durationSeconds
            let secsStr = secs.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(secs))s" : String(format: "%.1fs", secs)
            return "\(a.changes.count) change(s) · hold \(secsStr)"
        case let .webhook(a):
            return "\(a.method) \(a.url)"
        case let .log(a):
            return a.message
        case let .runScene(a):
            let sceneName = scenes.first(where: { $0.id == a.sceneId })?.name ?? a.sceneId
            return "Scene: \(sceneName)"
        case let .stateVariable(a):
            return a.operation.displayName
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

    private static func conditionHasOrphan(_ condition: AutomationCondition, deviceIds: Set<String>) -> Bool {
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
                    AutomationBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
            if let elseBlocks = b.elseBlocks, !elseBlocks.isEmpty {
                Text("Else")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Text.tertiary)
                    .padding(.leading, CGFloat((depth + 1) * 7))
                ForEach(Array(elseBlocks.enumerated()), id: \.offset) { i, nested in
                    AutomationBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
                }
            }
        default:
            if let nestedBlocks = flowControlNestedBlocks {
                ForEach(Array(nestedBlocks.enumerated()), id: \.offset) { i, nested in
                    AutomationBlockRow(block: nested, index: i, depth: depth + 1, devices: devices, scenes: scenes)
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
        case .executeAutomation: return "arrow.triangle.turn.up.right.diamond.fill"
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
        case let .executeAutomation(b): return b.name ?? "Execute Automation (\(b.executionMode.rawValue))"
        }
    }

    private var flowControlNestedBlocks: [AutomationBlock]? {
        switch flowControl {
        case .delay, .waitForState, .stop, .executeAutomation: return nil
        case .conditional: return nil // handled separately in nestedBlocksView
        case let .repeat(b): return b.blocks
        case let .repeatWhile(b): return b.blocks
        case let .group(b): return b.blocks
        }
    }
}

// MARK: - Improve with AI Sheet

private struct AutomationImproveSheet: View {
    let automationName: String
    @Binding var prompt: String
    let isImproving: Bool
    let improvedAutomation: Automation?
    let error: String?
    let onImprove: () -> Void
    let onOpenInEditor: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isImproving {
                    loadingView
                } else if let improved = improvedAutomation {
                    reviewView(improved)
                } else {
                    inputView
                }
            }
            .navigationTitle("Improve with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isImproving {
                        Button("Cancel", action: onDismiss)
                    }
                }
            }
        }
    }

    private var inputView: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Theme.Tint.main)
                    Text(automationName)
                        .fontWeight(.medium)
                }
            } header: {
                Text("Automation")
            }

            Section {
                TextField("e.g., Add a condition to only run during nighttime", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Instructions (optional)")
            } footer: {
                Text("Leave empty for an automatic review and optimization.")
            }

            if let error {
                Section {
                    Text(error)
                        .foregroundColor(Theme.Status.error)
                        .font(.footnote)
                }
            }

            Section {
                Button(action: onImprove) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Improve")
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
                .tint(Theme.Tint.main)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing and improving your automation...")
                .font(.subheadline)
                .foregroundColor(Theme.Text.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.mainBackground)
    }

    private func reviewView(_ improved: Automation) -> some View {
        Form {
            Section {
                LabeledContent("Name", value: improved.name)
                if let desc = improved.description, !desc.isEmpty {
                    LabeledContent("Description", value: desc)
                }
            } header: {
                Text("Improved Automation")
            }

            Section {
                LabeledContent("Triggers", value: "\(improved.triggers.count)")
                LabeledContent("Blocks", value: "\(improved.blocks.count)")
                LabeledContent("Execution Guards", value: "\(improved.conditions?.count ?? 0)")
            } header: {
                Text("Summary")
            }

            Section {
                Button(action: onOpenInEditor) {
                    HStack {
                        Image(systemName: "pencil.circle")
                        Text("Open in Editor")
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
                .tint(Theme.Tint.main)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
    }
}

#Preview {
    NavigationStack {
        AutomationDetailView(
            automation: PreviewData.sampleAutomations[0],
            executionLogs: PreviewData.sampleAutomationLogs,
            devices: PreviewData.sampleDevices,
            scenes: PreviewData.sampleScenes,
            onToggle: { },
            onDelete: { },
            onTrigger: { },
            onUpdate: { _ in }
        )
    }
}
