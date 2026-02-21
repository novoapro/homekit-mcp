import SwiftUI

struct TriggerEditorSection: View {
    @Binding var triggers: [TriggerDraft]
    let devices: [DeviceModel]
    var onCopy: (() -> Void)? = nil
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    /// The host that the MCP server is actually reachable on.
    /// Shows the LAN IP when bound to all interfaces so the copied URL works from remote devices.
    private var webhookHost: String {
        let bind = settingsViewModel.storage.mcpServerBindAddress
        return bind == "0.0.0.0" ? settingsViewModel.localIPAddress : bind
    }

    private var webhookPort: Int { settingsViewModel.storage.mcpServerPort }

    var body: some View {
        Section {
            ForEach($triggers) { $trigger in
                TriggerRow(trigger: $trigger, devices: devices, webhookHost: webhookHost, webhookPort: webhookPort, onCopy: onCopy, onDelete: {
                    triggers.removeAll(where: { $0.id == trigger.id })
                })
            }
            .onDelete { triggers.remove(atOffsets: $0) }

            Menu {
                Button { triggers.append(.empty()) } label: {
                    Label("Device State Change", systemImage: "bolt.fill")
                }
                Button { triggers.append(.emptySchedule()) } label: {
                    Label("Schedule", systemImage: "clock.fill")
                }
                Button { triggers.append(.emptyWebhook()) } label: {
                    Label("Webhook", systemImage: "arrow.down.circle.fill")
                }
                Button { triggers.append(.emptyWorkflow()) } label: {
                    Label("Workflow", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
            } label: {
                Label("Add Trigger", systemImage: "plus.circle")
            }
        } header: {
            Text("Triggers (\(triggers.count))")
        } footer: {
            Text("Any trigger firing will start the workflow.")
        }
        .listRowBackground(Theme.contentBackground)
    }
}

// MARK: - Trigger Row

private struct TriggerRow: View {
    @Binding var trigger: TriggerDraft
    let devices: [DeviceModel]
    let webhookHost: String
    let webhookPort: Int
    var onCopy: (() -> Void)?
    let onDelete: () -> Void
    @State private var isEditingName: Bool = false

    var body: some View {
        DisclosureGroup {
            triggerContent

            HStack {
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove Trigger")
            }
        } label: {
            triggerLabel
        }
    }

    // MARK: - Label

    private var triggerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: trigger.triggerType.icon)
                .font(.caption)
                .foregroundColor(trigger.triggerType == .deviceStateChange ? Theme.Tint.main : .indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(trigger.triggerType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isEditingName {
                    TextField("Name", text: $trigger.name)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { isEditingName = false }
                } else {
                    Text(trigger.name.isEmpty ? trigger.autoName(devices: devices) : trigger.name)
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                isEditingName.toggle()
            } label: {
                Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var triggerContent: some View {
        switch trigger.triggerType {
        case .deviceStateChange:
            deviceStateTriggerContent
        case .schedule:
            scheduleTriggerContent
        case .webhook:
            webhookTriggerContent
        case .workflow:
            workflowTriggerContent
        }
    }

    // MARK: - Device State Change Content

    @ViewBuilder
    private var deviceStateTriggerContent: some View {
        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: $trigger.deviceId,
            selectedServiceId: $trigger.serviceId,
            selectedCharacteristicType: $trigger.characteristicType
        )

        Picker("Condition", selection: $trigger.conditionType) {
            ForEach(TriggerConditionType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        if trigger.conditionType.requiresValue {
            if trigger.conditionType == .transitioned {
                HStack {
                    Text("From (optional)")
                    Spacer()
                    TextField("Any", text: $trigger.conditionFromValue)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("To")
                    Spacer()
                    TextField("Value", text: $trigger.conditionValue)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                ValueEditor(
                    value: $trigger.conditionValue,
                    characteristicType: trigger.characteristicType,
                    devices: devices,
                    deviceId: trigger.deviceId
                )
            }
        }
    }

    // MARK: - Schedule Trigger Content

    @ViewBuilder
    private var scheduleTriggerContent: some View {
        Picker("Schedule Type", selection: $trigger.scheduleType) {
            ForEach(ScheduleDraftType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        switch trigger.scheduleType {
        case .once:
            DatePicker("Date & Time", selection: $trigger.scheduleDate)
        case .daily:
            timePicker12h
        case .weekly:
            timePicker12h
            weekdayPicker
        case .interval:
            HStack {
                Text("Every")
                Spacer()
                TextField("1", value: $trigger.scheduleIntervalAmount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $trigger.scheduleIntervalUnit) {
                    ForEach(ScheduleIntervalUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
        }
    }

    // MARK: - 12-Hour Time Picker

    /// Binding converting 0-23 scheduleHour to 1-12 display.
    private var hour12Binding: Binding<Int> {
        Binding(
            get: {
                let h = trigger.scheduleHour % 12
                return h == 0 ? 12 : h
            },
            set: { newHour12 in
                let isPM = trigger.scheduleHour >= 12
                trigger.scheduleHour = (newHour12 % 12) + (isPM ? 12 : 0)
            }
        )
    }

    /// Binding converting scheduleHour to AM/PM toggle.
    private var isPMBinding: Binding<Bool> {
        Binding(
            get: { trigger.scheduleHour >= 12 },
            set: { newIsPM in
                let hour12 = trigger.scheduleHour % 12
                trigger.scheduleHour = hour12 + (newIsPM ? 12 : 0)
            }
        )
    }

    private var timePicker12h: some View {
        HStack {
            Text("Time")
            Spacer()
            Picker("", selection: hour12Binding) {
                ForEach(1...12, id: \.self) { h in
                    Text("\(h)").tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 52)
            Text(":")
            Picker("", selection: $trigger.scheduleMinute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 52)
            Picker("", selection: isPMBinding) {
                Text("AM").tag(false)
                Text("PM").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days")
                .font(.subheadline)
            HStack(spacing: 4) {
                ForEach(ScheduleWeekday.allCases, id: \.rawValue) { day in
                    let isSelected = trigger.scheduleDays.contains(day)
                    Button {
                        if isSelected {
                            trigger.scheduleDays.remove(day)
                        } else {
                            trigger.scheduleDays.insert(day)
                        }
                    } label: {
                        Text(day.displayName)
                            .font(.caption)
                            .fontWeight(isSelected ? .bold : .regular)
                            .frame(minWidth: 32)
                            .padding(.vertical, 6)
                            .background(isSelected ? Theme.Tint.main : Color(.systemGray5))
                            .foregroundColor(isSelected ? .white : Theme.Text.primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Webhook Trigger Content

    @ViewBuilder
    private var webhookTriggerContent: some View {
        LabeledContent("Token") {
            Text(String(trigger.webhookToken.prefix(8)) + "...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.Text.secondary)
        }

        LabeledContent("URL") {
            Text("http://\(webhookHost):\(webhookPort)/workflows/webhook/\(String(trigger.webhookToken.prefix(8)))...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }

        Button {
            UIPasteboard.general.string = "http://\(webhookHost):\(webhookPort)/workflows/webhook/\(trigger.webhookToken)"
            onCopy?()
        } label: {
            Label("Copy Webhook URL", systemImage: "doc.on.doc")
        }
    }

    // MARK: - Workflow Trigger Content

    @ViewBuilder
    private var workflowTriggerContent: some View {
        Text("This workflow can be launched from an Execute Workflow block in another workflow.")
            .font(.caption)
            .foregroundColor(Theme.Text.secondary)
    }
}
