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
                triggerRow(trigger: $trigger)
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

    private func triggerRow(trigger: Binding<TriggerDraft>) -> some View {
        DisclosureGroup {
            triggerContent(trigger: trigger)

            Button(role: .destructive) {
                triggers.removeAll(where: { $0.id == trigger.wrappedValue.id })
            } label: {
                Label("Remove Trigger", systemImage: "trash")
                    .font(.subheadline)
            }
        } label: {
            triggerLabel(trigger.wrappedValue)
        }
    }

    @ViewBuilder
    private func triggerContent(trigger: Binding<TriggerDraft>) -> some View {
        TextField("Custom Name (optional)", text: trigger.name)

        switch trigger.wrappedValue.triggerType {
        case .deviceStateChange:
            deviceStateTriggerContent(trigger: trigger)
        case .schedule:
            scheduleTriggerContent(trigger: trigger)
        case .webhook:
            webhookTriggerContent(trigger: trigger)
        }
    }

    // MARK: - Device State Change Content

    @ViewBuilder
    private func deviceStateTriggerContent(trigger: Binding<TriggerDraft>) -> some View {
        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: trigger.deviceId,
            selectedServiceId: trigger.serviceId,
            selectedCharacteristicType: trigger.characteristicType
        )

        Picker("Condition", selection: trigger.conditionType) {
            ForEach(TriggerConditionType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        if trigger.wrappedValue.conditionType.requiresValue {
            if trigger.wrappedValue.conditionType == .transitioned {
                HStack {
                    Text("From (optional)")
                    Spacer()
                    TextField("Any", text: trigger.conditionFromValue)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("To")
                    Spacer()
                    TextField("Value", text: trigger.conditionValue)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                ValueEditor(
                    value: trigger.conditionValue,
                    characteristicType: trigger.wrappedValue.characteristicType,
                    devices: devices,
                    deviceId: trigger.wrappedValue.deviceId
                )
            }
        }
    }

    // MARK: - Schedule Trigger Content

    @ViewBuilder
    private func scheduleTriggerContent(trigger: Binding<TriggerDraft>) -> some View {
        Picker("Schedule Type", selection: trigger.scheduleType) {
            ForEach(ScheduleDraftType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }

        switch trigger.wrappedValue.scheduleType {
        case .once:
            DatePicker("Date & Time", selection: trigger.scheduleDate)
        case .daily:
            timePicker(trigger: trigger)
        case .weekly:
            timePicker(trigger: trigger)
            weekdayPicker(trigger: trigger)
        case .interval:
            HStack {
                Text("Every")
                Spacer()
                TextField("1", value: trigger.scheduleIntervalAmount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: trigger.scheduleIntervalUnit) {
                    ForEach(ScheduleIntervalUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
        }
    }

    private func timePicker(trigger: Binding<TriggerDraft>) -> some View {
        HStack {
            Text("Time")
            Spacer()
            Picker("", selection: trigger.scheduleHour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 60)
            Text(":")
            Picker("", selection: trigger.scheduleMinute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 60)
        }
    }

    private func weekdayPicker(trigger: Binding<TriggerDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days")
                .font(.subheadline)
            HStack(spacing: 4) {
                ForEach(ScheduleWeekday.allCases, id: \.rawValue) { day in
                    let isSelected = trigger.wrappedValue.scheduleDays.contains(day)
                    Button {
                        if isSelected {
                            trigger.wrappedValue.scheduleDays.remove(day)
                        } else {
                            trigger.wrappedValue.scheduleDays.insert(day)
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
    private func webhookTriggerContent(trigger: Binding<TriggerDraft>) -> some View {
        LabeledContent("Token") {
            Text(String(trigger.wrappedValue.webhookToken.prefix(8)) + "...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.Text.secondary)
        }

        LabeledContent("URL") {
            Text("http://\(webhookHost):\(webhookPort)/workflows/webhook/\(String(trigger.wrappedValue.webhookToken.prefix(8)))...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
        }

        Button {
            UIPasteboard.general.string = "http://\(webhookHost):\(webhookPort)/workflows/webhook/\(trigger.wrappedValue.webhookToken)"
            onCopy?()
        } label: {
            Label("Copy Webhook URL", systemImage: "doc.on.doc")
        }
    }

    // MARK: - Trigger Label

    private func triggerLabel(_ trigger: TriggerDraft) -> some View {
        HStack {
            Image(systemName: trigger.triggerType.icon)
                .font(.caption)
                .foregroundColor(trigger.triggerType == .deviceStateChange ? Theme.Tint.main : .indigo)
            Text(trigger.name.isEmpty ? trigger.autoName(devices: devices) : trigger.name)
                .lineLimit(1)
        }
    }
}
