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
        // Operator picker + NOT toggle — always visible at every depth
        HStack(spacing: 12) {
            Picker("Match", selection: $group.logicOperator) {
                Text("All conditions (AND)").tag(LogicOperator.and)
                Text("Any condition (OR)").tag(LogicOperator.or)
            }

            Spacer()

            Toggle(isOn: $group.isNegated) {
                Text("NOT")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .toggleStyle(.button)
            .tint(group.isNegated ? .red : nil)
        }

        // Children with operator separators
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

            // Operator separator between children
            if index < group.children.count - 1 {
                Text(group.logicOperator.symbol)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }

        // Add buttons
        addConditionMenu
    }

    // MARK: - Add Condition Menu

    private var addConditionMenu: some View {
        HStack(spacing: 12) {
            Menu {
                Button {
                    group.children.append(.leaf(.empty()))
                } label: {
                    Label("Device State", systemImage: "shield.fill")
                }
                Button {
                    group.children.append(.leaf(.emptySunEvent()))
                } label: {
                    Label("Sunrise/Sunset", systemImage: "sunrise.fill")
                }
                Button {
                    group.children.append(.leaf(.emptySceneActive()))
                } label: {
                    Label("Scene Active", systemImage: "play.rectangle.fill")
                }
            } label: {
                Label("Add Condition", systemImage: "plus.circle")
            }

            Button {
                group.children.append(.group(.withOneLeaf(operator: group.logicOperator == .and ? .or : .and)))
            } label: {
                Label("Add Group", systemImage: "folder.badge.plus")
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
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
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

// MARK: - Condition Leaf Row (single condition with NOT toggle)

private struct ConditionLeafRow: View {
    @Binding var condition: ConditionDraft
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    let onDelete: () -> Void
    @State private var isEditingName: Bool = false

    var body: some View {
        DisclosureGroup {
            conditionContent
        } label: {
            conditionLabel
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
        case .sunEvent:
            sunEventConditionContent
        case .sceneActive:
            sceneActiveConditionContent
        }
    }

    private var sunEventConditionContent: some View {
        VStack(spacing: 12) {
            Picker("Event", selection: $condition.sunEventType) {
                ForEach(SunEventType.allCases) { eventType in
                    Text(eventType.displayName).tag(eventType)
                }
            }
            .pickerStyle(.segmented)

            Picker("Timing", selection: $condition.sunEventComparison) {
                ForEach(SunEventComparison.allCases) { comp in
                    Text(comp.displayName).tag(comp)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var sceneActiveConditionContent: some View {
        VStack(spacing: 12) {
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

    private var conditionLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: condition.conditionDraftType.icon)
                .font(.caption)
                .foregroundColor(conditionIconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(condition.conditionDraftType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isEditingName {
                    TextField("Name", text: $condition.name)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { isEditingName = false }
                } else {
                    Text(condition.name.isEmpty ? condition.autoName(devices: devices, scenes: scenes) : condition.name)
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
                .accessibilityLabel("Remove Condition")
            }
        }
    }

    private var conditionIconColor: Color {
        switch condition.conditionDraftType {
        case .deviceState: return .indigo
        case .sunEvent: return .orange
        case .sceneActive: return .green
        }
    }
}
