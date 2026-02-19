import SwiftUI

struct DeviceRow: View {
    let device: DeviceModel
    @ObservedObject var viewModel: HomeKitViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
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
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 8)
    ]

    private var deviceExternalAccessEnabled: Bool {
        viewModel.isExternalAccessEnabled(for: device)
    }

    private var deviceWebhookEnabled: Bool {
        viewModel.isWebhookEnabled(for: device)
    }
    
    // Status color based on reachability and activity
    private var statusColor: Color {
        device.isReachable ? Theme.Status.active : Theme.Status.error
    }
    
    // Dynamic icon background color
    private var iconBackgroundColor: Color {
        device.isReachable ? Theme.Tint.main.opacity(0.1) : Theme.Status.inactive.opacity(0.1)
    }
    
    private var iconForegroundColor: Color {
        device.isReachable ? Theme.Tint.main : Theme.Status.inactive
    }

    var body: some View {
        VStack {
            // Header
            HStack(spacing: Theme.Spacing.medium) {
                // Icon Container
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                        .fill(iconBackgroundColor)
                    
                    Image(systemName: deviceIcon)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(iconForegroundColor)
                }
                .frame(width: 50, height: 50)
                
                // Device Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(Theme.Text.primary)
                    
                    HStack(spacing: 6) {
                        Text(device.roomName ?? "Unknown Room")
                            .font(.subheadline)
                            .foregroundColor(Theme.Text.secondary)
                        
                        if !device.isReachable {
                            Text("No Response")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Status.error.opacity(0.1))
                                .foregroundColor(Theme.Status.error)
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Compact Controls
                VStack(alignment: .trailing, spacing: 12) {
                    MiniToggle(isOn: Binding(
                        get: { deviceExternalAccessEnabled },
                        set: { result in
                            updateAllConfigs(externalAccessEnabled: result)
                            viewModel.setDeviceConfig(device: device, externalAccessEnabled: result)
                        }
                    ), label: "EXT")
                    
                    MiniToggle(isOn: Binding(
                        get: { deviceWebhookEnabled },
                        set: { result in
                            updateAllConfigs(webhookEnabled: result)
                            viewModel.setDeviceConfig(device: device, webhookEnabled: result)
                        }
                    ), label: "Hook")
                }
                .padding(.trailing, 8)
                
                // Expansion Indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Text.secondary.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(Theme.Spacing.medium)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded Content
            if isExpanded {
                VStack(spacing: 20) {
                     if !displayCharacteristics.isEmpty {
                        // Divider before characteristics if needed, or rely on spacing
                         Divider()
                             .padding(.horizontal, Theme.Spacing.medium)

                        // Group characteristics by service for multi-service devices
                        if device.services.count > 1 {
                            ForEach(device.services.filter { service in
                                displayCharacteristics.contains { $0.service.id == service.id }
                            }) { service in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: serviceIcon(for: service.type))
                                            .font(.caption)
                                            .foregroundColor(Theme.Tint.main)
                                        Text(service.displayName)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(Theme.Text.secondary)
                                            .textCase(.uppercase)
                                    }
                                    .padding(.horizontal, Theme.Spacing.medium)

                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                        ForEach(displayCharacteristics.filter { $0.service.id == service.id }, id: \.char.id) { item in
                                            characteristicTile(service: item.service, char: item.char)
                                        }
                                    }
                                    .padding(.horizontal, Theme.Spacing.medium)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Characteristics")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.Text.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, Theme.Spacing.medium)
                                
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                    ForEach(displayCharacteristics, id: \.char.id) { item in
                                        characteristicTile(service: item.service, char: item.char)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.medium)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .background(Theme.contentBackground)
        .cornerRadius(Theme.CornerRadius.large)
        // Add a subtle border/shadow for depth
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .task {
            await loadConfigs()
        }
    }

    private func characteristicTile(service: ServiceModel, char: CharacteristicModel) -> some View {
        let key = configKey(deviceId: device.id, serviceId: service.id, charId: char.id)
        let config = configs[key] ?? .default
        
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CharacteristicTypes.displayName(for: char.type))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.Text.primary)
                        .lineLimit(1)
                    
                    if let value = char.value {
                        Text(CharacteristicTypes.formatValue(value.value, characteristicType: char.type))
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(1)
                    } else {
                        Text("--")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Text.secondary)
                    }
                }
                Spacer()
            }
            
            Divider()
            
            // granular controls
            HStack(spacing: 4) {
                MiniToggle(isOn: Binding(
                    get: { config.externalAccessEnabled },
                    set: { val in
                        var updated = config
                        updated.externalAccessEnabled = val
                        configs[key] = updated
                        viewModel.setConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id, config: updated)
                    }
                ), label: "EXT")
                
                Spacer()
                
                MiniToggle(isOn: Binding(
                    get: { config.webhookEnabled },
                    set: { val in
                        var updated = config
                        updated.webhookEnabled = val
                        configs[key] = updated
                        viewModel.setConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id, config: updated)
                    }
                ), label: "Hook")
            }
        }
        .padding(10)
        .background(Theme.mainBackground.opacity(0.3))
        .cornerRadius(Theme.CornerRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                .stroke(Theme.Tint.main.opacity(0.5), lineWidth: 1)
        )
        
    }

    private func configKey(deviceId: String, serviceId: String, charId: String) -> String {
        "\(deviceId):\(serviceId):\(charId)"
    }

    private func updateAllConfigs(externalAccessEnabled: Bool? = nil, webhookEnabled: Bool? = nil) {
        for service in device.services {
            for char in service.characteristics {
                let key = configKey(deviceId: device.id, serviceId: service.id, charId: char.id)
                var config = configs[key] ?? .default
                if let ext = externalAccessEnabled { config.externalAccessEnabled = ext }
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

    private func serviceIcon(for serviceType: String) -> String {
        let displayName = ServiceTypes.displayName(for: serviceType)
        switch displayName {
        case "Lightbulb": return "lightbulb.fill"
        case "Fan": return "fan"
        case "Switch": return "switch.2"
        case "Outlet": return "poweroutlet.type.b"
        case "Thermostat": return "thermometer"
        case "Door": return "door.left.hand.closed"
        case "Lock": return "lock.fill"
        case "Window": return "window.vertical.closed"
        case "Window Covering": return "blinds.vertical.closed"
        case "Garage Door Opener": return "door.garage.closed"
        case "Motion Sensor": return "figure.walk"
        case "Temperature Sensor": return "thermometer"
        case "Humidity Sensor": return "humidity"
        case "Speaker": return "speaker.fill"
        case "Battery": return "battery.100"
        case "Valve": return "spigot"
        case "Security System": return "shield.fill"
        default: return "gearshape"
        }
    }
}

// MARK: - Helper Views

struct ControlToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Text.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.Tint.main)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(Theme.Text.secondary)
                }
            }
            .padding(12)
            .background(Theme.detailBackground.opacity(0.3))
            .cornerRadius(Theme.CornerRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .stroke(isOn ? Theme.Tint.main.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MiniToggle: View {
    @Binding var isOn: Bool
    let label: String
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 6) {
               Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isOn ? Theme.Text.primary : Theme.Text.secondary)
                
               Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isOn ? Theme.Tint.main : Theme.Text.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    List {
        DeviceRow(device: PreviewData.sampleDevices[0], viewModel: PreviewData.homeKitViewModel)
            .listRowInsets(EdgeInsets())
            .padding()
    }
    .listStyle(.plain)
}
