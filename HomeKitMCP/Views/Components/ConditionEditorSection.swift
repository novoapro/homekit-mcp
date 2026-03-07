import SwiftUI

// MARK: - Guard Conditions Section (used in WorkflowEditorView)

struct ConditionEditorSection: View {
    @Binding var conditionRoot: ConditionGroupDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    /// When false (default), Block Result conditions are hidden from the add menu.
    /// Guard conditions (workflow-level) should pass false; block-level conditions pass true.
    var allowBlockResult: Bool = false
    /// 1-based execution order index for each block.
    var blockOrdinals: [UUID: Int] = [:]

    var body: some View {
        Section {
            ConditionGroupEditor(
                group: $conditionRoot,
                devices: devices,
                scenes: scenes,
                depth: 0,
                continueOnError: continueOnError,
                allBlocks: allBlocks,
                currentBlockId: currentBlockId,
                allowBlockResult: allowBlockResult,
                blockOrdinals: blockOrdinals
            )
        } header: {
            Text("Guard Conditions (\(conditionRoot.leafCount))")
        } footer: {
            if conditionRoot.children.isEmpty {
                Text("No conditions — workflow will always proceed.")
            } else {
                Text("Conditions combine with \(conditionRoot.logicOperator.displayName). Leave empty to always proceed.")
            }
        }
        .listRowBackground(Theme.contentBackground)
    }
}

// MARK: - Reusable Condition Group Editor

struct ConditionGroupEditor: View {
    @Binding var group: ConditionGroupDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let depth: Int
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    var allowBlockResult: Bool = false
    var blockOrdinals: [UUID: Int] = [:]

