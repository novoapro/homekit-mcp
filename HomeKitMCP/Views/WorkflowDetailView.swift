import SwiftUI

struct WorkflowDetailView: View {
    let workflow: Workflow
    let executionLogs: [WorkflowExecutionLog]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTrigger: () -> Void

    @State private var showingDeleteConfirmation = false
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
        .alert("Delete Workflow?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
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
            Toggle("Enabled", isOn: .constant(workflow.isEnabled))
                .tint(Theme.Tint.main)
                .onTapGesture { onToggle() }

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
                WorkflowTriggerRow(trigger: trigger)
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
                WorkflowConditionRow(condition: condition)
            }
        } header: {
            Text("Guard Conditions")
        } footer: {
            Text("All conditions must be true for the workflow to proceed.")
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Blocks Section

    private var blocksSection: some View {
        Section {
            ForEach(Array(workflow.blocks.enumerated()), id: \.offset) { index, block in
                WorkflowBlockRow(block: block, index: index, depth: 0)
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
                WorkflowExecutionLogRow(log: log)
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

    var body: some View {
        switch trigger {
        case .deviceStateChange(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text("Device State Change")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Device: \(t.deviceId)")
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
        case .compound(let t):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text("Compound (\(t.logicOperator.rawValue.uppercased()))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("\(t.triggers.count) sub-triggers")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
        }
    }

    static func triggerConditionDescription(_ condition: TriggerCondition) -> String {
        switch condition {
        case .changed: return "Any change"
        case .equals(let v): return "== \(v.value)"
        case .notEquals(let v): return "!= \(v.value)"
        case .transitioned(let from, let to):
            if let from { return "\(from.value) → \(to.value)" }
            return "→ \(to.value)"
        case .greaterThan(let v): return "> \(v)"
        case .lessThan(let v): return "< \(v)"
        case .greaterThanOrEqual(let v): return ">= \(v)"
        case .lessThanOrEqual(let v): return "<= \(v)"
        }
    }
}

// MARK: - Condition Row

private struct WorkflowConditionRow: View {
    let condition: WorkflowCondition

    var body: some View {
        switch condition {
        case .deviceState(let c):
            VStack(alignment: .leading, spacing: 2) {
                Text("Device: \(c.deviceId)")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                Text("\(CharacteristicTypes.displayName(for: c.characteristicType)) \(ConditionEvaluator.comparisonDescription(c.comparison))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case .and(let conditions):
            Text("AND: \(conditions.count) conditions")
                .font(.subheadline)
        case .or(let conditions):
            Text("OR: \(conditions.count) conditions")
                .font(.subheadline)
        case .not:
            Text("NOT condition")
                .font(.subheadline)
        }
    }
}

// MARK: - Block Row

private struct WorkflowBlockRow: View {
    let block: WorkflowBlock
    let index: Int
    let depth: Int

    var body: some View {
        switch block {
        case .action(let action):
            ActionBlockRow(action: action, depth: depth)
        case .flowControl(let flowControl):
            FlowControlBlockRow(flowControl: flowControl, depth: depth)
        }
    }
}

// MARK: - Action Block Row

private struct ActionBlockRow: View {
    let action: WorkflowAction
    let depth: Int

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

    @ViewBuilder
    private var depthIndicators: some View {
        ForEach(0..<depth, id: \.self) { _ in
            Rectangle()
                .fill(Theme.Text.tertiary.opacity(0.3))
                .frame(width: 2)
        }
    }

    private var actionIcon: String {
        switch action {
        case .controlDevice: return "house.fill"
        case .webhook: return "globe"
        case .log: return "text.bubble"
        }
    }

    private var actionTitle: String {
        switch action {
        case .controlDevice: return "Control Device"
        case .webhook: return "Webhook"
        case .log: return "Log Message"
        }
    }

    private var actionDetail: String {
        switch action {
        case .controlDevice(let a):
            return "Set \(CharacteristicTypes.displayName(for: a.characteristicType)) = \(a.value.value) on \(a.deviceId)"
        case .webhook(let a):
            return "\(a.method) \(a.url)"
        case .log(let a):
            return a.message
        }
    }
}

// MARK: - Flow Control Block Row

private struct FlowControlBlockRow: View {
    let flowControl: FlowControlBlock
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            nestedBlocksView
        }
        .padding(.vertical, 2)
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.Text.tertiary.opacity(0.3))
                    .frame(width: 2)
            }

            Image(systemName: flowControlIcon)
                .font(.caption)
                .foregroundColor(.indigo)
            Text(flowControlTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.indigo)
        }
    }

    @ViewBuilder
    private var nestedBlocksView: some View {
        if let nestedBlocks = flowControlNestedBlocks {
            ForEach(Array(nestedBlocks.enumerated()), id: \.offset) { i, nested in
                WorkflowBlockRow(block: nested, index: i, depth: depth + 1)
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
        }
    }

    private var flowControlTitle: String {
        switch flowControl {
        case .delay(let b): return "Delay \(b.seconds)s"
        case .waitForState(let b):
            return "Wait for \(CharacteristicTypes.displayName(for: b.characteristicType)) \(ConditionEvaluator.comparisonDescription(b.condition))"
        case .conditional: return "If/Else"
        case .repeat(let b): return "Repeat \(b.count) times"
        case .repeatWhile(let b): return "Repeat while (max \(b.maxIterations))"
        case .group(let b): return b.label ?? "Group"
        }
    }

    private var flowControlNestedBlocks: [WorkflowBlock]? {
        switch flowControl {
        case .delay, .waitForState: return nil
        case .conditional(let b): return b.thenBlocks + (b.elseBlocks ?? [])
        case .repeat(let b): return b.blocks
        case .repeatWhile(let b): return b.blocks
        case .group(let b): return b.blocks
        }
    }
}

// MARK: - Execution Log Row

private struct WorkflowExecutionLogRow: View {
    let log: WorkflowExecutionLog

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.status.rawValue.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let error = log.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.Status.error)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(log.triggeredAt, style: .relative)
                .font(.caption)
                .foregroundColor(Theme.Text.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch log.status {
        case .success: return Theme.Status.active
        case .failure: return Theme.Status.error
        case .running: return .blue
        case .skipped: return Theme.Status.inactive
        case .conditionNotMet: return Theme.Status.warning
        }
    }
}
