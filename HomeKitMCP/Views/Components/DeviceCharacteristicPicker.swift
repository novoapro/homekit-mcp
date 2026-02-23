import SwiftUI

struct DeviceCharacteristicPicker: View {
    let devices: [DeviceModel]
    @Binding var selectedDeviceId: String
    @Binding var selectedServiceId: String?
    @Binding var selectedCharacteristicType: String
    var onCharacteristicSelected: ((CharacteristicModel?) -> Void)? = nil

    @State private var showDevicePicker = false

    var body: some View {
        HStack(spacing: 8) {
            // Device button — opens searchable sheet
            Button {
                showDevicePicker = true
            } label: {
                HStack(spacing: 4) {
                    if let device = selectedDevice {
                        Image(systemName: categoryIcon(for: device.categoryType))
                            .font(.caption2)
                        Text(device.name)
                            .lineLimit(1)
                    } else {
                        Text("Device…")
                            .foregroundColor(Theme.Text.secondary)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(Theme.Text.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDevicePicker) {
                DevicePickerSheet(
                    devices: devices,
                    selectedDeviceId: $selectedDeviceId,
                    selectedServiceId: $selectedServiceId,
                    selectedCharacteristicType: $selectedCharacteristicType,
                    categoryIcon: categoryIcon
                )
            }

            // Characteristic menu — only when a device is selected
            if let device = selectedDevice {
                let characteristics = flattenedCharacteristics(for: device)
                let showServicePrefix = device.services.count > 1
                Menu {
                    Button("None") {
                        selectedCharacteristicType = ""
                        selectedServiceId = nil
                        onCharacteristicSelected?(nil)
                    }
                    ForEach(characteristics) { item in
                        Button {
                            selectedCharacteristicType = item.characteristic.type
                            selectedServiceId = item.serviceId
                            onCharacteristicSelected?(item.characteristic)
                        } label: {
                            if showServicePrefix {
                                Text("\(item.serviceName) › \(CharacteristicTypes.displayName(for: item.characteristic.type))")
                            } else {
                                Text(CharacteristicTypes.displayName(for: item.characteristic.type))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if !selectedCharacteristicType.isEmpty {
                            Text(CharacteristicTypes.displayName(for: selectedCharacteristicType))
                                .lineLimit(1)
                        } else {
                            Text("Characteristic…")
                                .foregroundColor(Theme.Text.secondary)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(Theme.Text.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Selected Device

    private var selectedDevice: DeviceModel? {
        devices.first(where: { $0.id == selectedDeviceId })
    }

    // MARK: - Device Grouping

    private struct DeviceGroup {
        let roomName: String
        let devices: [DeviceModel]
    }

    private var devicesByRoom: [DeviceGroup] {
        let grouped = Dictionary(grouping: devices) { $0.roomName ?? "No Room" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { DeviceGroup(roomName: $0.key, devices: $0.value.sorted { $0.name < $1.name }) }
    }

    // MARK: - Category Icons

    private func categoryIcon(for categoryType: String) -> String {
        switch categoryType.lowercased() {
        case "lightbulb":
            return "lightbulb.fill"
        case "switch", "outlet":
            return "switch.2"
        case "thermostat":
            return "thermometer"
        case "sensor":
            return "sensor.fill"
        case "fan":
            return "fan.fill"
        case "lock", "lock-mechanism":
            return "lock.fill"
        case "garage-door-opener":
            return "door.garage.closed"
        case "door":
            return "door.left.hand.closed"
        case "window":
            return "window.vertical.closed"
        case "window-covering":
            return "blinds.vertical.closed"
        case "security-system":
            return "shield.fill"
        case "camera", "ip-camera", "video-doorbell":
            return "camera.fill"
        case "air-purifier":
            return "aqi.medium"
        case "humidifier-dehumidifier":
            return "humidity.fill"
        case "sprinkler":
            return "sprinkler.and.droplets.fill"
        case "programmable-switch":
            return "button.programmable"
        default:
            return "house.fill"
        }
    }

    // MARK: - Characteristic Helpers

    private struct CharacteristicItem: Identifiable {
        let serviceId: String
        let serviceName: String
        let characteristic: CharacteristicModel

        /// Composite identity: service + characteristic type, so the same characteristic type
        /// on different services (e.g. Power on Switch 1 vs Power on Switch 2) stays unique.
        var id: String { "\(serviceId):\(characteristic.type)" }
    }

    private func flattenedCharacteristics(for device: DeviceModel) -> [CharacteristicItem] {
        device.services.flatMap { service in
            service.characteristics.compactMap { characteristic in
                guard characteristic.isUserFacing else { return nil }
                return CharacteristicItem(
                    serviceId: service.id,
                    serviceName: service.effectiveDisplayName,
                    characteristic: characteristic
                )
            }
        }
    }
}

// MARK: - Searchable Device Picker Sheet

private struct DevicePickerSheet: View {
    let devices: [DeviceModel]
    @Binding var selectedDeviceId: String
    @Binding var selectedServiceId: String?
    @Binding var selectedCharacteristicType: String
    let categoryIcon: (String) -> String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private struct DeviceGroup: Identifiable {
        let roomName: String
        var id: String { roomName }
        let devices: [DeviceModel]
    }

    private var filteredDevicesByRoom: [DeviceGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [DeviceModel]
        if query.isEmpty {
            filtered = devices
        } else {
            filtered = devices.filter {
                $0.name.lowercased().contains(query) ||
                ($0.roomName ?? "").lowercased().contains(query)
            }
        }
        let grouped = Dictionary(grouping: filtered) { $0.roomName ?? "No Room" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { DeviceGroup(roomName: $0.key, devices: $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedDeviceId = ""
                    selectedCharacteristicType = ""
                    selectedServiceId = nil
                    dismiss()
                } label: {
                    Label("None", systemImage: "minus.circle")
                        .foregroundColor(Theme.Text.secondary)
                }

                ForEach(filteredDevicesByRoom) { group in
                    Section(group.roomName) {
                        ForEach(group.devices) { device in
                            Button {
                                if selectedDeviceId != device.id {
                                    selectedDeviceId = device.id
                                    selectedCharacteristicType = ""
                                    selectedServiceId = nil
                                }
                                dismiss()
                            } label: {
                                HStack {
                                    Label {
                                        Text(device.name)
                                            .foregroundColor(Theme.Text.primary)
                                    } icon: {
                                        Image(systemName: categoryIcon(device.categoryType))
                                    }
                                    Spacer()
                                    if device.id == selectedDeviceId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                            .font(.footnote)
                                    }
                                    if !device.isReachable {
                                        Text("Offline")
                                            .font(.footnote)
                                            .foregroundColor(Theme.Text.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search devices")
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