    var body: some View {
        // Compact operator row
        HStack(spacing: 8) {
            Picker("", selection: $group.logicOperator) {
                Text("AND").tag(LogicOperator.and)
                Text("OR").tag(LogicOperator.or)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)

            if group.isNegated {
                Text("NOT")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    group.isNegated.toggle()
                }
            } label: {
                Image(systemName: group.isNegated ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(group.isNegated ? .red : Theme.Text.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }

        // Children — compact rows, no operator separators
        ForEach(Array(group.children.enumerated()), id: \.element.id) { index, node in
            switch node {
            case .leaf:
                if let leafBinding = bindingForLeaf(at: index) {
                    ConditionLeafRow(
                        condition: leafBinding,
                        devices: devices,
                        scenes: scenes,
                        allBlocks: allBlocks,
                        currentBlockId: currentBlockId,
                        blockOrdinals: blockOrdinals,
                        onDelete: { group.children.remove(at: index) }
                    )
                }
            case .group:
                if let subBinding = bindingForGroup(at: index) {
                    DisclosureGroup {
                        ConditionGroupEditor(
                            group: subBinding,
                            devices: devices,
                            scenes: scenes,
                            depth: depth + 1,
                            continueOnError: continueOnError,
                            allBlocks: allBlocks,
                            currentBlockId: currentBlockId,
                            allowBlockResult: allowBlockResult,
                            blockOrdinals: blockOrdinals
                        )
                    } label: {
                        subGroupLabel(at: index)
                    }
                }
            }
        }

        // Add buttons
        addConditionMenu
    }

    // MARK: - Add Condition Menu

    private var addConditionMenu: some View {
        HStack(spacing: 20) {
            Menu {
                Button {
                    group.children.append(.leaf(.empty()))
                } label: {
                    Label("Device State", systemImage: "shield.fill")
                }
                Button {
                    group.children.append(.leaf(.emptyTimeCondition()))
                } label: {
                    Label("Time Condition", systemImage: "clock.fill")
                }
                if allowBlockResult && continueOnError {
                    Button {
                        group.children.append(.leaf(.emptyBlockResult()))
                    } label: {
                        Label("Block Result", systemImage: "checkmark.rectangle.stack")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Condition")
                }
                .foregroundStyle(Theme.Tint.main)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }

            Button {
                group.children.append(.group(.withOneLeaf(operator: group.logicOperator == .and ? .or : .and)))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Group")
                }
                .foregroundStyle(Theme.Tint.main)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Sub-Group Label

    private func subGroupLabel(at index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.footnote)
                .foregroundStyle(Theme.Tint.secondary)

            if case .group(let subGroup) = group.children[index] {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if subGroup.isNegated {
                            Text("NOT")
                                .font(.footnote)
                                .fontWeight(.bold)
                                .foregroundStyle(.red)
                        }
                        Text("\(subGroup.logicOperator.displayName) Group")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("\(subGroup.leafCount) conditions")
                        .font(.footnote)
                        .foregroundStyle(Theme.Text.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                group.children.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bindings

    private func bindingForLeaf(at index: Int) -> Binding<ConditionDraft>? {
        guard index < group.children.count, case .leaf = group.children[index] else { return nil }
        return Binding(
            get: {
                if case .leaf(let d) = group.children[index] { return d }
                return .empty()
            },
            set: { group.children[index] = .leaf($0) }
        )
    }

    private func bindingForGroup(at index: Int) -> Binding<ConditionGroupDraft>? {
        guard index < group.children.count, case .group = group.children[index] else { return nil }
        return Binding(
            get: {
                if case .group(let g) = group.children[index] { return g }
                return .empty()
            },
            set: { group.children[index] = .group($0) }
        )
    }
}

// MARK: - Compact Condition Leaf Row (summary line + edit sheet)

private struct ConditionLeafRow: View {
    @Binding var condition: ConditionDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    var blockOrdinals: [UUID: Int] = [:]
    let onDelete: () -> Void
    @State private var showingEditSheet = false

    private var isOrphanedBlockResult: Bool {
        guard condition.conditionDraftType == .blockResult,
              condition.blockResultScope == .specific,
              let blockId = condition.blockResultBlockId else { return false }
        return !allBlocks.contains(where: { $0.id == blockId })
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: condition.conditionDraftType.icon)
                .font(.caption2)
                .foregroundStyle(conditionIconColor)
                .frame(width: 20)

            Text(condition.name.isEmpty ? condition.autoName(devices: devices, scenes: scenes, allBlocks: allBlocks, blockOrdinals: blockOrdinals) : condition.name)
                .font(.footnote)
                .foregroundStyle(Theme.Text.primary)
                .lineLimit(1)

            if isOrphanedBlockResult {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove Condition")

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Theme.Text.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showingEditSheet = true
        }
        .sheet(isPresented: $showingEditSheet) {
            ConditionLeafEditSheet(
                condition: $condition,
                devices: devices,
                scenes: scenes,
                allBlocks: allBlocks,
                currentBlockId: currentBlockId,
                blockOrdinals: blockOrdinals
            )
        }
    }

    private var conditionIconColor: Color {
        switch condition.conditionDraftType {
        case .deviceState: return .indigo
        case .timeCondition: return .orange
        case .sceneActive: return .green
        case .blockResult: return .purple
        }
    }
}

// MARK: - Condition Leaf Edit Sheet

private struct ConditionLeafEditSheet: View {
    @Binding var condition: ConditionDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var allBlocks: [BlockDraft] = []
    var currentBlockId: UUID? = nil
    var blockOrdinals: [UUID: Int] = [:]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workflowViewModel: WorkflowViewModel

    @State private var testResult: ConditionResult?
    @State private var isTesting = false

    private var isBlockResult: Bool {
        condition.conditionDraftType == .blockResult
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    conditionContent
                }

                Section("Name") {
                    TextField("Custom name (optional)", text: $condition.name)
                }

                if !isBlockResult {
                    testSection
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .navigationTitle(condition.conditionDraftType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Test Section

    private var testSection: some View {
        Section {
            if let result = testResult {
                HStack(spacing: 10) {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.passed ? .green : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.passed ? "Passed" : "Failed")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(result.passed ? Color.green : Color.red)
                        Text(result.conditionDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                isTesting = true
                testResult = nil
                let c = condition.toCondition(devices: devices)
                Task {
                    let result = await workflowViewModel.evaluateCondition(c)
                    isTesting = false
                    testResult = result
                }
            } label: {
                if isTesting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Testing…")
                    }
                } else {
                    Label("Test Condition", systemImage: "play.circle.fill")
                }
            }
            .disabled(isTesting)
        } header: {
            Text("Test")
        } footer: {
            Text("Evaluates the condition right now against current device state and time.")
        }
    }

    @ViewBuilder
    private var conditionContent: some View {
        switch condition.conditionDraftType {
        case .deviceState:
            DeviceCharacteristicPicker(
                devices: devices,
                selectedDeviceId: $condition.deviceId,
                selectedServiceId: $condition.serviceId,
                selectedCharacteristicType: $condition.characteristicId,
                requiredPermission: "read",
                onCharacteristicSelected: { char in
                    condition.characteristicFormat = char?.format
                    condition.characteristicMinValue = char?.minValue
                    condition.characteristicMaxValue = char?.maxValue
                    condition.characteristicStepValue = char?.stepValue
                    condition.characteristicValidValues = char?.validValues
                }
            )

            if !condition.deviceId.isEmpty && !condition.characteristicId.isEmpty {
                CurrentValueBadge(
                    devices: devices,
                    deviceId: condition.deviceId,
                    characteristicId: condition.characteristicId
                )
            }

            ComparisonValueRow(
                comparisonType: $condition.comparisonType,
                value: $condition.comparisonValue,
                characteristicType: condition.characteristicId,
                devices: devices,
                deviceId: condition.deviceId,
                fallbackFormat: condition.characteristicFormat,
                fallbackMinValue: condition.characteristicMinValue,
                fallbackMaxValue: condition.characteristicMaxValue,
                fallbackStepValue: condition.characteristicStepValue,
                fallbackValidValues: condition.characteristicValidValues
            )
        case .timeCondition:
            Picker("Mode", selection: $condition.timeConditionMode) {
                ForEach(TimeConditionMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }

            if condition.timeConditionMode == .timeRange {
                timeRangePickers
            }

            if condition.timeConditionMode.requiresLocation {
                Text("Requires location configured in Settings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .sceneActive:
            // Legacy — no longer offered for new conditions
            Text("Scene Active (legacy)")
                .foregroundStyle(.secondary)

        case .blockResult:
            blockResultContent
        }
    }

    // MARK: - Block Result Content

    @ViewBuilder
    private var blockResultContent: some View {
        Picker("Scope", selection: $condition.blockResultScope) {
            ForEach(BlockResultScopeDraft.allCases) { scope in
                Text(scope.displayName).tag(scope)
            }
        }

        if condition.blockResultScope == .specific {
            let currentOrdinal = currentBlockId.flatMap { blockOrdinals[$0] } ?? Int.max
            let precedingBlocks = allBlocks.filter { block in
                guard block.id != currentBlockId else { return false }
                let ord = blockOrdinals[block.id] ?? Int.max
                return ord < currentOrdinal
            }

            Picker("Block", selection: $condition.blockResultBlockId) {
                Text("Select block\u{2026}").tag(UUID?.none)
                ForEach(precedingBlocks) { block in
                    let ord = blockOrdinals[block.id].map { "#\($0) " } ?? ""
                    Text("\(ord)\(block.displayName(devices: devices, scenes: scenes))").tag(UUID?.some(block.id))
                }
            }

            if let blockId = condition.blockResultBlockId,
               !allBlocks.contains(where: { $0.id == blockId }) {
                Label("Referenced block no longer exists", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let blockId = condition.blockResultBlockId,
                      let refOrd = blockOrdinals[blockId],
                      refOrd >= currentOrdinal {
                Label("Referenced block has not executed yet at this point", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        Picker("Expected Status", selection: $condition.blockResultExpectedStatus) {
            Text("Success").tag(ExecutionStatus.success)
            Text("Failure").tag(ExecutionStatus.failure)
            Text("Cancelled").tag(ExecutionStatus.cancelled)
        }

        if isBlockResult {
            let currentOrd = currentBlockId.flatMap { blockOrdinals[$0] }
            let precedingCount = currentOrd.map { ord in
                allBlocks.filter { blockOrdinals[$0.id] ?? Int.max < ord }.count
            } ?? 0
            switch condition.blockResultScope {
            case .specific:
                Text("Checks the result of a specific block that executed before this one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .all:
                Text("Checks that all \(precedingCount) preceding block(s) match the expected status.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .any:
                Text("Checks that at least one of \(precedingCount) preceding block(s) matches the expected status.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Time Range Pickers

    @ViewBuilder
    private var timeRangePickers: some View {
        let startHour = Binding(
            get: { condition.timeRangeStart.hour },
            set: { condition.timeRangeStart = TimeOfDay(hour: $0, minute: condition.timeRangeStart.minute) }
        )
        let startMinute = Binding(
            get: { condition.timeRangeStart.minute },
            set: { condition.timeRangeStart = TimeOfDay(hour: condition.timeRangeStart.hour, minute: $0) }
        )
        let endHour = Binding(
            get: { condition.timeRangeEnd.hour },
            set: { condition.timeRangeEnd = TimeOfDay(hour: $0, minute: condition.timeRangeEnd.minute) }
        )
        let endMinute = Binding(
            get: { condition.timeRangeEnd.minute },
            set: { condition.timeRangeEnd = TimeOfDay(hour: condition.timeRangeEnd.hour, minute: $0) }
        )

        VStack(alignment: .leading, spacing: 8) {
            Text("Start Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Picker("Hour", selection: startHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%d %@", h == 0 ? 12 : (h > 12 ? h - 12 : h), h < 12 ? "AM" : "PM")).tag(h)
                    }
                }
                .frame(maxWidth: .infinity)
                Text(":")
                Picker("Minute", selection: startMinute) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                        Text(String(format: ":%02d", m)).tag(m)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("End Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Picker("Hour", selection: endHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%d %@", h == 0 ? 12 : (h > 12 ? h - 12 : h), h < 12 ? "AM" : "PM")).tag(h)
                    }
                }
                .frame(maxWidth: .infinity)
                Text(":")
                Picker("Minute", selection: endMinute) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                        Text(String(format: ":%02d", m)).tag(m)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }

        if condition.timeRangeStart.totalMinutes > condition.timeRangeEnd.totalMinutes {
            Label("Spans midnight", systemImage: "moon.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var conditionRoot = PreviewData.sampleConditionGroupDraft

        var body: some View {
            NavigationStack {
                Form {
                    ConditionEditorSection(
                        conditionRoot: $conditionRoot,
                        devices: PreviewData.sampleDevices,
                        scenes: PreviewData.sampleScenes
                    )
                }
                .navigationTitle("Conditions")
            }
        }
    }
    return PreviewWrapper()
}
