import SwiftUI

struct TriggerEditorSection: View {
    @Binding var triggers: [TriggerDraft]
    let devices: [DeviceModel]
    var onCopy: (() -> Void)? = nil

    var body: some View {
        Section {
            ForEach($triggers) { $trigger in
                TriggerRow(trigger: $trigger, devices: devices, onCopy: onCopy, onDelete: {
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
                Button { triggers.append(.emptySunEvent()) } label: {
                    Label("Sunrise/Sunset", systemImage: "sunrise.fill")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("Add Trigger")
                }
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
    var onCopy: (() -> Void)?
    let onDelete: () -> Void
    @State private var isEditingName: Bool = false

    var body: some View {
        DisclosureGroup {
            triggerContent
        } label: {
            triggerLabel
        }
    }

    // MARK: - Label

    private var triggerHasOrphanedRef: Bool {
        trigger.triggerType == .deviceStateChange && !trigger.deviceId.isEmpty && !devices.contains(where: { $0.id == trigger.deviceId })
    }

    private var triggerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: trigger.triggerType.icon)
                .font(.footnote)
                .foregroundColor(triggerHasOrphanedRef ? .orange : (trigger.triggerType == .deviceStateChange ? Theme.Tint.main : trigger.triggerType == .sunEvent ? .orange : .indigo))
            if triggerHasOrphanedRef {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(trigger.triggerType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isEditingName {
                    TextField("Name", text: $trigger.name)
                        .font(.footnote)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { isEditingName = false }
                } else {
                    Text(trigger.name.isEmpty ? trigger.autoName(devices: devices) : trigger.name)
                        .font(.footnote)
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
                .accessibilityLabel("Remove Trigger")
            }
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
        case .sunEvent:
            sunEventTriggerContent
        }

        Picker("If workflow is running?", selection: $trigger.retriggerPolicy) {
            ForEach(ConcurrentExecutionPolicy.allCases) { policy in
                VStack(alignment: .leading) {
                    Text(policy.displayName)
                    Text(policy.description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .tag(policy)
            }
        }
    }

    // MARK: - Device State Change Content

    @ViewBuilder
    private var deviceStateTriggerContent: some View {
        DeviceCharacteristicPicker(
            devices: devices,
            selectedDeviceId: $trigger.deviceId,
            selectedServiceId: $trigger.serviceId,
            selectedCharacteristicType: $trigger.characteristicId,
            requiredPermission: "notify",
            onCharacteristicSelected: { char in
                trigger.characteristicFormat = char?.format
                trigger.characteristicMinValue = char?.minValue
                trigger.characteristicMaxValue = char?.maxValue
                trigger.characteristicStepValue = char?.stepValue
                trigger.characteristicValidValues = char?.validValues
            }
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
                    Text("To (optional)")
                    Spacer()
                    TextField("Any", text: $trigger.conditionValue)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                ValueEditor(
                    value: $trigger.conditionValue,
                    characteristicType: trigger.characteristicId,
                    devices: devices,
                    deviceId: trigger.deviceId,
                    fallbackFormat: trigger.characteristicFormat,
                    fallbackMinValue: trigger.characteristicMinValue,
                    fallbackMaxValue: trigger.characteristicMaxValue,
                    fallbackStepValue: trigger.characteristicStepValue,
                    fallbackValidValues: trigger.characteristicValidValues
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
                            .font(.footnote)
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
            Text(trigger.webhookToken)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }

        Button {
            UIPasteboard.general.string = trigger.webhookToken
            onCopy?()
        } label: {
            Label("Copy Token", systemImage: "doc.on.doc")
        }
    }

    // MARK: - Workflow Trigger Content

    @ViewBuilder
    private var workflowTriggerContent: some View {
        Text("This workflow can be launched from an Execute Workflow block in another workflow.")
            .font(.footnote)
            .foregroundColor(Theme.Text.secondary)
    }

    // MARK: - Sun Event Trigger Content

    @ViewBuilder
    private var sunEventTriggerContent: some View {
        Picker("Event", selection: $trigger.sunEventType) {
            ForEach(SunEventType.allCases) { eventType in
                Text(eventType.displayName).tag(eventType)
            }
        }

        HStack {
            Text("Offset (minutes)")
            Spacer()
            TextField("0", value: $trigger.sunEventOffsetMinutes, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }

        Text("Negative = before, Positive = after. Set location in Settings.")
            .font(.footnote)
            .foregroundColor(Theme.Text.secondary)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var triggers = PreviewData.sampleTriggerDrafts

        var body: some View {
            NavigationStack {
                Form {
                    TriggerEditorSection(
                        triggers: $triggers,
                        devices: PreviewData.sampleDevices
                    )
                }
                .navigationTitle("Triggers")
            }
        }
    }
    return PreviewWrapper()
}
