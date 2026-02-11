import SwiftUI

struct DeviceRow: View {
    let device: DeviceModel
    @ObservedObject var viewModel: HomeKitViewModel
    @State private var isExpanded = false
    @State private var configs: [String: CharacteristicConfiguration] = [:]

    private var displayCharacteristics: [(service: ServiceModel, char: CharacteristicModel)] {
        device.services.flatMap { service in
            service.characteristics
                .filter { shouldDisplay($0) }
                .map { (service: service, char: $0) }
        }
    }

    private let columns = [
        GridItem(.flexible(minimum: 120), spacing: 10),
        GridItem(.flexible(minimum: 120), spacing: 10),
        GridItem(.flexible(minimum: 120), spacing: 10),
        GridItem(.flexible(minimum: 120), spacing: 10)
    ]

    private var deviceMCPEnabled: Bool {
        let allKeys = device.services.flatMap { service in
            service.characteristics.map { configKey(deviceId: device.id, serviceId: service.id, charId: $0.id) }
        }
        guard !allKeys.isEmpty else { return true }
        return allKeys.contains { configs[$0]?.mcpEnabled ?? true }
    }

    private var deviceWebhookEnabled: Bool {
        let allKeys = device.services.flatMap { service in
            service.characteristics.map { configKey(deviceId: device.id, serviceId: service.id, charId: $0.id) }
        }
        guard !allKeys.isEmpty else { return false }
        return allKeys.contains { configs[$0]?.webhookEnabled ?? false }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(displayCharacteristics, id: \.char.id) { item in
                    characteristicTile(service: item.service, char: item.char)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            HStack {
                Image(systemName: deviceIcon)
                    .foregroundColor(.accentColor)
                Text(device.name)
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { deviceMCPEnabled },
                            set: { newValue in
                                updateAllConfigs(mcpEnabled: newValue)
                                viewModel.setDeviceConfig(device: device, mcpEnabled: newValue)
                            }
                        )) { EmptyView() }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        Text("MCP")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { deviceWebhookEnabled },
                            set: { newValue in
                                updateAllConfigs(webhookEnabled: newValue)
                                viewModel.setDeviceConfig(device: device, webhookEnabled: newValue)
                            }
                        )) { EmptyView() }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        Text("Webhook")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Circle()
                        .fill(device.isReachable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            await loadConfigs()
        }
    }

    private func characteristicTile(service: ServiceModel, char: CharacteristicModel) -> some View {
        let key = configKey(deviceId: device.id, serviceId: service.id, charId: char.id)
        let config = configs[key] ?? .default

        return VStack(alignment: .leading, spacing: 4) {
            HStack{
                Text(CharacteristicTypes.displayName(for: char.type))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let value = char.value {
                    Text(CharacteristicTypes.formatValue(value.value, characteristicType: char.type))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { config.mcpEnabled },
                        set: { newValue in
                            var updated = config
                            updated.mcpEnabled = newValue
                            configs[key] = updated
                            viewModel.setConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id, config: updated)
                        }
                    )) { EmptyView() }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    Text("MCP")
                }

                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { config.webhookEnabled },
                        set: { newValue in
                            var updated = config
                            updated.webhookEnabled = newValue
                            configs[key] = updated
                            viewModel.setConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id, config: updated)
                        }
                    )) { EmptyView() }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    Text("Webhook")
                }
            }
            .padding(.top, 4)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .border(.gray)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func configKey(deviceId: String, serviceId: String, charId: String) -> String {
        "\(deviceId):\(serviceId):\(charId)"
    }

    private func updateAllConfigs(mcpEnabled: Bool? = nil, webhookEnabled: Bool? = nil) {
        for service in device.services {
            for char in service.characteristics {
                let key = configKey(deviceId: device.id, serviceId: service.id, charId: char.id)
                var config = configs[key] ?? .default
                if let mcp = mcpEnabled { config.mcpEnabled = mcp }
                if let webhook = webhookEnabled { config.webhookEnabled = webhook }
                configs[key] = config
            }
        }
    }

    private func loadConfigs() async {
        for service in device.services {
            for char in service.characteristics {
                let key = configKey(deviceId: device.id, serviceId: service.id, charId: char.id)
                let config = await viewModel.getConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id)
                configs[key] = config
            }
        }
    }

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
        DeviceRow(device: PreviewData.sampleDevices[0], viewModel: PreviewData.homeKitViewModel)
        DeviceRow(device: PreviewData.sampleDevices[2], viewModel: PreviewData.homeKitViewModel)
    }
}
