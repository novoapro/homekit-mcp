import SwiftUI

struct BlockEditorRow: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let allowNesting: Bool
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?
    let onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var moveTargets: [MoveTarget] = []
    var onMoveToContainer: ((UUID, String) -> Void)?
    var isReorderMode: Bool = false
    var workflows: [Workflow] = []
    @State private var isExpanded: Bool = true
    @State private var isEditingName: Bool = false

    var body: some View {
        if isReorderMode {
            blockLabel
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                blockContent
            } label: {
                blockLabel
            }
            .contextMenu {
                if let onDuplicate {
                    Button { onDuplicate() } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                }
                if onDelete != nil || onDuplicate != nil {
                    Divider()
                }
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Remove Block", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var blockLabel: some View {
        HStack(spacing: 8) {
            if isReorderMode {
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundColor(Theme.Text.tertiary)
                    .frame(width: 28, height: 28)
            }

            Image(systemName: block.blockType.icon)
                .font(.footnote)
                .foregroundColor(block.blockType.isFlowControl ? Theme.Tint.secondary : Theme.Tint.main)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.blockType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isEditingName {
                    TextField("Name", text: blockNameBinding)
                        .font(.footnote)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { isEditingName = false }
                } else {
                    Text(block.displayName(devices: devices, scenes: scenes))
                        .font(.footnote)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isReorderMode {
                HStack(spacing: 4) {
                    Button {
                        isEditingName.toggle()
                    } label: {
                        Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                            .font(.subheadline)
                            .foregroundColor(Theme.Text.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let onDuplicate {
                        Button {
                            onDuplicate()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.subheadline)
                                .foregroundColor(Theme.Text.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Duplicate")
                    }

                    if let onMoveToContainer, !moveTargets.isEmpty {
                        Menu {
                            ForEach(moveTargets) { target in
                                Button {
                                    onMoveToContainer(target.containerBlockId, target.label)
                                } label: {
                                    Label(target.description, systemImage: target.icon)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.right.square")
                                .font(.subheadline)
                                .foregroundColor(Theme.Text.secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Move to")
                    }

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove")
                    }
                }
            }
        }
    }

    /// Binding to the block's name regardless of which block type it is.
    private var blockNameBinding: Binding<String> {
        Binding(
            get: {
                switch block.blockType {
                case let .controlDevice(d): return d.name
                case let .webhook(d): return d.name
                case let .log(d): return d.name
                case let .runScene(d): return d.name
                case let .delay(d): return d.name
                case let .waitForState(d): return d.name
                case let .conditional(d): return d.name
                case let .repeatBlock(d): return d.name
                case let .repeatWhile(d): return d.name
                case let .group(d): return d.name
                case let .stop(d): return d.name
                case let .executeWorkflow(d): return d.name
                }
            },
            set: { newName in
                switch block.blockType {
                case .controlDevice(var d): d.name = newName; block.blockType = .controlDevice(d)
                case .webhook(var d): d.name = newName; block.blockType = .webhook(d)
                case .log(var d): d.name = newName; block.blockType = .log(d)
                case .runScene(var d): d.name = newName; block.blockType = .runScene(d)
                case .delay(var d): d.name = newName; block.blockType = .delay(d)
                case .waitForState(var d): d.name = newName; block.blockType = .waitForState(d)
                case .conditional(var d): d.name = newName; block.blockType = .conditional(d)
                case .repeatBlock(var d): d.name = newName; block.blockType = .repeatBlock(d)
                case .repeatWhile(var d): d.name = newName; block.blockType = .repeatWhile(d)
                case .group(var d): d.name = newName; block.blockType = .group(d)
                case .stop(var d): d.name = newName; block.blockType = .stop(d)
                case .executeWorkflow(var d): d.name = newName; block.blockType = .executeWorkflow(d)
                }
            }
        )
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.blockType {
        case .controlDevice:
            controlDeviceContent
        case .webhook:
            webhookContent
        case .log:
            logContent
        case .runScene:
            runSceneContent
        case .delay:
            delayContent
        case .waitForState:
            waitForStateContent
        case .conditional:
            conditionalContent
        case .repeatBlock:
            repeatContent
        case .repeatWhile:
            repeatWhileContent
        case .group:
            groupContent
        case .stop:
            stopContent
        case .executeWorkflow:
            executeWorkflowContent
        }
    }
}

// MARK: - Action Block Editors

extension BlockEditorRow {
    private var controlDeviceContent: some View {
        ControlDeviceEditor(block: $block, devices: devices)
    }

    private var webhookContent: some View {
        WebhookEditor(block: $block)
    }

    private var logContent: some View {
        LogEditor(block: $block)
    }

    private var runSceneContent: some View {
        RunSceneEditor(block: $block, scenes: scenes)
    }
}

// MARK: - Flow Control Block Editors

extension BlockEditorRow {
    private var delayContent: some View {
        DelayEditor(block: $block)
    }

    private var waitForStateContent: some View {
        WaitForStateEditor(block: $block, devices: devices)
    }

    private var conditionalContent: some View {
        ConditionalEditor(block: $block, devices: devices, scenes: scenes, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var repeatContent: some View {
        RepeatEditor(block: $block, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var repeatWhileContent: some View {
        RepeatWhileEditor(block: $block, devices: devices, scenes: scenes, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var groupContent: some View {
        GroupEditor(block: $block, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var stopContent: some View {
        StopEditor(block: $block)
    }

    private var executeWorkflowContent: some View {
        ExecuteWorkflowEditor(block: $block, workflows: workflows)
    }
}

// MARK: - Control Device Editor

private struct ControlDeviceEditor: View {
    @Binding var block: BlockDraft

    let devices: [DeviceModel]

    private var draft: Binding<ControlDeviceDraft> {
        Binding(
            get: {
                if case .controlDevice(let d) = block.blockType { return d }
                return ControlDeviceDraft()
            },
            set: { block.blockType = .controlDevice($0) }
        )
    }

    var body: some View {
        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: draft.deviceId,
            selectedServiceId: draft.serviceId,
            selectedCharacteristicType: draft.characteristicType
        )
        ValueEditor(
            value: draft.value,
            characteristicType: draft.wrappedValue.characteristicType,
            devices: devices,
            deviceId: draft.wrappedValue.deviceId
        )
    }
}

// MARK: - Webhook Editor

private struct WebhookEditor: View {
    @Binding var block: BlockDraft

    private var draft: Binding<WebhookDraft> {
        Binding(
            get: {
                if case .webhook(let d) = block.blockType { return d }
                return WebhookDraft()
            },
            set: { block.blockType = .webhook($0) }
        )
    }

    private var methodSupportsBody: Bool {
        let method = draft.wrappedValue.method.uppercased()
        return method != "GET" && method != "HEAD"
    }

    var body: some View {
        TextField("URL", text: draft.url)
            .keyboardType(.URL)
            .autocapitalization(.none)
            .disableAutocorrection(true)

        Picker("Method", selection: draft.method) {
            Text("GET").tag("GET")
            Text("POST").tag("POST")
            Text("PUT").tag("PUT")
            Text("DELETE").tag("DELETE")
        }
        .onChange(of: draft.wrappedValue.method) { newMethod in
            let upper = newMethod.uppercased()
            if upper == "GET" || upper == "HEAD" {
                draft.wrappedValue.body = ""
            }
        }

        if methodSupportsBody {
            TextField("Body (optional)", text: draft.body)
        }
    }
}

// MARK: - Log Editor

private struct LogEditor: View {
    @Binding var block: BlockDraft

    private var draft: Binding<LogDraft> {
        Binding(
            get: {
                if case .log(let d) = block.blockType { return d }
                return LogDraft()
            },
            set: { block.blockType = .log($0) }
        )
    }

    var body: some View {
        TextField("Log message", text: draft.message)
    }
}

// MARK: - Run Scene Editor

private struct RunSceneEditor: View {
    @Binding var block: BlockDraft
    let scenes: [SceneModel]

    private var draft: Binding<RunSceneDraft> {
        Binding(
            get: {
                if case .runScene(let d) = block.blockType { return d }
                return RunSceneDraft()
            },
            set: { block.blockType = .runScene($0) }
        )
    }

    var body: some View {
        Picker("Scene", selection: draft.sceneId) {
            Text("Select scene…").tag("")
            ForEach(scenes) { scene in
                Text(scene.name).tag(scene.id)
            }
        }
    }
}

// MARK: - Delay Editor

private struct DelayEditor: View {
    @Binding var block: BlockDraft

    private var draft: Binding<DelayDraft> {
        Binding(
            get: {
                if case .delay(let d) = block.blockType { return d }
                return DelayDraft()
            },
            set: { block.blockType = .delay($0) }
        )
    }

    var body: some View {
        HStack {
            Text("Seconds")
            Spacer()
            TextField("1.0", value: draft.seconds, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Wait For State Editor

private struct WaitForStateEditor: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]

    private var draft: Binding<WaitForStateDraft> {
        Binding(
            get: {
                if case .waitForState(let d) = block.blockType { return d }
                return WaitForStateDraft()
            },
            set: { block.blockType = .waitForState($0) }
        )
    }

    var body: some View {
        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: draft.deviceId,
            selectedServiceId: draft.serviceId,
            selectedCharacteristicType: draft.characteristicType
        )

        ComparisonValueRow(
            comparisonType: draft.comparisonType,
            value: draft.comparisonValue,
            characteristicType: draft.wrappedValue.characteristicType,
            devices: devices,
            deviceId: draft.wrappedValue.deviceId
        )

        HStack {
            Text("Timeout (seconds)")
            Spacer()
            TextField("30", value: draft.timeoutSeconds, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Conditional Editor

private struct ConditionalEditor: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let allowNesting: Bool
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?

    private var draft: Binding<ConditionalDraft> {
        Binding(
            get: {
                if case .conditional(let d) = block.blockType { return d }
                return ConditionalDraft()
            },
            set: { block.blockType = .conditional($0) }
        )
    }

    var body: some View {
        ConditionGroupEditor(
            group: draft.conditionRoot,
            devices: devices,
            scenes: scenes,
            depth: 0
        )

        if allowNesting {
            nestedBlockButtons
        } else {
            Text("Then: \(draft.wrappedValue.thenBlocks.count) blocks, Else: \(draft.wrappedValue.elseBlocks.count) blocks")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        }
    }

    private var nestedBlockButtons: some View {
        VStack(spacing: 0) {
            Button {
                onEditNestedBlocks?("then", draft.wrappedValue.thenBlocks)
            } label: {
                HStack {
                    Label("Edit Then Blocks", systemImage: "arrow.right.circle")
                        .foregroundColor(Theme.Tint.main)
                    Spacer()
                    Text("\(draft.wrappedValue.thenBlocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Theme.Text.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)

            Divider()

            Button {
                onEditNestedBlocks?("else", draft.wrappedValue.elseBlocks)
            } label: {
                HStack {
                    Label("Edit Else Blocks", systemImage: "arrow.uturn.right.circle")
                        .foregroundColor(Theme.Tint.secondary)
                    Spacer()
                    Text("\(draft.wrappedValue.elseBlocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(Theme.Text.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Repeat Editor

private struct RepeatEditor: View {
    @Binding var block: BlockDraft
    let allowNesting: Bool
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?

    private var draft: Binding<RepeatDraft> {
        Binding(
            get: {
                if case .repeatBlock(let d) = block.blockType { return d }
                return RepeatDraft()
            },
            set: { block.blockType = .repeatBlock($0) }
        )
    }

    var body: some View {
        Stepper("Count: \(draft.wrappedValue.count)", value: draft.count, in: 1...1000)

        HStack {
            Text("Delay Between (s)")
            Spacer()
            TextField("0", value: draft.delayBetweenSeconds, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }

        if allowNesting {
            Button {
                onEditNestedBlocks?("blocks", draft.wrappedValue.blocks)
            } label: {
                HStack {
                    Label("Edit Blocks", systemImage: "square.stack.3d.up")
                    Spacer()
                    Text("\(draft.wrappedValue.blocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                }
            }
        } else {
            Text("\(draft.wrappedValue.blocks.count) nested blocks")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        }
    }
}

// MARK: - Repeat While Editor

private struct RepeatWhileEditor: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let allowNesting: Bool
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?

    private var draft: Binding<RepeatWhileDraft> {
        Binding(
            get: {
                if case .repeatWhile(let d) = block.blockType { return d }
                return RepeatWhileDraft()
            },
            set: { block.blockType = .repeatWhile($0) }
        )
    }

    var body: some View {
        ConditionGroupEditor(
            group: draft.conditionRoot,
            devices: devices,
            scenes: scenes,
            depth: 0
        )

        Stepper("Max Iterations: \(draft.wrappedValue.maxIterations)", value: draft.maxIterations, in: 1...10000)

        HStack {
            Text("Delay Between (s)")
            Spacer()
            TextField("0", value: draft.delayBetweenSeconds, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }

        if allowNesting {
            Button {
                onEditNestedBlocks?("blocks", draft.wrappedValue.blocks)
            } label: {
                HStack {
                    Label("Edit Blocks", systemImage: "square.stack.3d.up")
                    Spacer()
                    Text("\(draft.wrappedValue.blocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                }
            }
        } else {
            Text("\(draft.wrappedValue.blocks.count) nested blocks")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        }
    }
}

// MARK: - Group Editor

private struct GroupEditor: View {
    @Binding var block: BlockDraft
    let allowNesting: Bool
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?

    private var draft: Binding<GroupDraft> {
        Binding(
            get: {
                if case .group(let d) = block.blockType { return d }
                return GroupDraft()
            },
            set: { block.blockType = .group($0) }
        )
    }

    var body: some View {
        TextField("Group Label (optional)", text: draft.label)

        if allowNesting {
            Button {
                onEditNestedBlocks?("blocks", draft.wrappedValue.blocks)
            } label: {
                HStack {
                    Label("Edit Blocks", systemImage: "square.stack.3d.up")
                    Spacer()
                    Text("\(draft.wrappedValue.blocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                }
            }
        } else {
            Text("\(draft.wrappedValue.blocks.count) nested blocks")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        }
    }
}

// MARK: - Stop Editor

private struct StopEditor: View {
    @Binding var block: BlockDraft

    private var draft: Binding<StopDraft> {
        Binding(
            get: {
                if case .stop(let d) = block.blockType { return d }
                return StopDraft()
            },
            set: { block.blockType = .stop($0) }
        )
    }

    var body: some View {
        Picker("Outcome", selection: draft.outcome) {
            Text("Success").tag(StopOutcome.success)
            Text("Error").tag(StopOutcome.error)
            Text("Cancelled").tag(StopOutcome.cancelled)
        }

        TextField("Message (optional)", text: draft.message)
    }
}

// MARK: - Execute Workflow Editor

private struct ExecuteWorkflowEditor: View {
    @Binding var block: BlockDraft
    let workflows: [Workflow]

    private var draft: Binding<ExecuteWorkflowDraft> {
        Binding(
            get: {
                if case .executeWorkflow(let d) = block.blockType { return d }
                return ExecuteWorkflowDraft()
            },
            set: { block.blockType = .executeWorkflow($0) }
        )
    }

    /// Workflows that have a .workflow trigger and can be called.
    private var callableWorkflows: [Workflow] {
        workflows.filter { workflow in
            workflow.triggers.contains { trigger in
                if case .workflow = trigger { return true }
                return false
            }
        }
    }

    var body: some View {
        Picker("Workflow", selection: draft.targetWorkflowId) {
            Text("Select workflow…").tag(nil as UUID?)
            ForEach(callableWorkflows, id: \.id) { workflow in
                Text(workflow.name).tag(workflow.id as UUID?)
            }
        }

        Picker("Mode", selection: draft.executionMode) {
            Text("Inline").tag(ExecutionMode.inline)
            Text("Parallel").tag(ExecutionMode.parallel)
            Text("Delegate").tag(ExecutionMode.delegate)
        }
        .pickerStyle(.segmented)

        Group {
            switch draft.wrappedValue.executionMode {
            case .inline:
                Text("Wait for the target workflow to complete before continuing.")
            case .parallel:
                Text("Launch the target workflow and continue immediately.")
            case .delegate:
                Text("Launch the target workflow and stop this workflow.")
            }
        }
        .font(.footnote)
        .foregroundColor(Theme.Text.secondary)
    }
}
