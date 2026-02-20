import SwiftUI

struct WorkflowBuilderView: View {
    let aiWorkflowService: AIWorkflowService
    let devices: [DeviceModel]
    let onSave: (Workflow) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var generatedWorkflow: Workflow?
    @State private var refinementFeedback = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingSaveConfirmation = false

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
                        .font(.caption)
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
                                    .font(.caption)
                                Text(example)
                                    .font(.caption)
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
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.red)
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
                        WorkflowBuilderTriggerRow(trigger: trigger)
                    }
                } header: {
                    Text("Triggers (\(workflow.triggers.count))")
                }
                .listRowBackground(Theme.contentBackground)

                // Conditions
                if let conditions = workflow.conditions, !conditions.isEmpty {
                    Section {
                        ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                            WorkflowBuilderConditionRow(condition: condition)
                        }
                    } header: {
                        Text("Guard Conditions")
                    }
                    .listRowBackground(Theme.contentBackground)
                }

                // Blocks
                Section {
                    ForEach(Array(workflow.blocks.enumerated()), id: \.offset) { index, block in
                        WorkflowBuilderBlockRow(block: block, index: index, depth: 0)
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
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
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
                    .foregroundColor(.secondary)
                Text("Characteristic: \(CharacteristicTypes.displayName(for: t.characteristicType))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Condition: \(triggerConditionDescription(t.condition))")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
            }
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
}

// MARK: - Condition Row (Builder)

private struct WorkflowBuilderConditionRow: View {
    let condition: WorkflowCondition

    var body: some View {
        switch condition {
        case .deviceState(let c):
            VStack(alignment: .leading, spacing: 2) {
                Text("Device: \(c.deviceId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

// MARK: - Block Row (Builder)

private struct WorkflowBuilderBlockRow: View {
    let block: WorkflowBlock
    let index: Int
    let depth: Int

    var body: some View {
        switch block {
        case .action(let action):
            BuilderActionBlockRow(action: action, depth: depth)
        case .flowControl(let flowControl):
            BuilderFlowControlBlockRow(flowControl: flowControl, depth: depth)
        }
    }
}

private struct BuilderActionBlockRow: View {
    let action: WorkflowAction
    let depth: Int

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
                        .font(.caption)
                        .foregroundColor(Theme.Tint.main)
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(actionDetail)
                    .font(.caption)
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

private struct BuilderFlowControlBlockRow: View {
    let flowControl: FlowControlBlock
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
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

            if let nestedBlocks = flowControlNestedBlocks {
                ForEach(Array(nestedBlocks.enumerated()), id: \.offset) { i, nested in
                    WorkflowBuilderBlockRow(block: nested, index: i, depth: depth + 1)
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
