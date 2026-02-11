import SwiftUI

struct DeviceRow: View {
    let device: DeviceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: deviceIcon)
                    .foregroundColor(.accentColor)
                Text(device.name)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(device.isReachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            ForEach(device.services) { service in
                ForEach(service.characteristics.filter { shouldDisplay($0) }) { char in
                    HStack {
                        Text(CharacteristicTypes.displayName(for: char.type))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let value = char.value {
                            Text(CharacteristicTypes.formatValue(value.value, characteristicType: char.type))
                                .font(.caption)
                                .fontWeight(.medium)
                        } else {
                            Text("--")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Filter out characteristics that aren't useful to display (e.g. Name, configured status).
    private func shouldDisplay(_ char: CharacteristicModel) -> Bool {
        let hidden = ["Name", "Is Configured", "Status Active"]
        let displayName = CharacteristicTypes.displayName(for: char.type)
        return !hidden.contains(displayName)
    }

    private var deviceIcon: String {
        switch device.categoryType {
        case "HMAccessoryCategoryTypeLightbulb":
            return "lightbulb.fill"
        case "HMAccessoryCategoryTypeSwitch":
            return "switch.2"
        case "HMAccessoryCategoryTypeOutlet":
            return "poweroutlet.type.b"
        case "HMAccessoryCategoryTypeThermostat":
            return "thermometer"
        case "HMAccessoryCategoryTypeFan":
            return "fan"
        case "HMAccessoryCategoryTypeDoor":
            return "door.left.hand.closed"
        case "HMAccessoryCategoryTypeWindow":
            return "window.vertical.closed"
        case "HMAccessoryCategoryTypeLock":
            return "lock.fill"
        case "HMAccessoryCategoryTypeSensor":
            return "sensor"
        case "HMAccessoryCategoryTypeGarageDoorOpener":
            return "door.garage.closed"
        case "HMAccessoryCategoryTypeProgrammableSwitch":
            return "button.programmable"
        case "HMAccessoryCategoryTypeSecuritySystem":
            return "shield.fill"
        case "HMAccessoryCategoryTypeBridge":
            return "network"
        default:
            return "house.fill"
        }
    }
}

#Preview {
    List {
        DeviceRow(device: PreviewData.sampleDevices[0])
        DeviceRow(device: PreviewData.sampleDevices[2])
    }
}
