import SwiftUI

struct BlockEditorRow: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let allowNesting: Bool
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var isReferencedByCondition: Bool = false
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?
    let onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var moveTargets: [MoveTarget] = []
    var onMoveToContainer: ((UUID, String) -> Void)?
    var isReorderMode: Bool = false
    var automations: [Automation] = []
    /// 1-based execution order index for this block. Shown as a badge.
    var ordinal: Int?
    /// Full ordinals map for passing to condition editors.
    var blockOrdinals: [UUID: Int] = [:]
    var controllerStates: [StateVariable] = []
    @State private var isExpanded: Bool = true
    @State private var isEditingName: Bool = false
    @State private var showReferencedAlert: Bool = false

    var body: some View {
        if isReorderMode {
            blockLabel
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                Group {
                    blockContent
                }
                .listRowBackground(
                    HStack(spacing: 0) {
                        (block.blockType.isFlowControl ? Theme.Tint.secondary : Theme.Tint.main)
                            .frame(width: Theme.Block.accentBarWidth)
                        Theme.contentBackground
                    }
                )
            } label: {
                blockLabel
                    .contentShape(Rectangle())
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
                    Button(role: .destructive) {
                        if isReferencedByCondition {
                            showReferencedAlert = true
                        } else {
                            onDelete()
                        }
                    } label: {
                        Label(isReferencedByCondition ? "Cannot Remove (Referenced)" : "Remove Block", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var blockLabel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if isReorderMode {
                    Image(systemName: "line.3.horizontal")
                        .font(.body)
                        .foregroundColor(Theme.Text.tertiary)
                        .frame(width: 28, height: 28)
                }

                if let ordinal {
                    Text("#\(ordinal)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(block.blockType.isFlowControl ? Theme.Tint.secondary : Theme.Tint.main)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Image(systemName: block.blockType.icon)
                    .font(.footnote)
                    .foregroundColor(block.hasOrphanedReference(devices: devices, scenes: scenes) ? .orange : (block.blockType.isFlowControl ? Theme.Tint.secondary : Theme.Tint.main))
                if block.hasOrphanedReference(devices: devices, scenes: scenes) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
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
                        Text(block.displayName(devices: devices, scenes: scenes, controllerStates: controllerStates))
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
                                if isReferencedByCondition {
                                    showReferencedAlert = true
                                } else {
                                    onDelete()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .foregroundColor(isReferencedByCondition ? Theme.Text.tertiary : .red)
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
        .alert("Cannot Delete Block", isPresented: $showReferencedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This block is referenced by a Block Result condition. Remove the condition first before deleting this block.")
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
                case let .stateVariable(d): return d.name
                case let .delay(d): return d.name
                case let .waitForState(d): return d.name
                case let .conditional(d): return d.name
                case let .repeatBlock(d): return d.name
                case let .repeatWhile(d): return d.name
                case let .group(d): return d.name
                case let .stop(d): return d.name
                case let .executeAutomation(d): return d.name
                }
            },
            set: { newName in
                switch block.blockType {
                case .controlDevice(var d): d.name = newName; block.blockType = .controlDevice(d)
                case .webhook(var d): d.name = newName; block.blockType = .webhook(d)
                case .log(var d): d.name = newName; block.blockType = .log(d)
                case .runScene(var d): d.name = newName; block.blockType = .runScene(d)
                case .stateVariable(var d): d.name = newName; block.blockType = .stateVariable(d)
                case .delay(var d): d.name = newName; block.blockType = .delay(d)
                case .waitForState(var d): d.name = newName; block.blockType = .waitForState(d)
                case .conditional(var d): d.name = newName; block.blockType = .conditional(d)
                case .repeatBlock(var d): d.name = newName; block.blockType = .repeatBlock(d)
                case .repeatWhile(var d): d.name = newName; block.blockType = .repeatWhile(d)
                case .group(var d): d.name = newName; block.blockType = .group(d)
                case .stop(var d): d.name = newName; block.blockType = .stop(d)
                case .executeAutomation(var d): d.name = newName; block.blockType = .executeAutomation(d)
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
        case .stateVariable:
            stateVariableContent
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
        case .executeAutomation:
            executeAutomationContent
        }
    }
}

// MARK: - Action Block Editors

extension BlockEditorRow {
    private var controlDeviceContent: some View {
        ControlDeviceEditor(block: $block, devices: devices, controllerStates: controllerStates)
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

    @ViewBuilder
    private var stateVariableContent: some View {
        StateVariableEditor(block: $block, devices: devices, controllerStates: controllerStates)
    }
}

// MARK: - Flow Control Block Editors

extension BlockEditorRow {
    private var delayContent: some View {
        DelayEditor(block: $block, controllerStates: controllerStates)
    }

    private var waitForStateContent: some View {
        WaitForStateEditor(block: $block, devices: devices, scenes: scenes, continueOnError: continueOnError, allBlocks: allBlocks, currentBlockId: block.id, blockOrdinals: blockOrdinals, controllerStates: controllerStates)
    }

    private var conditionalContent: some View {
        ConditionalEditor(block: $block, devices: devices, scenes: scenes, allowNesting: allowNesting, continueOnError: continueOnError, allBlocks: allBlocks, currentBlockId: block.id, blockOrdinals: blockOrdinals, controllerStates: controllerStates, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var repeatContent: some View {
        RepeatEditor(block: $block, devices: devices, scenes: scenes, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var repeatWhileContent: some View {
        RepeatWhileEditor(block: $block, devices: devices, scenes: scenes, allowNesting: allowNesting, continueOnError: continueOnError, allBlocks: allBlocks, currentBlockId: block.id, blockOrdinals: blockOrdinals, controllerStates: controllerStates, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var groupContent: some View {
        GroupEditor(block: $block, devices: devices, scenes: scenes, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var stopContent: some View {
        StopEditor(block: $block)
    }

    private var executeAutomationContent: some View {
        ExecuteAutomationEditor(block: $block, automations: automations)
    }
}

// MARK: - Control Device Editor

private struct ControlDeviceEditor: View {
    @Binding var block: BlockDraft

    let devices: [DeviceModel]
    var controllerStates: [StateVariable] = []

    private var draft: Binding<ControlDeviceDraft> {
        Binding(
            get: {
                if case .controlDevice(let d) = block.blockType { return d }
                return ControlDeviceDraft()
            },
            set: { block.blockType = .controlDevice($0) }
        )
    }

    private var valueSourceBinding: Binding<ControlDeviceDraft.ValueSource> {
        Binding(
            get: { draft.wrappedValue.valueSource },
            set: { draft.wrappedValue.valueSource = $0 }
        )
    }

    /// Maps a characteristic format to the compatible StateVariableType.
    private var compatibleStateType: StateVariableType? {
        guard let format = draft.wrappedValue.characteristicFormat else { return nil }
        switch format {
        case "bool": return .boolean
        case "uint8", "uint16", "uint32", "uint64", "int", "float": return .number
        case "string": return .string
        default: return nil
        }
    }

    /// Global values filtered to those compatible with the selected characteristic's type.
    private var compatibleGlobalValues: [StateVariable] {
        guard let requiredType = compatibleStateType else { return controllerStates }
        return controllerStates.filter { $0.type == requiredType }
    }

    var body: some View {
        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: draft.deviceId,
            selectedServiceId: draft.serviceId,
            selectedCharacteristicType: draft.characteristicId,
            requiredPermission: "write",
            onCharacteristicSelected: { char in
                draft.wrappedValue.characteristicFormat = char?.format
                draft.wrappedValue.characteristicMinValue = char?.minValue
                draft.wrappedValue.characteristicMaxValue = char?.maxValue
                draft.wrappedValue.characteristicStepValue = char?.stepValue
                draft.wrappedValue.characteristicValidValues = char?.validValues
            }
        )

        // Value source toggle: Local vs Global
        if !compatibleGlobalValues.isEmpty {
            Picker("Value Source", selection: valueSourceBinding) {
                Text("Local").tag(ControlDeviceDraft.ValueSource.local)
                Text("Global").tag(ControlDeviceDraft.ValueSource.global)
            }
            .pickerStyle(.segmented)
        }

        if draft.wrappedValue.valueSource == .global && !compatibleGlobalValues.isEmpty {
            // Global Value picker (filtered by compatible type)
            Picker("Global Value", selection: Binding(
                get: { draft.wrappedValue.valueRefName },
                set: { newValue in
                    draft.wrappedValue.valueRefName = newValue
                    draft.wrappedValue.valueRefDisplayName = compatibleGlobalValues.first(where: { $0.name == newValue })?.label ?? ""
                }
            )) {
                Text("-- Select --").tag("")
                ForEach(compatibleGlobalValues) { state in
                    Label(state.label, systemImage: state.type.icon)
                        .tag(state.name)
                }
            }

            // Default fallback value (required)
            Section {
                ValueEditor(
                    value: draft.value,
                    characteristicType: draft.wrappedValue.characteristicId,
                    devices: devices,
                    deviceId: draft.wrappedValue.deviceId,
                    fallbackFormat: draft.wrappedValue.characteristicFormat,
                    fallbackMinValue: draft.wrappedValue.characteristicMinValue,
                    fallbackMaxValue: draft.wrappedValue.characteristicMaxValue,
                    fallbackStepValue: draft.wrappedValue.characteristicStepValue,
                    fallbackValidValues: draft.wrappedValue.characteristicValidValues
                )
            } header: {
                Text("Default value (used if global value is removed)")
            }
        } else {
            // Local value editor (existing behavior)
            ValueEditor(
                value: draft.value,
                characteristicType: draft.wrappedValue.characteristicId,
                devices: devices,
                deviceId: draft.wrappedValue.deviceId,
                fallbackFormat: draft.wrappedValue.characteristicFormat,
                fallbackMinValue: draft.wrappedValue.characteristicMinValue,
                fallbackMaxValue: draft.wrappedValue.characteristicMaxValue,
                fallbackStepValue: draft.wrappedValue.characteristicStepValue,
                fallbackValidValues: draft.wrappedValue.characteristicValidValues
            )
        }
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

// MARK: - State Variable Editor

private struct StateVariableEditor: View {
    @Binding var block: BlockDraft
    var devices: [DeviceModel] = []
    var controllerStates: [StateVariable] = []

    private var draft: Binding<StateVariableDraft> {
        Binding(
            get: {
                if case .stateVariable(let d) = block.blockType { return d }
                return StateVariableDraft()
            },
            set: { block.blockType = .stateVariable($0) }
        )
    }

    /// The selected state's type — looks up from loaded states, or infers from the current operation.
    private var selectedStateType: StateVariableType? {
        // First try to find in loaded states
        if let found = controllerStates.first(where: { $0.name == draft.wrappedValue.variableName })?.type {
            return found
        }
        // Infer from the current operation type if states aren't loaded
        let opType = draft.wrappedValue.operationType
        if !opType.applicableTypes.isEmpty {
            return opType.applicableTypes.first
        }
        return nil
    }

    /// Operations filtered to the selected state's type.
    private var availableOperations: [StateVariableOperationType] {
        guard let type = selectedStateType else {
            // Type unknown — show all non-create ops so the user can still see/edit
            return StateVariableOperationType.allCases.filter { $0 != .create }
        }
        return StateVariableOperationType.allCases.filter { op in
            op != .create && (op.applicableTypes.isEmpty || op.applicableTypes.contains(type))
        }
    }

    /// Whether the user is in "create new" mode.
    private var isCreateMode: Bool {
        draft.wrappedValue.operationType == .create
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Step 1: Pick existing state or create new
            Picker("State", selection: Binding(
                get: { isCreateMode ? "__create__" : draft.wrappedValue.variableName },
                set: { newValue in
                    if newValue == "__create__" {
                        draft.wrappedValue.operationType = .create
                        draft.wrappedValue.variableName = ""
                    } else {
                        if isCreateMode {
                            draft.wrappedValue.operationType = .set
                        }
                        draft.wrappedValue.variableName = newValue
                        draft.wrappedValue.variableDisplayName = controllerStates.first(where: { $0.name == newValue })?.label ?? ""
                        // If the operation doesn't apply to this type, reset to .set
                        if let type = controllerStates.first(where: { $0.name == newValue })?.type {
                            let applicable = draft.wrappedValue.operationType.applicableTypes
                            if !applicable.isEmpty && !applicable.contains(type) {
                                draft.wrappedValue.operationType = .set
                            }
                        }
                    }
                }
            )) {
                ForEach(controllerStates) { state in
                    Label(state.label, systemImage: state.type.icon).tag(state.name)
                }
                // Show the current variable name even if not in loaded states (e.g., states not loaded yet)
                if !isCreateMode,
                   !draft.wrappedValue.variableName.isEmpty,
                   !controllerStates.contains(where: { $0.name == draft.wrappedValue.variableName }) {
                    Text(draft.wrappedValue.variableName).tag(draft.wrappedValue.variableName)
                }
                Divider()
                Text("Create New...").tag("__create__")
            }

            if isCreateMode {
                // Create new state
                TextField("Name (no spaces)", text: draft.variableName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Picker("Type", selection: draft.variableType) {
                    ForEach(StateVariableType.allCases) { t in
                        Label(t.displayName, systemImage: t.icon).tag(t)
                    }
                }

                // Type-specific initial value
                initialValueInput
            } else if !draft.wrappedValue.variableName.isEmpty {
                // Step 2: Pick operation (filtered by type)
                Picker("Operation", selection: draft.operationType) {
                    ForEach(availableOperations) { op in
                        Text(op.displayName).tag(op)
                    }
                }

                // Step 3: Type-specific value/amount inputs
                if draft.wrappedValue.operationType.requiresValue {
                    typedValueInput
                }

                if draft.wrappedValue.operationType.requiresAmount {
                    HStack {
                        Text("Amount")
                            .foregroundColor(Theme.Text.secondary)
                        Spacer()
                        TextField("Amount", value: draft.amountValue, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                if draft.wrappedValue.operationType.requiresOtherRef {
                    Picker("Other State", selection: draft.otherVariableName) {
                        Text("Select...").tag("")
                        ForEach(controllerStates.filter { $0.name != draft.wrappedValue.variableName && (selectedStateType == nil || $0.type == selectedStateType) }) { state in
                            Label(state.label, systemImage: state.type.icon).tag(state.name)
                        }
                    }
                }

                if draft.wrappedValue.operationType.requiresTimeAmount {
                    HStack {
                        Text("Amount")
                            .foregroundColor(Theme.Text.secondary)
                        Spacer()
                        TextField("Amount", value: draft.timeAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Unit", selection: Binding(
                        get: { draft.wrappedValue.timeUnit },
                        set: { draft.wrappedValue.timeUnit = $0 }
                    )) {
                        ForEach(StateVariableOperation.TimeUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                }

                if draft.wrappedValue.operationType.requiresDevice {
                    DeviceCharacteristicPicker(
                        devices: devices,
                        selectedDeviceId: draft.sourceDeviceId,
                        selectedServiceId: Binding(
                            get: { draft.wrappedValue.sourceServiceId },
                            set: { draft.wrappedValue.sourceServiceId = $0 }
                        ),
                        selectedCharacteristicType: draft.sourceCharacteristicId,
                        requiredPermission: "read",
                        allowedFormats: formatsForStateType(selectedStateType)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var initialValueInput: some View {
        switch draft.wrappedValue.variableType {
        case .number:
            TextField("Number", text: draft.value)
                .keyboardType(.decimalPad)
        case .string:
            TextField("Text value", text: draft.value)
        case .boolean:
            Toggle("Initial Value", isOn: Binding(
                get: { draft.wrappedValue.value.lowercased() == "true" },
                set: { draft.wrappedValue.value = $0 ? "true" : "false" }
            ))
        case .datetime:
            DatePicker("Initial Value", selection: Binding(
                get: {
                    if let str = draft.wrappedValue.value as String?,
                       let date = StateVariable.parseDate(str) { return date }
                    return Date()
                },
                set: { draft.wrappedValue.value = StateVariable.formatDateISO($0) }
            ))
        }
    }

    @ViewBuilder
    private var typedValueInput: some View {
        switch selectedStateType {
        case .number:
            TextField("Number", text: draft.value)
                .keyboardType(.decimalPad)
        case .boolean:
            Toggle("Value", isOn: Binding(
                get: { draft.wrappedValue.value.lowercased() == "true" },
                set: { draft.wrappedValue.value = $0 ? "true" : "false" }
            ))
        case .datetime:
            DatePicker("Value", selection: Binding(
                get: {
                    if let date = StateVariable.parseDate(draft.wrappedValue.value) { return date }
                    return Date()
                },
                set: { draft.wrappedValue.value = StateVariable.formatDateISO($0) }
            ))
        case .string, .none:
            TextField("Value", text: draft.value)
        }
    }

    /// Maps a StateVariableType to the set of characteristic formats that are compatible with it.
    private func formatsForStateType(_ type: StateVariableType?) -> Set<String>? {
        switch type {
        case .boolean: return ["bool"]
        case .number: return ["uint8", "uint16", "uint32", "uint64", "int", "float"]
        case .string: return ["string"]
        case .datetime: return nil // datetime is not used with characteristics
        case .none: return nil
        }
    }
}

// MARK: - Delay Editor

private struct DelayEditor: View {
    @Binding var block: BlockDraft
    var controllerStates: [StateVariable] = []

    private var draft: Binding<DelayDraft> {
        Binding(
            get: {
                if case .delay(let d) = block.blockType { return d }
                return DelayDraft()
            },
            set: { block.blockType = .delay($0) }
        )
    }

    private var numberStates: [StateVariable] {
        controllerStates.filter { $0.type == .number }
    }

    var body: some View {
        if !numberStates.isEmpty {
            Picker("Duration Source", selection: Binding(
                get: { draft.wrappedValue.valueSource },
                set: { draft.wrappedValue.valueSource = $0 }
            )) {
                Text("Local").tag(ControlDeviceDraft.ValueSource.local)
                Text("Global").tag(ControlDeviceDraft.ValueSource.global)
            }
            .pickerStyle(.segmented)
        }

        if draft.wrappedValue.valueSource == .global && !numberStates.isEmpty {
            Picker("Global Value", selection: Binding(
                get: { draft.wrappedValue.secondsRefName },
                set: { draft.wrappedValue.secondsRefName = $0 }
            )) {
                Text("-- Select --").tag("")
                ForEach(numberStates) { state in
                    Label(state.label, systemImage: state.type.icon).tag(state.name)
                }
            }
            Section {
                HStack {
                    Text("Default (seconds)")
                    Spacer()
                    TextField("1.0", value: draft.seconds, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Fallback if global value is removed")
            }
        } else {
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
}

// MARK: - Wait For State Editor

private struct WaitForStateEditor: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    var blockOrdinals: [UUID: Int] = [:]
    var controllerStates: [StateVariable] = []

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
        ConditionGroupEditor(
            group: draft.conditionRoot,
            devices: devices,
            scenes: scenes,
            depth: 0,
            continueOnError: continueOnError,
            allBlocks: allBlocks,
            currentBlockId: currentBlockId,
            allowBlockResult: false,
            blockOrdinals: blockOrdinals,
            controllerStates: controllerStates
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
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    var blockOrdinals: [UUID: Int] = [:]
    var controllerStates: [StateVariable] = []
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
            depth: 0,
            continueOnError: continueOnError,
            allBlocks: allBlocks,
            currentBlockId: currentBlockId,
            allowBlockResult: true,
            blockOrdinals: blockOrdinals
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
        let thenHasOrphans = draft.wrappedValue.thenBlocks.contains { $0.hasOrphanedReference(devices: devices, scenes: scenes) }
        let elseHasOrphans = draft.wrappedValue.elseBlocks.contains { $0.hasOrphanedReference(devices: devices, scenes: scenes) }
        return VStack(spacing: 0) {
            Button {
                onEditNestedBlocks?("then", draft.wrappedValue.thenBlocks)
            } label: {
                HStack {
                    Label("Edit Then Blocks", systemImage: "arrow.right.circle")
                        .foregroundColor(Theme.Tint.main)
                    if thenHasOrphans {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
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
                    if elseHasOrphans {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
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
    var devices: [DeviceModel] = []
    var scenes: [SceneModel] = []
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
            let hasOrphans = draft.wrappedValue.blocks.contains { $0.hasOrphanedReference(devices: devices, scenes: scenes) }
            Button {
                onEditNestedBlocks?("blocks", draft.wrappedValue.blocks)
            } label: {
                HStack {
                    Label("Edit Blocks", systemImage: "square.stack.3d.up")
                    if hasOrphans {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
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
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    var blockOrdinals: [UUID: Int] = [:]
    var controllerStates: [StateVariable] = []
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
            depth: 0,
            continueOnError: continueOnError,
            allBlocks: allBlocks,
            currentBlockId: currentBlockId,
            allowBlockResult: false,
            blockOrdinals: blockOrdinals,
            controllerStates: controllerStates
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
            let hasOrphans = draft.wrappedValue.blocks.contains { $0.hasOrphanedReference(devices: devices, scenes: scenes) }
            Button {
                onEditNestedBlocks?("blocks", draft.wrappedValue.blocks)
            } label: {
                HStack {
                    Label("Edit Blocks", systemImage: "square.stack.3d.up")
                    if hasOrphans {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
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
    var devices: [DeviceModel] = []
    var scenes: [SceneModel] = []
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
            let hasOrphans = draft.wrappedValue.blocks.contains { $0.hasOrphanedReference(devices: devices, scenes: scenes) }
            Button {
                onEditNestedBlocks?("blocks", draft.wrappedValue.blocks)
            } label: {
                HStack {
                    Label("Edit Blocks", systemImage: "square.stack.3d.up")
                    if hasOrphans {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
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

// MARK: - Execute Automation Editor

private struct ExecuteAutomationEditor: View {
    @Binding var block: BlockDraft
    let automations: [Automation]

    private var draft: Binding<ExecuteAutomationDraft> {
        Binding(
            get: {
                if case .executeAutomation(let d) = block.blockType { return d }
                return ExecuteAutomationDraft()
            },
            set: { block.blockType = .executeAutomation($0) }
        )
    }

    /// Automations that have a .automation trigger and can be called.
    private var callableAutomations: [Automation] {
        automations.filter { automation in
            automation.triggers.contains { trigger in
                if case .automation = trigger { return true }
                return false
            }
        }
    }

    var body: some View {
        Picker("Automation", selection: draft.targetAutomationId) {
            Text("Select automation…").tag(nil as UUID?)
            ForEach(callableAutomations, id: \.id) { automation in
                Text(automation.name).tag(automation.id as UUID?)
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
                Text("Wait for the target automation to complete before continuing.")
            case .parallel:
                Text("Launch the target automation and continue immediately.")
            case .delegate:
                Text("Launch the target automation and stop this automation.")
            }
        }
        .font(.footnote)
        .foregroundColor(Theme.Text.secondary)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var block = PreviewData.sampleBlockDrafts[0]

        var body: some View {
            NavigationStack {
                Form {
                    BlockEditorRow(
                        block: $block,
                        devices: PreviewData.sampleDevices,
                        scenes: PreviewData.sampleScenes,
                        allowNesting: true,
                        onEditNestedBlocks: nil,
                        onDelete: { }
                    )
                }
                .navigationTitle("Block")
            }
        }
    }
    return PreviewWrapper()
}
