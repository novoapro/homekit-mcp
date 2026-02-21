import SwiftUI

struct DeviceCharacteristicPicker: View {
    let devices: [DeviceModel]
    @Binding var selectedDeviceId: String
    @Binding var selectedServiceId: String?
    @Binding var selectedCharacteristicType: String

    var body: some View {
        HStack(spacing: 8) {
            // Device menu
            Menu {
                Button("None") {
                    selectedDeviceId = ""
                    selectedCharacteristicType = ""
                    selectedServiceId = nil
                }
                ForEach(devicesByRoom, id: \.roomName) { group in
                    Section(group.roomName) {
                        ForEach(group.devices) { device in
                            Button {
                                if selectedDeviceId != device.id {
                                    selectedDeviceId = device.id
                                    selectedCharacteristicType = ""
                                    selectedServiceId = nil
                                }
                            } label: {
                                Label {
                                    if device.isReachable {
                                        Text(device.name)
                                    } else {
                                        Text("\(device.name) (Offline)")
                                    }
                                } icon: {
                                    Image(systemName: categoryIcon(for: device.categoryType))
                                }
                            }
                        }
                    }
                }
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

            // Characteristic menu — only when a device is selected
            if let device = selectedDevice {
                let characteristics = flattenedCharacteristics(for: device)
                Menu {
                    Button("None") {
                        selectedCharacteristicType = ""
                        selectedServiceId = nil
                    }
                    ForEach(characteristics, id: \.characteristic.type) { item in
                        Button {
                            selectedCharacteristicType = item.characteristic.type
                            selectedServiceId = item.serviceId
                        } label: {
                            Text("\(item.serviceName) › \(CharacteristicTypes.displayName(for: item.characteristic.type))")
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

    private struct CharacteristicItem {
        let serviceId: String
        let serviceName: String
        let characteristic: CharacteristicModel
    }

    private func flattenedCharacteristics(for device: DeviceModel) -> [CharacteristicItem] {
        device.services.flatMap { service in
            service.characteristics.map { characteristic in
                CharacteristicItem(
                    serviceId: service.id,
                    serviceName: service.displayName,
                    characteristic: characteristic
                )
            }
        }
    }
}
