import SwiftUI

struct DeviceRow: View {
    let device: DeviceModel
    @ObservedObject var viewModel: HomeKitViewModel
    @State private var isExpanded = false
    @State private var charSettings: [String: (enabled: Bool, observed: Bool)] = [:]
    @State private var isHovered = false
    @State private var renamingService: ServiceModel?
    @State private var renameText = ""

    private var displayCharacteristics: [(service: ServiceModel, char: CharacteristicModel)] {
        device.services.flatMap { service in
            service.characteristics.map { (service: service, char: $0) }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 8)
    ]

    private var deviceEnabled: Bool {
        viewModel.isEnabled(for: device)
    }

    private var deviceObserved: Bool {
        viewModel.isObserved(for: device)
    }

    /// Whether the device has any characteristic that supports notify.
    private var deviceHasNotifiableCharacteristics: Bool {
        device.services.flatMap(\.characteristics).contains { $0.permissions.contains("notify") }
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

                    if isExpanded {
                        Text(device.id)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.Text.tertiary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                // Compact Controls
                VStack(alignment: .trailing, spacing: 12) {
                    MiniToggle(isOn: Binding(
                        get: { deviceEnabled },
                        set: { result in
                            viewModel.setDeviceEnabled(device: device, enabled: result)
                        }
                    ), label: "Enabled")

                    MiniToggle(isOn: Binding(
                        get: { deviceObserved },
                        set: { result in
                            viewModel.setDeviceObserved(device: device, observed: result)
                        }
                    ), label: "Observed")
                    .disabled(!deviceEnabled || !deviceHasNotifiableCharacteristics)
                    .opacity(deviceEnabled && deviceHasNotifiableCharacteristics ? 1 : 0.4)
                    .help(!deviceEnabled
                          ? "Enable the device first to observe state changes"
                          : (deviceHasNotifiableCharacteristics
                             ? "Observe state changes for this device"
                             : "No characteristics support notifications"))
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
                                        Text(serviceDisplayName(for: service))
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(Theme.Text.secondary)
                                            .textCase(.uppercase)

                                        Button {
                                            renameText = serviceDisplayName(for: service)
                                            renamingService = service
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12))
                                                .foregroundColor(Theme.Text.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Rename service")

                                        if let stableId = stableServiceId(for: service) {
                                            let hasCustomName = viewModel.registryService.readServiceCustomName(forStableServiceId: stableId) != nil

                                            // "Use type name" — only when the global setting is off
                                            if !useServiceTypeAsName && !hasCustomName && serviceDisplayName(for: service) != service.displayName {
                                                Button {
                                                    viewModel.renameService(stableServiceId: stableId, customName: service.displayName)
                                                } label: {
                                                    Image(systemName: "tag")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(Theme.Text.tertiary)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Use type name: \(service.displayName)")
                                            }

                                            // Reset — only if a custom name is set
                                            if hasCustomName {
                                                Button {
                                                    viewModel.renameService(stableServiceId: stableId, customName: nil)
                                                } label: {
                                                    Image(systemName: "arrow.counterclockwise")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(Theme.Text.tertiary)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Reset to default name")
                                            }

                                            Button {
                                                UIPasteboard.general.string = stableId
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(Theme.Text.tertiary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy service ID")
                                        }
                                    }
                                    .padding(.horizontal, Theme.Spacing.medium)

                                    if let stableId = stableServiceId(for: service) {
                                        Text(stableId)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(Theme.Text.tertiary)
                                            .lineLimit(1)
                                            .textSelection(.enabled)
                                            .padding(.horizontal, Theme.Spacing.medium)
                                    }

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

            Button {
                UIPasteboard.general.string = device.id
            } label: {
                Label("Copy Device ID", systemImage: "number")
            }

            Divider()

            Button {
                viewModel.setDeviceEnabled(device: device, enabled: !deviceEnabled)
            } label: {
                Label(deviceEnabled ? "Disable" : "Enable",
                      systemImage: deviceEnabled ? "xmark.circle" : "checkmark.circle")
            }

            if deviceHasNotifiableCharacteristics && deviceEnabled {
                Button {
                    viewModel.setDeviceObserved(device: device, observed: !deviceObserved)
                } label: {
                    Label(deviceObserved ? "Stop Observing" : "Start Observing",
                          systemImage: deviceObserved ? "eye.slash" : "eye")
                }
            }

        }
        .alert("Rename Service", isPresented: Binding(
            get: { renamingService != nil },
            set: { if !$0 { renamingService = nil } }
        )) {
            TextField("Service name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingService = nil }
            Button("Save") {
                guard let service = renamingService,
                      let stableId = stableServiceId(for: service) else {
                    renamingService = nil
                    return
                }
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                viewModel.renameService(
                    stableServiceId: stableId,
                    customName: trimmed.isEmpty ? nil : trimmed
                )
                renamingService = nil
            }
        } message: {
            if let service = renamingService {
                Text("Enter a custom name for \"\(serviceDisplayName(for: service))\"")
            }
        }
        .task {
            await loadSettings()
        }
        .onReceive(viewModel.registryService.registrySyncSubject.receive(on: DispatchQueue.main)) { _ in
            Task { await loadSettings() }
        }
    }

    private func characteristicTile(service: ServiceModel, char: CharacteristicModel) -> some View {
        let stableCharId = viewModel.registryService.readStableCharacteristicId(char.id)
        let stableDevId = viewModel.registryService.readStableDeviceId(device.id) ?? device.id
        let displayCharId = stableCharId ?? char.id
        let settings = stableCharId.flatMap { charSettings[$0] } ?? (enabled: true, observed: false)
        let canObserve = settings.enabled && char.permissions.contains("notify")

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

                    Text(displayCharId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.Text.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 4) {
                MiniToggle(isOn: Binding(
                    get: { settings.enabled },
                    set: { val in
                        if let id = stableCharId {
                            charSettings[id] = (enabled: val, observed: val ? settings.observed : false)
                            viewModel.setCharacteristicEnabled(stableCharId: id, enabled: val)
                        }
                    }
                ), label: "Enabled")

                Spacer()

                if char.permissions.contains("notify") {
                    MiniToggle(isOn: Binding(
                        get: { settings.observed },
                        set: { val in
                            if let id = stableCharId {
                                charSettings[id] = (enabled: settings.enabled, observed: val)
                                viewModel.setCharacteristicObserved(stableCharId: id, observed: val)
                            }
                        }
                    ), label: "Observed")
                    .disabled(!canObserve)
                    .opacity(canObserve ? 1 : 0.4)
                } else {
                    Text("No notify")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Text.tertiary)
                }
            }

            Divider()

            HStack(spacing: 6) {
                tileActionButton(label: "ID", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = displayCharId
                }

                if char.permissions.contains("write") {
                    tileActionButton(label: "URL", systemImage: "link") {
                        let sv = controlSampleValue(for: char)
                        let port = UserDefaults.standard.integer(forKey: "mcpServerPort")
                        let host = UserDefaults.standard.string(forKey: "mcpServerBindAddress") ?? "127.0.0.1"
                        let displayHost = host == "0.0.0.0" ? "localhost" : host
                        let pv = possibleValuesDescription(for: char)
                        var text = "// Device ID: \(stableDevId)\n"
                        text += "// Possible values: \(pv)\n"
                        text += "// Method: PUT (query params as fallback for simple integrations)\n"
                        text += "http://\(displayHost):\(port)/devices/\(stableDevId)/control?characteristic_id=\(displayCharId)&value=\(sv)"
                        UIPasteboard.general.string = text
                    }

                    tileActionButton(label: "JSON", systemImage: "curlybraces") {
                        let sv = controlSampleValue(for: char)
                        let pv = possibleValuesDescription(for: char)
                        let port = UserDefaults.standard.integer(forKey: "mcpServerPort")
                        let host = UserDefaults.standard.string(forKey: "mcpServerBindAddress") ?? "127.0.0.1"
                        let displayHost = host == "0.0.0.0" ? "localhost" : host
                        let json = """
                        // Device ID: \(stableDevId)
                        // Possible values: \(pv)
                        // PUT http://\(displayHost):\(port)/devices/\(stableDevId)/control
                        {
                          "characteristic_id": "\(displayCharId)",
                          "value": \(controlSampleJsonValue(for: char, sampleValue: sv))
                        }
                        """
                        UIPasteboard.general.string = json
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.surfaceOverlay)
        .cornerRadius(Theme.CornerRadius.small)
    }

    private func tileActionButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(Theme.Text.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.contentBackground)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func controlSampleValue(for char: CharacteristicModel) -> String {
        if let validValues = char.validValues, !validValues.isEmpty {
            if let raw = char.value?.value {
                let numeric = coerceToInt(raw)
                if validValues.contains(numeric) { return "\(numeric)" }
            }
            return "\(validValues[0])"
        }
        if let raw = char.value?.value {
            if let b = raw as? Bool { return b ? "true" : "false" }
            if let i = raw as? Int { return "\(i)" }
            if let d = raw as? Double { return "\(d)" }
            return "\(raw)"
        }
        switch char.format {
        case "bool": return "true"
        case "int", "uint8", "uint16", "uint32", "uint64":
            if let min = char.minValue { return "\(Int(min))" }
            return "0"
        case "float":
            if let min = char.minValue { return "\(min)" }
            return "0.0"
        default: return "value"
        }
    }

    private func controlSampleJsonValue(for char: CharacteristicModel, sampleValue: String) -> String {
        if char.validValues != nil && !char.validValues!.isEmpty {
            return sampleValue
        }
        switch char.format {
        case "bool": return sampleValue
        case "int", "uint8", "uint16", "uint32", "uint64": return sampleValue
        case "float": return sampleValue
        default: return "\"\(sampleValue)\""
        }
    }

    private func coerceToInt(_ value: Any) -> Int {
        if let b = value as? Bool { return b ? 1 : 0 }
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return 0
    }

    private func possibleValuesDescription(for char: CharacteristicModel) -> String {
        if let validValues = char.validValues, !validValues.isEmpty {
            let options = CharacteristicInputConfig.buildPickerOptions(for: char.type, values: validValues)
            return options.map { "\($0.value) (\($0.label))" }.joined(separator: ", ")
        }
        switch char.format {
        case "bool":
            return "true (On), false (Off)"
        case "int", "uint8", "uint16", "uint32", "uint64":
            let min = char.minValue.map { String(Int($0)) } ?? "0"
            let max = char.maxValue.map { String(Int($0)) } ?? "255"
            let step = char.stepValue.map { " (step: \(Int($0)))" } ?? ""
            return "\(min) – \(max)\(step)"
        case "float":
            let min = char.minValue.map { String($0) } ?? "0.0"
            let max = char.maxValue.map { String($0) } ?? "100.0"
            let step = char.stepValue.map { " (step: \($0))" } ?? ""
            return "\(min) – \(max)\(step)"
        case "string":
            return "string"
        default:
            return "any"
        }
    }

    /// Loads settings for this device's characteristics from the registry.
    private func loadSettings() async {
        let allSettings = await viewModel.getAllCharacteristicSettings()
        var deviceSettings: [String: (enabled: Bool, observed: Bool)] = [:]
        for service in device.services {
            for char in service.characteristics {
                if let stableCharId = viewModel.registryService.readStableCharacteristicId(char.id) {
                    deviceSettings[stableCharId] = allSettings[stableCharId] ?? (enabled: true, observed: false)
                }
            }
        }
        charSettings = deviceSettings
    }

    private func stableServiceId(for service: ServiceModel) -> String? {
        viewModel.registryService.readStableServiceId(service.id)
    }

    /// Returns the custom name from the registry if set, then the service type name if that setting
    /// is enabled, otherwise the HomeKit effective name.
    private func serviceDisplayName(for service: ServiceModel) -> String {
        if let stableId = stableServiceId(for: service),
           let customName = viewModel.registryService.readServiceCustomName(forStableServiceId: stableId) {
            return customName
        }
        if useServiceTypeAsName {
            return service.displayName
        }
        return service.effectiveDisplayName
    }

    private var useServiceTypeAsName: Bool {
        UserDefaults.standard.bool(forKey: "useServiceTypeAsName")
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
