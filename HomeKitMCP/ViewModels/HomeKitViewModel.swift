import Combine
import Foundation
import HomeKit

enum TriStateFilter: String, CaseIterable {
    case all = "All"
    case enabled = "Enabled"
    case disabled = "Disabled"
}

@MainActor
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
    @Published var selectedCharacteristicTypes: Set<String> = []
    @Published var enabledFilter: TriStateFilter = .all
    @Published var observedFilter: TriStateFilter = .all

    @Published var isRefreshing = false
    @Published var isUpdating = false
    /// Device-level settings cache: deviceId -> (enabled: Bool, observed: Bool)
    @Published private(set) var deviceConfigCache: [String: (enabled: Bool, observed: Bool)] = [:]

    private let homeKitManager: HomeKitManager
    let registryService: DeviceRegistryService
    private var cancellables = Set<AnyCancellable>()

    /// Debounces rapid refresh triggers to avoid redundant UI rebuilds.
    private var refreshWorkItem: DispatchWorkItem?

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var totalDeviceCount: Int {
        devicesByRoom.reduce(0) { $0 + $1.devices.count }
    }

    @Published private(set) var availableRooms: [String] = []
    @Published private(set) var availableServiceTypes: [String] = []
    @Published private(set) var availableCharacteristicTypes: [String] = []

    var hasActiveFilters: Bool {
        !selectedRooms.isEmpty || !selectedServiceTypes.isEmpty || !selectedCharacteristicTypes.isEmpty || enabledFilter != .all || observedFilter != .all
    }

    @Published var filteredDevicesByRoom: [(roomName: String, devices: [DeviceModel])] = []

    // Scenes
    @Published var scenes: [SceneModel] = []
    @Published var filteredScenes: [SceneModel] = []
    @Published var sceneSearchText = ""

    init(homeKitManager: HomeKitManager, registryService: DeviceRegistryService) {
        self.homeKitManager = homeKitManager
        self.registryService = registryService

        // Setup background filtering pipeline
        Publishers.CombineLatest4(
            $devicesByRoom,
            $searchText,
            $selectedRooms,
            $selectedServiceTypes
        )
        .combineLatest($selectedCharacteristicTypes, $enabledFilter)
        .combineLatest($observedFilter, $deviceConfigCache)
        .handleEvents(receiveOutput: { [weak self] _ in
            self?.isUpdating = true
        })
        .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main) // Debounce UI updates
        .receive(on: DispatchQueue.global(qos: .userInitiated)) // Process on background thread
        .map { lhs, observedFilter, configCache -> [(roomName: String, devices: [DeviceModel])] in
            let ((devicesByRoom, searchText, selectedRooms, selectedServiceTypes), selectedCharacteristicTypes, enabledFilter) = lhs

            var groups = devicesByRoom

            // Filter by room
            if !selectedRooms.isEmpty {
                groups = groups.filter { selectedRooms.contains($0.roomName) }
            }

            // Apply search + Enabled/Observed/ServiceType/CharacteristicType filters to devices within groups
            return groups.compactMap { group in
                let filteredDevices = group.devices.filter { device in
                    // Search filter
                    if !searchText.isEmpty, !device.name.localizedCaseInsensitiveContains(searchText) {
                        return false
                    }

                    // Service type filter
                    if !selectedServiceTypes.isEmpty {
                        let hasServiceType = device.services.contains { service in
                            selectedServiceTypes.contains(ServiceTypes.displayName(for: service.type))
                        }
                        if !hasServiceType { return false }
                    }

                    // Characteristic type filter
                    if !selectedCharacteristicTypes.isEmpty {
                        let hasCharType = device.services.contains { service in
                            service.characteristics.contains { char in
                                selectedCharacteristicTypes.contains(CharacteristicTypes.displayName(for: char.type))
                            }
                        }
                        if !hasCharType { return false }
                    }

                    // Enabled filter
                    if enabledFilter != .all {
                        let cache = configCache[device.id]
                        let hasEnabled = cache?.enabled ?? true
                        if enabledFilter == .enabled, !hasEnabled { return false }
                        if enabledFilter == .disabled, hasEnabled { return false }
                    }

                    // Observed filter
                    if observedFilter != .all {
                        let cache = configCache[device.id]
                        let hasObserved = cache?.observed ?? false
                        if observedFilter == .enabled, !hasObserved { return false }
                        if observedFilter == .disabled, hasObserved { return false }
                    }

                    return true
                }

                if filteredDevices.isEmpty { return nil }
                return (roomName: group.roomName, devices: filteredDevices)
            }
        }
        .receive(on: DispatchQueue.main) // Update UI on main thread
        .sink { [weak self] results in
            self?.filteredDevicesByRoom = results
            self?.isUpdating = false
        }
        .store(in: &cancellables)

        // Scene search filtering
        $sceneSearchText
            .combineLatest($scenes)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .map { query, scenes in
                guard !query.isEmpty else { return scenes }
                return scenes.filter { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .assign(to: &$filteredScenes)

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

        // Subscribe to registry sync events to refresh cache when settings change
        registryService.registrySyncSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshConfigCacheSync()
            }
            .store(in: &cancellables)
    }

    func refreshAsync() async {
        isRefreshing = true
        refresh()
        isRefreshing = false
    }

    func refresh() {
        devicesByRoom = homeKitManager.getDevicesGroupedByRoom()
        scenes = homeKitManager.getAllScenes()
        isLoading = false

        // Update cached filter options
        availableRooms = devicesByRoom.map(\.roomName).sorted()
        let allTypes = devicesByRoom.flatMap { group in
            group.devices.flatMap { device in
                device.services.map { ServiceTypes.displayName(for: $0.type) }
            }
        }
        availableServiceTypes = Array(Set(allTypes)).sorted()

        let allCharTypes: [String] = devicesByRoom.flatMap(\.devices)
            .flatMap(\.services)
            .flatMap(\.characteristics)
            .map { CharacteristicTypes.displayName(for: $0.type) }
        availableCharacteristicTypes = Array(Set(allCharTypes)).sorted()

        refreshConfigCacheSync()
    }

    func executeScene(id: String) async {
        do {
            try await homeKitManager.executeScene(id: id)
        } catch {
            AppLogger.scene.error("Scene execution failed: \(error.localizedDescription)")
        }
    }

    func clearFilters() {
        selectedRooms.removeAll()
        selectedServiceTypes.removeAll()
        selectedCharacteristicTypes.removeAll()
        enabledFilter = .all
        observedFilter = .all
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

    /// Builds a device-level settings cache from the registry using nonisolated lookups.
    private func refreshConfigCacheSync() {
        var cache: [String: (enabled: Bool, observed: Bool)] = [:]

        for group in devicesByRoom {
            for device in group.devices {
                var anyEnabled = false
                var anyObserved = false

                for service in device.services {
                    for char in service.characteristics {
                        let settings = registryService.readCharacteristicSettings(forHomeKitCharId: char.id)
                        if settings.enabled { anyEnabled = true }
                        if settings.observed && char.permissions.contains("notify") { anyObserved = true }
                    }
                }

                cache[device.id] = (enabled: anyEnabled, observed: anyObserved)
            }
        }

        deviceConfigCache = cache
    }

    /// Returns all characteristic settings from the registry. Used by DeviceRow to preload settings.
    func getAllCharacteristicSettings() async -> [String: (enabled: Bool, observed: Bool)] {
        await registryService.getAllCharacteristicSettings()
    }

    func setCharacteristicEnabled(stableCharId: String, enabled: Bool) {
        Task {
            await registryService.setCharacteristicEnabled(stableCharId: stableCharId, enabled: enabled)
            if !enabled {
                homeKitManager.refreshNotificationRegistrations()
            }
        }
    }

    func setCharacteristicObserved(stableCharId: String, observed: Bool) {
        Task {
            await registryService.setCharacteristicObserved(stableCharId: stableCharId, observed: observed)
            homeKitManager.refreshNotificationRegistrations()
        }
    }

    func setDeviceEnabled(device: DeviceModel, enabled: Bool) {
        guard let stableDeviceId = registryService.readStableDeviceId(device.id) else { return }
        Task {
            await registryService.setAllEnabled(deviceStableId: stableDeviceId, enabled: enabled)
            if !enabled {
                homeKitManager.refreshNotificationRegistrations()
            }
        }
    }

    func setDeviceObserved(device: DeviceModel, observed: Bool) {
        guard let stableDeviceId = registryService.readStableDeviceId(device.id) else { return }
        let notifiableCharTypes = Set(
            device.services.flatMap(\.characteristics)
                .filter { $0.permissions.contains("notify") }
                .map(\.type)
        )
        Task {
            await registryService.setAllObserved(deviceStableId: stableDeviceId, observed: observed, notifiableCharTypes: notifiableCharTypes)
            homeKitManager.refreshNotificationRegistrations()
        }
    }

    func renameService(stableServiceId: String, customName: String?) {
        Task {
            await registryService.setServiceCustomName(stableServiceId: stableServiceId, customName: customName)
        }
    }

    func setBulkEnabled(_ enabled: Bool) {
        let devices = filteredDevicesByRoom.flatMap(\.devices)
        Task {
            for device in devices {
                if let stableDeviceId = registryService.readStableDeviceId(device.id) {
                    await registryService.setAllEnabled(deviceStableId: stableDeviceId, enabled: enabled)
                }
            }
            if !enabled {
                homeKitManager.refreshNotificationRegistrations()
            }
        }
    }

    func setBulkObserved(_ observed: Bool) {
        let devices = filteredDevicesByRoom.flatMap(\.devices)
        Task {
            for device in devices {
                if let stableDeviceId = registryService.readStableDeviceId(device.id) {
                    let notifiableCharTypes = Set(
                        device.services.flatMap(\.characteristics)
                            .filter { $0.permissions.contains("notify") }
                            .map(\.type)
                    )
                    await registryService.setAllObserved(deviceStableId: stableDeviceId, observed: observed, notifiableCharTypes: notifiableCharTypes)
                }
            }
            homeKitManager.refreshNotificationRegistrations()
        }
    }

    /// Bulk enable/disable characteristics matching the selected characteristic type filters.
    func setBulkCharacteristicEnabled(_ enabled: Bool) {
        let charTypes = resolveSelectedCharacteristicTypes()
        guard !charTypes.isEmpty else { return }
        Task {
            await registryService.setBulkEnabled(forCharacteristicTypes: charTypes, enabled: enabled)
            if !enabled {
                homeKitManager.refreshNotificationRegistrations()
            }
        }
    }

    /// Bulk observe/unobserve characteristics matching the selected characteristic type filters.
    func setBulkCharacteristicObserved(_ observed: Bool) {
        let charTypes = resolveSelectedCharacteristicTypes()
        guard !charTypes.isEmpty else { return }
        // Collect all notifiable HomeKit characteristic IDs for the matching types
        let allDevices = filteredDevicesByRoom.flatMap(\.devices)
        let notifiableIds = Set(allDevices.flatMap(\.services).flatMap(\.characteristics)
            .filter { $0.permissions.contains("notify") }
            .map(\.id))
        Task {
            await registryService.setBulkObserved(forCharacteristicTypes: charTypes, observed: observed, notifiableHomeKitCharIds: notifiableIds)
            homeKitManager.refreshNotificationRegistrations()
        }
    }

    /// Resolves selected display names ("Battery Level", "Power", etc.) to HomeKit characteristic type UUIDs.
    private func resolveSelectedCharacteristicTypes() -> Set<String> {
        var result: Set<String> = []
        for displayName in selectedCharacteristicTypes {
            if let hkType = CharacteristicTypes.characteristicType(forName: displayName) {
                result.insert(hkType)
            }
        }
        return result
    }

    func getRoomName(for deviceId: String) -> String? {
        for group in devicesByRoom {
            if group.devices.contains(where: { $0.id == deviceId }) {
                return group.roomName
            }
        }
        return nil
    }

    func isEnabled(for device: DeviceModel) -> Bool {
        deviceConfigCache[device.id]?.enabled ?? true
    }

    func isObserved(for device: DeviceModel) -> Bool {
        deviceConfigCache[device.id]?.observed ?? false
    }

    private func updateErrorForStatus(_ status: HMHomeManagerAuthorizationStatus) {
        if status == .restricted {
            errorMessage = "HomeKit access is restricted on this device."
        } else if status.contains(.determined), !status.contains(.authorized) {
            errorMessage = "HomeKit access was denied. Grant access in System Settings > Privacy & Security > HomeKit."
        } else {
            errorMessage = nil
        }
    }
}
