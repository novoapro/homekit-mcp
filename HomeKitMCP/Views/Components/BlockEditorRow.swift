import SwiftUI

struct BlockEditorRow: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
    let allowNesting: Bool
    let onEditNestedBlocks: ((String, [BlockDraft]) -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        DisclosureGroup {
            blockContent

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Remove Block", systemImage: "trash")
                        .font(.subheadline)
                }
            }
        } label: {
            blockLabel
        }
    }

    private var blockLabel: some View {
        HStack {
            Image(systemName: block.blockType.icon)
                .font(.caption)
                .foregroundColor(block.blockType.isFlowControl ? .indigo : Theme.Tint.main)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.blockType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let name = blockName, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                }
            }
        }
    }

    private var blockName: String? {
        switch block.blockType {
        case .controlDevice(let d): return d.name.isEmpty ? nil : d.name
        case .webhook(let d): return d.name.isEmpty ? nil : d.name
        case .log(let d): return d.name.isEmpty ? nil : d.name
        case .delay(let d): return d.name.isEmpty ? nil : d.name
        case .waitForState(let d): return d.name.isEmpty ? nil : d.name
        case .conditional(let d): return d.name.isEmpty ? nil : d.name
        case .repeatBlock(let d): return d.name.isEmpty ? nil : d.name
        case .repeatWhile(let d): return d.name.isEmpty ? nil : d.name
        case .group(let d): return d.name.isEmpty ? nil : d.name
        }
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
        ConditionalEditor(block: $block, devices: devices, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var repeatContent: some View {
        RepeatEditor(block: $block, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var repeatWhileContent: some View {
        RepeatWhileEditor(block: $block, devices: devices, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
    }

    private var groupContent: some View {
        GroupEditor(block: $block, allowNesting: allowNesting, onEditNestedBlocks: onEditNestedBlocks)
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
        TextField("Block Name (optional)", text: draft.name)

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

    var body: some View {
        TextField("Block Name (optional)", text: draft.name)

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

        TextField("Body (optional)", text: draft.body)
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
        TextField("Block Name (optional)", text: draft.name)
        TextField("Log message", text: draft.message)
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
        TextField("Block Name (optional)", text: draft.name)

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
        TextField("Block Name (optional)", text: draft.name)

        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: draft.deviceId,
            selectedServiceId: draft.serviceId,
            selectedCharacteristicType: draft.characteristicType
        )

        Picker("Comparison", selection: draft.comparisonType) {
            ForEach(ComparisonType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        ValueEditor(
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
        TextField("Block Name (optional)", text: draft.name)

        Text("Condition")
            .font(.caption)
            .foregroundColor(Theme.Text.secondary)

        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: draft.conditionDeviceId,
            selectedServiceId: draft.conditionServiceId,
            selectedCharacteristicType: draft.conditionCharacteristicType
        )

        Picker("Comparison", selection: draft.comparisonType) {
            ForEach(ComparisonType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        ValueEditor(
            value: draft.comparisonValue,
            characteristicType: draft.wrappedValue.conditionCharacteristicType,
            devices: devices,
            deviceId: draft.wrappedValue.conditionDeviceId
        )

        if allowNesting {
            nestedBlockButtons
        } else {
            Text("Then: \(draft.wrappedValue.thenBlocks.count) blocks, Else: \(draft.wrappedValue.elseBlocks.count) blocks")
                .font(.caption)
                .foregroundColor(Theme.Text.secondary)
        }
    }

    private var nestedBlockButtons: some View {
        VStack(spacing: 8) {
            Button {
                onEditNestedBlocks?("then", draft.wrappedValue.thenBlocks)
            } label: {
                HStack {
                    Label("Edit Then Blocks", systemImage: "arrow.right.circle")
                    Spacer()
                    Text("\(draft.wrappedValue.thenBlocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                }
            }

            Button {
                onEditNestedBlocks?("else", draft.wrappedValue.elseBlocks)
            } label: {
                HStack {
                    Label("Edit Else Blocks", systemImage: "arrow.uturn.right.circle")
                    Spacer()
                    Text("\(draft.wrappedValue.elseBlocks.count)")
                        .foregroundColor(Theme.Text.secondary)
                }
            }
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
        TextField("Block Name (optional)", text: draft.name)

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
                .font(.caption)
                .foregroundColor(Theme.Text.secondary)
        }
    }
}

// MARK: - Repeat While Editor

private struct RepeatWhileEditor: View {
    @Binding var block: BlockDraft
    let devices: [DeviceModel]
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
        TextField("Block Name (optional)", text: draft.name)

        Text("While Condition")
            .font(.caption)
            .foregroundColor(Theme.Text.secondary)

        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: draft.conditionDeviceId,
            selectedServiceId: draft.conditionServiceId,
            selectedCharacteristicType: draft.conditionCharacteristicType
        )

        Picker("Comparison", selection: draft.comparisonType) {
            ForEach(ComparisonType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        ValueEditor(
            value: draft.comparisonValue,
            characteristicType: draft.wrappedValue.conditionCharacteristicType,
            devices: devices,
            deviceId: draft.wrappedValue.conditionDeviceId
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
                .font(.caption)
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
        TextField("Block Name (optional)", text: draft.name)
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
                .font(.caption)
                .foregroundColor(Theme.Text.secondary)
        }
    }
}
