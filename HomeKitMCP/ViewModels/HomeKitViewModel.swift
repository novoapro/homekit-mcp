import Foundation
import HomeKit
import Combine

enum TriStateFilter: String, CaseIterable {
    case all = "All"
    case enabled = "Enabled"
    case disabled = "Disabled"
}

class HomeKitViewModel: ObservableObject {
    @Published var devicesByRoom: [(roomName: String, devices: [DeviceModel])] = []
    @Published var isLoading = true
    @Published var isReadingValues = false
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined
    @Published var errorMessage: String?

    // Search & Filters
    @Published var searchText = ""
    @Published var selectedRoom: String? = nil
    @Published var selectedServiceType: String? = nil
    @Published var mcpFilter: TriStateFilter = .all
    @Published var webhookFilter: TriStateFilter = .all

    // Device-level config cache: deviceId -> (anyMCPEnabled, anyWebhookEnabled)
    @Published private(set) var deviceConfigCache: [String: (mcpEnabled: Bool, webhookEnabled: Bool)] = [:]

    private let homeKitManager: HomeKitManager
    let configService: DeviceConfigurationService
    private var cancellables = Set<AnyCancellable>()

    /// Debounces rapid refresh triggers to avoid redundant UI rebuilds.
    private var refreshWorkItem: DispatchWorkItem?

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var totalDeviceCount: Int {
        devicesByRoom.reduce(0) { $0 + $1.devices.count }
    }

    var availableRooms: [String] {
        devicesByRoom.map(\.roomName).sorted()
    }

    var availableServiceTypes: [String] {
        let allTypes = devicesByRoom.flatMap { group in
            group.devices.flatMap { device in
                device.services.map { ServiceTypes.displayName(for: $0.type) }
            }
        }
        return Array(Set(allTypes)).sorted()
    }

    var hasActiveFilters: Bool {
        selectedRoom != nil || selectedServiceType != nil || mcpFilter != .all || webhookFilter != .all
    }

    var filteredDevicesByRoom: [(roomName: String, devices: [DeviceModel])] {
        var groups = devicesByRoom

        // Filter by room
        if let room = selectedRoom {
            groups = groups.filter { $0.roomName == room }
        }

        // Apply search + MCP/Webhook/ServiceType filters to devices within groups
        return groups.compactMap { group in
            let filteredDevices = group.devices.filter { device in
                // Search filter
                if !searchText.isEmpty && !device.name.localizedCaseInsensitiveContains(searchText) {
                    return false
                }

                // Service type filter
                if let serviceType = selectedServiceType {
                    let hasServiceType = device.services.contains { service in
                        ServiceTypes.displayName(for: service.type) == serviceType
                    }
                    if !hasServiceType { return false }
                }

                // MCP filter
                if mcpFilter != .all {
                    let cache = deviceConfigCache[device.id]
                    let hasMCP = cache?.mcpEnabled ?? true // default is MCP enabled
                    if mcpFilter == .enabled && !hasMCP { return false }
                    if mcpFilter == .disabled && hasMCP { return false }
                }

                // Webhook filter
                if webhookFilter != .all {
                    let cache = deviceConfigCache[device.id]
                    let hasWebhook = cache?.webhookEnabled ?? false // default is webhook disabled
                    if webhookFilter == .enabled && !hasWebhook { return false }
                    if webhookFilter == .disabled && hasWebhook { return false }
                }

                return true
            }

            if filteredDevices.isEmpty { return nil }
            return (roomName: group.roomName, devices: filteredDevices)
        }
    }

    init(homeKitManager: HomeKitManager, configService: DeviceConfigurationService) {
        self.homeKitManager = homeKitManager
        self.configService = configService

        homeKitManager.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if isReady {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        homeKitManager.$isReadingValues
            .receive(on: DispatchQueue.main)
            .assign(to: &$isReadingValues)

        homeKitManager.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
                self?.updateErrorForStatus(status)
            }
            .store(in: &cancellables)

        homeKitManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.debouncedRefresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        devicesByRoom = homeKitManager.getDevicesGroupedByRoom()
        isLoading = false
        Task { await refreshConfigCache() }
    }

    func clearFilters() {
        selectedRoom = nil
        selectedServiceType = nil
        mcpFilter = .all
        webhookFilter = .all
    }

    /// Debounced version of refresh — coalesces multiple rapid triggers into one.
    private func debouncedRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// Builds a device-level config cache from the per-characteristic configs.
    private func refreshConfigCache() async {
        var cache: [String: (mcpEnabled: Bool, webhookEnabled: Bool)] = [:]

        for group in devicesByRoom {
            for device in group.devices {
                var anyMCP = false
                var anyWebhook = false

                for service in device.services {
                    for char in service.characteristics {
                        let config = await configService.getConfig(
                            deviceId: device.id,
                            serviceId: service.id,
                            characteristicId: char.id
                        )
                        if config.mcpEnabled { anyMCP = true }
                        if config.webhookEnabled { anyWebhook = true }
                    }
                }

                cache[device.id] = (mcpEnabled: anyMCP, webhookEnabled: anyWebhook)
            }
        }

        let snapshot = cache
        await MainActor.run {
            self.deviceConfigCache = snapshot
        }
    }

    func getConfig(deviceId: String, serviceId: String, characteristicId: String) async -> CharacteristicConfiguration {
        await configService.getConfig(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId)
    }

    func setConfig(deviceId: String, serviceId: String, characteristicId: String, config: CharacteristicConfiguration) {
        Task {
            await configService.setConfig(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId, config: config)
            await refreshConfigCache()
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }

    func setDeviceConfig(device: DeviceModel, mcpEnabled: Bool? = nil, webhookEnabled: Bool? = nil) {
        let services = device.services.map { service in
            (serviceId: service.id, characteristicIds: service.characteristics.map(\.id))
        }
        Task {
            await configService.setAllForDevice(deviceId: device.id, services: services, mcpEnabled: mcpEnabled, webhookEnabled: webhookEnabled)
            await refreshConfigCache()
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }

    func resetConfiguration() {
        Task {
            await configService.resetAll()
            await refreshConfigCache()
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }

    private func updateErrorForStatus(_ status: HMHomeManagerAuthorizationStatus) {
        if status == .restricted {
            errorMessage = "HomeKit access is restricted on this device."
        } else if !status.contains(.authorized) && homeKitManager.isReady {
            errorMessage = "HomeKit access was denied. Grant access in System Settings > Privacy & Security > HomeKit."
        } else {
            errorMessage = nil
        }
    }
}
