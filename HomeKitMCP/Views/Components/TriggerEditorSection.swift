import SwiftUI

struct TriggerEditorSection: View {
    @Binding var triggers: [TriggerDraft]
    let devices: [DeviceModel]

    var body: some View {
        Section {
            ForEach(Array(triggers.indices), id: \.self) { index in
                triggerRow(index: index)
            }
            .onDelete { triggers.remove(atOffsets: $0) }

            Button {
                triggers.append(.empty())
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

    private func triggerRow(index: Int) -> some View {
        DisclosureGroup {
            TextField("Trigger Name (optional)", text: $triggers[index].name)

            DeviceCharacteristicPicker(
                devices: devices,
                selectedDeviceId: $triggers[index].deviceId,
                selectedServiceId: $triggers[index].serviceId,
                selectedCharacteristicType: $triggers[index].characteristicType
            )

            Picker("Condition", selection: $triggers[index].conditionType) {
                ForEach(TriggerConditionType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }

            if triggers[index].conditionType.requiresValue {
                if triggers[index].conditionType == .transitioned {
                    HStack {
                        Text("From (optional)")
                        Spacer()
                        TextField("Any", text: $triggers[index].conditionFromValue)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("To")
                        Spacer()
                        TextField("Value", text: $triggers[index].conditionValue)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    ValueEditor(
                        value: $triggers[index].conditionValue,
                        characteristicType: triggers[index].characteristicType,
                        devices: devices,
                        deviceId: triggers[index].deviceId
                    )
                }
            }

            Button(role: .destructive) {
                triggers.remove(at: index)
            } label: {
                Label("Remove Trigger", systemImage: "trash")
                    .font(.subheadline)
            }
        } label: {
            triggerLabel(triggers[index])
        }
    }

    private func triggerLabel(_ trigger: TriggerDraft) -> some View {
        HStack {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundColor(Theme.Tint.main)
            if !trigger.name.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trigger.name)
                        .lineLimit(1)
                    if !trigger.deviceId.isEmpty {
                        let deviceName = devices.first(where: { $0.id == trigger.deviceId })?.name ?? "Unknown"
                        let charName = trigger.characteristicType.isEmpty ? "..." : CharacteristicTypes.displayName(for: trigger.characteristicType)
                        Text("\(deviceName) › \(charName)")
                            .font(.caption)
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(1)
                    }
                }
            } else if trigger.deviceId.isEmpty {
                Text("New Trigger")
                    .foregroundColor(Theme.Text.secondary)
            } else {
                let deviceName = devices.first(where: { $0.id == trigger.deviceId })?.name ?? "Unknown"
                let charName = trigger.characteristicType.isEmpty ? "..." : CharacteristicTypes.displayName(for: trigger.characteristicType)
                Text("\(deviceName) › \(charName)")
                    .lineLimit(1)
            }
        }
    }
}
