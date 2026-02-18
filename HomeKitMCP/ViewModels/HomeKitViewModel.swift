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
    @Published var selectedRooms: Set<String> = []
    @Published var selectedServiceTypes: Set<String> = []
    @Published var mcpFilter: TriStateFilter = .all
    @Published var webhookFilter: TriStateFilter = .all

    // Device-level config cache: deviceId -> (externalAccessEnabled: Bool, webhookEnabled: Bool)
    @Published private(set) var deviceConfigCache: [String: (externalAccessEnabled: Bool, webhookEnabled: Bool)] = [:]

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
        !selectedRooms.isEmpty || !selectedServiceTypes.isEmpty || mcpFilter != .all || webhookFilter != .all
    }

    @Published var filteredDevicesByRoom: [(roomName: String, devices: [DeviceModel])] = []

    init(homeKitManager: HomeKitManager, configService: DeviceConfigurationService) {
        self.homeKitManager = homeKitManager
        self.configService = configService

        // Setup background filtering pipeline
        Publishers.CombineLatest4(
            $devicesByRoom,
            $searchText,
            $selectedRooms,
            $selectedServiceTypes
        )
        .combineLatest($mcpFilter, $webhookFilter, $deviceConfigCache)
        .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main) // Debounce UI updates
        .receive(on: DispatchQueue.global(qos: .userInitiated)) // Process on background thread
        .map { (inputs, mcpFilter, webhookFilter, configCache) -> [(roomName: String, devices: [DeviceModel])] in
            let (devicesByRoom, searchText, selectedRooms, selectedServiceTypes) = inputs
            
            var groups = devicesByRoom

            // Filter by room
            if !selectedRooms.isEmpty {
                groups = groups.filter { selectedRooms.contains($0.roomName) }
            }

            // Apply search + MCP/Webhook/ServiceType filters to devices within groups
            return groups.compactMap { group in
                let filteredDevices = group.devices.filter { device in
                    // Search filter
                    if !searchText.isEmpty && !device.name.localizedCaseInsensitiveContains(searchText) {
                        return false
                    }

                    // Service type filter
                    if !selectedServiceTypes.isEmpty {
                        let hasServiceType = device.services.contains { service in
                            selectedServiceTypes.contains(ServiceTypes.displayName(for: service.type))
                        }
                        if !hasServiceType { return false }
                    }

                    // MCP filter
                    if mcpFilter != .all {
                        let cache = configCache[device.id]
                        let hasExternal = cache?.externalAccessEnabled ?? true // default is enabled
                        if mcpFilter == .enabled && !hasExternal { return false }
                        if mcpFilter == .disabled && hasExternal { return false }
                    }

                    // Webhook filter
                    if webhookFilter != .all {
                        let cache = configCache[device.id]
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
        .receive(on: DispatchQueue.main) // Update UI on main thread
        .assign(to: &$filteredDevicesByRoom)

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
        selectedRooms.removeAll()
        selectedServiceTypes.removeAll()
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
        var cache: [String: (externalAccessEnabled: Bool, webhookEnabled: Bool)] = [:]

        for group in devicesByRoom {
            for device in group.devices {
                var anyExternal = false
                var anyWebhook = false

                for service in device.services {
                    for char in service.characteristics {
                        let config = await configService.getConfig(
                            deviceId: device.id,
                            serviceId: service.id,
                            characteristicId: char.id
                        )
                        if config.externalAccessEnabled { anyExternal = true }
                        if config.webhookEnabled { anyWebhook = true }
                    }
                }

                cache[device.id] = (externalAccessEnabled: anyExternal, webhookEnabled: anyWebhook)
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

    func setDeviceConfig(device: DeviceModel, externalAccessEnabled: Bool? = nil, webhookEnabled: Bool? = nil) {
        let services = device.services.map { service in
            (serviceId: service.id, characteristicIds: service.characteristics.map(\.id))
        }
        Task {
            await configService.setAllForDevice(deviceId: device.id, services: services, externalAccessEnabled: externalAccessEnabled, webhookEnabled: webhookEnabled)
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

    func getRoomName(for deviceId: String) -> String? {
        for group in devicesByRoom {
            if group.devices.contains(where: { $0.id == deviceId }) {
                return group.roomName
            }
        }
        return nil
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
