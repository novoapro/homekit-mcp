import SwiftUI

struct DeviceRow: View {
    let device: DeviceModel
    @ObservedObject var viewModel: HomeKitViewModel
    @State private var isExpanded = false
    @State private var configs: [String: CharacteristicConfiguration] = [:]
    @State private var showGranularControls = false
    @State private var isHovered = false

    private var displayCharacteristics: [(service: ServiceModel, char: CharacteristicModel)] {
        device.services.flatMap { service in
            service.characteristics
                .filter { shouldDisplay($0) }
                .map { (service: service, char: $0) }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 8)
    ]

    private var deviceExternalAccessEnabled: Bool {
        viewModel.isExternalAccessEnabled(for: device)
    }

    private var deviceWebhookEnabled: Bool {
        viewModel.isWebhookEnabled(for: device)
    }

    // MARK: - Category-based colors (matching Apple Home app)

    private var categoryColor: Color {
        device.isReachable ? Theme.Category.color(for: device.categoryType) : Theme.Status.inactive
    }

    var body: some View {
        VStack {
            // Header
            HStack(spacing: Theme.Spacing.medium) {
                // Circular Icon Container (Home app style: 40pt circle with category color)
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(device.isReachable ? 0.15 : 0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: deviceIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(categoryColor)
                }

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
                                .font(.footnote)
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
                    ), label: "API")

                    MiniToggle(isOn: Binding(
                        get: { deviceWebhookEnabled },
                        set: { result in
                            updateAllConfigs(webhookEnabled: result)
                            viewModel.setDeviceConfig(device: device, webhookEnabled: result)
                        }
                    ), label: "Webhook")
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
                withAnimation(Theme.Animation.expand) {
                    isExpanded.toggle()
                }
            }

            // Expanded Content
            if isExpanded {
                VStack(spacing: 20) {
                     if !displayCharacteristics.isEmpty {
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
                                            .font(.footnote)
                                            .foregroundColor(categoryColor)
                                        Text(service.effectiveDisplayName)
                                            .font(.footnote)
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
                                    .font(.footnote)
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

                        // Granular controls disclosure
                        if displayCharacteristics.count > 1 {
                            Button {
                                withAnimation(Theme.Animation.expand) {
                                    showGranularControls.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showGranularControls ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(showGranularControls ? "Hide Granular Controls" : "Show Granular Controls")
                                        .font(.footnote)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(Theme.Text.tertiary)
                                .padding(.horizontal, Theme.Spacing.medium)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .background(Theme.contentBackground)
        .cornerRadius(Theme.CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = device.name
            } label: {
                Label("Copy Device Name", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                viewModel.setDeviceConfig(device: device, externalAccessEnabled: !deviceExternalAccessEnabled)
                updateAllConfigs(externalAccessEnabled: !deviceExternalAccessEnabled)
            } label: {
                Label(deviceExternalAccessEnabled ? "Disable API Access" : "Enable API Access",
                      systemImage: deviceExternalAccessEnabled ? "xmark.circle" : "checkmark.circle")
            }

            Button {
                viewModel.setDeviceConfig(device: device, webhookEnabled: !deviceWebhookEnabled)
                updateAllConfigs(webhookEnabled: !deviceWebhookEnabled)
            } label: {
                Label(deviceWebhookEnabled ? "Disable Webhook" : "Enable Webhook",
                      systemImage: deviceWebhookEnabled ? "xmark.circle" : "checkmark.circle")
            }
        }
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.Text.primary)
                        .lineLimit(1)

                    if let value = char.value {
                        Text(CharacteristicTypes.formatValue(value.value, characteristicType: char.type))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(1)
                    } else {
                        Text("--")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Text.secondary)
                    }
                }
                Spacer()
            }

            // Granular controls — hidden by default to reduce density
            if showGranularControls {
                Divider()

                HStack(spacing: 4) {
                    MiniToggle(isOn: Binding(
                        get: { config.externalAccessEnabled },
                        set: { val in
                            var updated = config
                            updated.externalAccessEnabled = val
                            configs[key] = updated
                            viewModel.setConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id, config: updated)
                        }
                    ), label: "API")

                    Spacer()

                    MiniToggle(isOn: Binding(
                        get: { config.webhookEnabled },
                        set: { val in
                            var updated = config
                            updated.webhookEnabled = val
                            configs[key] = updated
                            viewModel.setConfig(deviceId: device.id, serviceId: service.id, characteristicId: char.id, config: updated)
                        }
                    ), label: "Webhook")
                }
            }
        }
        .padding(10)
        .background(Theme.surfaceOverlay)
        .cornerRadius(Theme.CornerRadius.small)
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

    /// Loads configs for this device in a single batch actor call.
    private func loadConfigs() async {
        let allConfigs = await viewModel.getAllConfigs()
        var deviceConfigs: [String: CharacteristicConfiguration] = [:]
        for service in device.services {
            for char in service.characteristics {
                let key = configKey(deviceId: device.id, serviceId: service.id, charId: char.id)
                deviceConfigs[key] = allConfigs[key] ?? .default
            }
        }
        configs = deviceConfigs
    }

    private func shouldDisplay(_ char: CharacteristicModel) -> Bool {
        char.isUserFacing
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
        case "HMAccessoryCategoryTypeDoorLock":
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

struct MiniToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 6) {
               Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isOn ? Theme.Text.primary : Theme.Text.secondary)

               Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isOn ? Theme.Tint.main : Theme.Text.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(isOn ? "enabled" : "disabled")")
        .accessibilityHint("Double tap to toggle \(label.lowercased())")
        .help(label == "API" ? "Include in MCP and REST API responses" : "Send webhook notifications on state changes")
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
