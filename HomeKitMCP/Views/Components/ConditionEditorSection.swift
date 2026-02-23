import SwiftUI

// MARK: - Guard Conditions Section (used in WorkflowEditorView)

struct ConditionEditorSection: View {
    @Binding var conditionRoot: ConditionGroupDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []

    var body: some View {
        Section {
            ConditionGroupEditor(
                group: $conditionRoot,
                devices: devices,
                scenes: scenes,
                depth: 0
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
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    group.isNegated.toggle()
                }
            } label: {
                Image(systemName: group.isNegated ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundColor(group.isNegated ? .red : Theme.Text.tertiary)
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
                            depth: depth + 1
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
                Button {
                    group.children.append(.leaf(.emptySceneActive()))
                } label: {
                    Label("Scene Active", systemImage: "play.rectangle.fill")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Condition")
                }
                .foregroundColor(Theme.Tint.main)
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
                .foregroundColor(Theme.Tint.main)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Sub-Group Label

    private func subGroupLabel(at index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundColor(Theme.Tint.secondary)

            if case .group(let subGroup) = group.children[index] {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if subGroup.isNegated {
                            Text("NOT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                        Text("\(subGroup.logicOperator.displayName) Group")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("\(subGroup.leafCount) conditions")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                group.children.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
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
    let onDelete: () -> Void
    @State private var showingEditSheet = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: condition.conditionDraftType.icon)
                .font(.caption2)
                .foregroundColor(conditionIconColor)
                .frame(width: 20)

            Text(condition.name.isEmpty ? condition.autoName(devices: devices, scenes: scenes) : condition.name)
                .font(.caption)
                .foregroundColor(Theme.Text.primary)
                .lineLimit(1)

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove Condition")

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(Theme.Text.tertiary)
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
                scenes: scenes
            )
        }
    }

    private var conditionIconColor: Color {
        switch condition.conditionDraftType {
        case .deviceState: return .indigo
        case .timeCondition: return .orange
        case .sceneActive: return .green
        }
    }
}

// MARK: - Condition Leaf Edit Sheet

private struct ConditionLeafEditSheet: View {
    @Binding var condition: ConditionDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workflowViewModel: WorkflowViewModel

    @State private var testResult: ConditionResult?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    conditionContent
                }

                Section("Name") {
                    TextField("Custom name (optional)", text: $condition.name)
                }

                testSection
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
                        .foregroundColor(result.passed ? .green : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.passed ? "Passed" : "Failed")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(result.passed ? .green : .red)
                        Text(result.conditionDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                selectedCharacteristicType: $condition.characteristicType
            )

            ComparisonValueRow(
                comparisonType: $condition.comparisonType,
                value: $condition.comparisonValue,
                characteristicType: condition.characteristicType,
                devices: devices,
                deviceId: condition.deviceId
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
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .sceneActive:
            Picker("Scene", selection: $condition.sceneId) {
                Text("Select scene\u{2026}").tag("")
                ForEach(scenes) { scene in
                    Text(scene.name).tag(scene.id)
                }
            }

            Picker("Check", selection: $condition.sceneIsActive) {
                Text("Is Active").tag(true)
                Text("Is Not Active").tag(false)
            }
            .pickerStyle(.segmented)
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
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
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
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
