import SwiftUI

/// A small pill-shaped badge displaying the current live value of a characteristic.
/// Updates reactively as HomeKit delegate callbacks refresh the devices array.
struct CurrentValueBadge: View {
    let devices: [DeviceModel]
    let deviceId: String
    let characteristicId: String

    private var device: DeviceModel? {
        devices.first(where: { $0.id == deviceId })
    }

    private var characteristic: CharacteristicModel? {
        device?.services.flatMap(\.characteristics)
            .first(where: { $0.id == characteristicId || $0.type == characteristicId })
    }

    var body: some View {
        if let char = characteristic {
            let isReachable = device?.isReachable == true
            HStack(spacing: 6) {
                Circle()
                    .fill(isReachable ? Theme.Tint.main : Theme.Text.tertiary)
                    .frame(width: 6, height: 6)

                Text("Current:")
                    .font(.caption2)
                    .foregroundStyle(Theme.Text.tertiary)

                Text(displayValue(for: char, isReachable: isReachable))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(isReachable ? Theme.Text.primary : Theme.Text.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        isReachable
                            ? Theme.Tint.main.opacity(0.08)
                            : Color.gray.opacity(0.08)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isReachable
                                    ? Theme.Tint.main.opacity(0.15)
                                    : Color.gray.opacity(0.15),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private func displayValue(for char: CharacteristicModel, isReachable: Bool) -> String {
        guard isReachable else { return "Unavailable" }
        guard let rawValue = char.value?.value else { return "Unknown" }

        // Convert AnyCodable value to string for the formatter
        let rawStr: String
        if let boolVal = rawValue as? Bool {
            rawStr = boolVal ? "true" : "false"
        } else {
            rawStr = "\(rawValue)"
        }

        return CharacteristicInputConfig.displayValueForName(
            characteristicType: char.type,
            rawValue: rawStr
        )
    }
}
