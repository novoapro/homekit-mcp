import Foundation
import HomeKit
import Combine

class HomeKitManager: NSObject, ObservableObject, HomeKitManaging {
    @Published var homes: [HMHome] = []
    @Published var allAccessories: [HMAccessory] = []
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined
    @Published var isReady = false
    @Published var isReadingValues = false

    /// Cached device models, rebuilt only when accessories or characteristic values change.
    @Published private(set) var cachedDevices: [DeviceModel] = []
    /// O(1) device lookup by ID, rebuilt alongside cachedDevices.
    /// Access protected by `deviceLookupLock` for thread safety.
    private var deviceLookup: [String: DeviceModel] = [:]
    private let deviceLookupLock = NSLock()

    private let homeManager = HMHomeManager()
    private let loggingService: LoggingService
    private let webhookService: WebhookService
    private let storage: StorageService
    let configService: DeviceConfigurationService
    private var cancellables = Set<AnyCancellable>()

    /// Publishes every HomeKit state change. WorkflowEngine subscribes to this
    /// instead of being directly referenced — eliminates the bidirectional coupling.
    let stateChangePublisher = PassthroughSubject<StateChange, Never>()

    /// Coalesces rapid objectWillChange signals during bulk reads.
    private var uiUpdateWorkItem: DispatchWorkItem?

    /// Timer subscription for periodic state polling.
    private var pollingTimerCancellable: AnyCancellable?
    /// Tracks whether a poll cycle is currently in progress to prevent overlapping polls.
    private var isPolling = false

    init(loggingService: LoggingService, webhookService: WebhookService, configService: DeviceConfigurationService, storage: StorageService) {
        self.loggingService = loggingService
        self.webhookService = webhookService
        self.configService = configService
        self.storage = storage
        super.init()
        homeManager.delegate = self

        // Forward storage changes to trigger refreshes when settings change
        storage.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildDeviceCache()
                self?.startPollingIfEnabled()
            }
            .store(in: &cancellables)
    }

    /// Returns all devices from the cache. The cache is invalidated when accessories
    /// change or characteristic values are read.
    func getAllDevices() -> [DeviceModel] {
        cachedDevices
    }

    /// Returns devices grouped by room name. Devices without a room go under "Other".
    func getDevicesGroupedByRoom() -> [(roomName: String, devices: [DeviceModel])] {
        let grouped = Dictionary(grouping: cachedDevices) { $0.roomName ?? "Other" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (roomName: $0.key, devices: $0.value) }
    }

    func updateDevice(id: String, characteristicType: String, value: Any, serviceId: String? = nil) async throws {
        guard let accessory = allAccessories.first(where: { $0.uniqueIdentifier.uuidString == id }) else {
            throw HomeKitError.deviceNotFound
        }

        // Support both raw UUID and human-readable name for characteristic type
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType

        // When a serviceId is provided, target only that specific service
        let targetServices: [HMService]
        if let serviceId {
            guard let matchedService = accessory.services.first(where: { $0.uniqueIdentifier.uuidString == serviceId }) else {
                throw HomeKitError.serviceNotFound
            }
            targetServices = [matchedService]
        } else {
            targetServices = accessory.services
        }

        for service in targetServices {
            for characteristic in service.characteristics where characteristic.characteristicType == resolvedType {
                try await characteristic.writeValue(value)
                return
            }
        }

        throw HomeKitError.characteristicNotFound
    }

    /// O(1) device lookup by ID using the cached dictionary.
    /// Thread-safe: protected by deviceLookupLock.
    func getDeviceState(id: String) -> DeviceModel? {
        deviceLookupLock.lock()
        defer { deviceLookupLock.unlock() }
        return deviceLookup[id]
    }

    // MARK: - Device Cache

    /// Rebuilds the device model cache from the current HMAccessory list.
    /// Called when accessories change, characteristic values are read, or settings change.
    private func rebuildDeviceCache() {
        let devices = allAccessories.compactMap { accessory -> DeviceModel? in
            let services = accessory.services.compactMap { service -> ServiceModel? in
                guard service.serviceType != HMServiceTypeAccessoryInformation else { return nil }
                guard ServiceTypes.isSupported(service.serviceType) else { return nil }
                let characteristics = service.characteristics.compactMap { char -> CharacteristicModel? in
                    guard CharacteristicTypes.isSupported(char.characteristicType) else { return nil }

                    return CharacteristicModel(
                        id: char.uniqueIdentifier.uuidString,
                        type: char.characteristicType,
                        value: char.value.map { AnyCodable($0) },
                        format: char.metadata?.format ?? "unknown",
                        permissions: characteristicPermissions(char),
                        minValue: char.metadata?.minimumValue?.doubleValue,
                        maxValue: char.metadata?.maximumValue?.doubleValue,
                        stepValue: char.metadata?.stepValue?.doubleValue,
                        validValues: extractValidValues(for: char.characteristicType)
                    )
                }

                if characteristics.isEmpty { return nil }

                return ServiceModel(
                    id: service.uniqueIdentifier.uuidString,
                    name: service.name,
                    type: service.serviceType,
                    characteristics: characteristics
                )
            }

            if services.isEmpty { return nil }

            let formattedName = DeviceNameFormatter.format(
                deviceName: accessory.name,
                roomName: accessory.room?.name,
                hideRoomName: storage.readHideRoomName()
            )

            return DeviceModel(
                id: accessory.uniqueIdentifier.uuidString,
                name: formattedName,
                roomName: accessory.room?.name,
                categoryType: accessory.category.categoryType,
                services: services,
                isReachable: accessory.isReachable
            )
        }

        cachedDevices = devices
        deviceLookupLock.lock()
        deviceLookup = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        deviceLookupLock.unlock()
        objectWillChange.send()
    }

    // MARK: - Targeted Cache Update

    /// Patches only the changed characteristic in the cached device model graph.
    /// O(1) device lookup + O(S×C) service/characteristic scan on the single device.
    /// Falls back to a full `rebuildDeviceCache()` if the device is not yet cached.
    /// Must be called on MainActor.
    private func updateCachedCharacteristic(
        deviceId: String,
        serviceId: String,
        characteristicId: String,
        newValue: Any?
    ) {
        deviceLookupLock.lock()
        let existingDevice = deviceLookup[deviceId]
        deviceLookupLock.unlock()

        guard let device = existingDevice else {
            // Device not in cache yet — trigger a full rebuild.
            rebuildDeviceCache()
            return
        }

        // Rebuild only the affected service and characteristic (structs are value types).
        var patched = false
        let updatedServices: [ServiceModel] = device.services.map { service in
            guard service.id == serviceId else { return service }
            let updatedCharacteristics: [CharacteristicModel] = service.characteristics.map { char in
                guard char.id == characteristicId else { return char }
                patched = true
                return CharacteristicModel(
                    id: char.id,
                    type: char.type,
                    value: newValue.map { AnyCodable($0) },
                    format: char.format,
                    permissions: char.permissions,
                    minValue: char.minValue,
                    maxValue: char.maxValue,
                    stepValue: char.stepValue,
                    validValues: char.validValues
                )
            }
            return ServiceModel(id: service.id, name: service.name, type: service.type, characteristics: updatedCharacteristics)
        }

        guard patched else {
            // Characteristic not found in cache — fall back to full rebuild.
            rebuildDeviceCache()
            return
        }

        let updatedDevice = DeviceModel(
            id: device.id,
            name: device.name,
            roomName: device.roomName,
            categoryType: device.categoryType,
            services: updatedServices,
            isReachable: device.isReachable
        )

        // Patch the device in cachedDevices and deviceLookup.
        if let listIdx = cachedDevices.firstIndex(where: { $0.id == deviceId }) {
            cachedDevices[listIdx] = updatedDevice
        }
        deviceLookupLock.lock()
        deviceLookup[deviceId] = updatedDevice
        deviceLookupLock.unlock()
        objectWillChange.send()
    }

    // MARK: - UI Update Coalescing

    /// Coalesced UI update — waits for a brief quiet period before rebuilding the cache.
    /// This prevents hundreds of individual updates from each characteristic read.
    /// Safe to call from any thread — always dispatches to main.
    private func scheduleUIUpdate() {
        let update = { [weak self] in
            self?.uiUpdateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.rebuildDeviceCache()
            }
            self?.uiUpdateWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    // MARK: - State Polling

    /// Starts or restarts the polling timer based on current storage settings.
    /// Safe to call repeatedly — always tears down before rebuilding.
    private func startPollingIfEnabled() {
        pollingTimerCancellable?.cancel()
        pollingTimerCancellable = nil

        guard storage.readPollingEnabled() else {
            AppLogger.homeKit.info("State polling disabled")
            return
        }

        let interval = TimeInterval(max(storage.readPollingInterval(), 10))
        AppLogger.homeKit.info("State polling enabled with interval \(interval)s")

        pollingTimerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollForStateChanges()
            }
    }

    /// Reads all readable characteristics and compares against cached values.
    /// Fires the state-change pipeline for any differences (missed delegate callbacks).
    private func pollForStateChanges() {
        guard !isPolling else {
            AppLogger.homeKit.debug("Skipping poll — previous cycle still in progress")
            return
        }
        guard isReady else { return }

        isPolling = true
        let accessories = allAccessories

        var totalReads = 0
        var completedReads = 0
        let lock = NSLock()

        for accessory in accessories where accessory.isReachable {
            for service in accessory.services {
                guard ServiceTypes.isSupported(service.serviceType) else { continue }
                guard service.serviceType != HMServiceTypeAccessoryInformation else { continue }
                for characteristic in service.characteristics {
                    guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }
                    guard characteristic.properties.contains(HMCharacteristicPropertyReadable) else { continue }
                    totalReads += 1
                }
            }
        }

        guard totalReads > 0 else {
            isPolling = false
            return
        }

        for accessory in accessories where accessory.isReachable {
            let deviceId = accessory.uniqueIdentifier.uuidString

            for service in accessory.services {
                guard ServiceTypes.isSupported(service.serviceType) else { continue }
                guard service.serviceType != HMServiceTypeAccessoryInformation else { continue }

                let serviceId = service.uniqueIdentifier.uuidString

                for characteristic in service.characteristics {
                    guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }
                    guard characteristic.properties.contains(HMCharacteristicPropertyReadable) else { continue }

                    let charId = characteristic.uniqueIdentifier.uuidString

                    characteristic.readValue { [weak self] error in
                        guard let self else { return }

                        lock.lock()
                        completedReads += 1
                        let allDone = completedReads >= totalReads
                        lock.unlock()

                        if let error = error {
                            AppLogger.homeKit.debug("Poll: failed to read \(characteristic.characteristicType) on \(accessory.name): \(error)")
                            if allDone { self.isPolling = false }
                            return
                        }

                        self.compareAndEmitIfChanged(
                            accessory: accessory,
                            service: service,
                            characteristic: characteristic,
                            deviceId: deviceId,
                            serviceId: serviceId,
                            charId: charId
                        )

                        if allDone {
                            self.isPolling = false
                        }
                    }
                }
            }
        }
    }

    /// Compares the freshly-read characteristic value against the cached value.
    /// If different, runs the full state-change pipeline (log, webhook, publisher, cache update).
    private func compareAndEmitIfChanged(
        accessory: HMAccessory,
        service: HMService,
        characteristic: HMCharacteristic,
        deviceId: String,
        serviceId: String,
        charId: String
    ) {
        let newValue = characteristic.value

        // Look up cached value
        deviceLookupLock.lock()
        let cachedDevice = deviceLookup[deviceId]
        deviceLookupLock.unlock()

        let cachedValue: Any? = cachedDevice?.services
            .first(where: { $0.id == serviceId })?
            .characteristics
            .first(where: { $0.id == charId })?
            .value?.value

        // Both nil means no change
        if cachedValue == nil && newValue == nil { return }

        // Compare using string representation (AnyCodable values lack Equatable)
        let oldStr = cachedValue.map { "\($0)" } ?? "nil"
        let newStr = newValue.map { "\($0)" } ?? "nil"
        guard oldStr != newStr else { return }

        // Mismatch detected: a delegate callback was missed
        AppLogger.homeKit.warning(
            "Poll detected missed state change: \(accessory.name) \(CharacteristicTypes.displayName(for: characteristic.characteristicType)): \(oldStr) -> \(newStr)"
        )

        let serviceName = ServiceTypes.displayName(for: service.serviceType)

        Task {
            let config = await self.configService.getConfig(
                deviceId: deviceId,
                serviceId: serviceId,
                characteristicId: charId
            )

            let formattedName = DeviceNameFormatter.format(
                deviceName: accessory.name,
                roomName: accessory.room?.name,
                hideRoomName: self.storage.readHideRoomName()
            )

            let logEntry = StateChangeLog(
                id: UUID(),
                timestamp: Date(),
                deviceId: deviceId,
                deviceName: formattedName,
                serviceName: serviceName,
                characteristicType: characteristic.characteristicType,
                oldValue: cachedValue.map { AnyCodable($0) },
                newValue: newValue.map { AnyCodable($0) },
                category: .stateChange
            )

            let change = StateChange(
                deviceId: deviceId,
                deviceName: formattedName,
                serviceId: serviceId,
                serviceName: serviceName,
                characteristicType: characteristic.characteristicType,
                oldValue: cachedValue,
                newValue: newValue
            )

            if self.storage.readDeviceStateLoggingEnabled() {
                await self.loggingService.logEntry(logEntry)
            }

            if config.webhookEnabled {
                await self.webhookService.sendStateChange(change)
            }

            await MainActor.run {
                self.stateChangePublisher.send(change)
                self.updateCachedCharacteristic(
                    deviceId: deviceId,
                    serviceId: serviceId,
                    characteristicId: charId,
                    newValue: newValue
                )
            }
        }
    }

    // MARK: - Helpers

    private func characteristicPermissions(_ characteristic: HMCharacteristic) -> [String] {
        var perms: [String] = []
        if characteristic.properties.contains(HMCharacteristicPropertyReadable) { perms.append("read") }
        if characteristic.properties.contains(HMCharacteristicPropertyWritable) { perms.append("write") }
        if characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) { perms.append("notify") }
        return perms
    }

    /// Extracts valid values for discrete characteristics (door state, lock state, etc.)
    /// Returns nil if the characteristic doesn't have defined discrete values.
    private func extractValidValues(for characteristicType: String) -> [Int]? {
        switch characteristicType {
        case HMCharacteristicTypeCurrentDoorState,
             HMCharacteristicTypeTargetDoorState:
            return [0, 1, 2, 3, 4]  // Open, Closed, Opening, Closing, Stopped

        case HMCharacteristicTypeCurrentLockMechanismState,
             HMCharacteristicTypeTargetLockMechanismState:
            return [0, 1, 2, 3]  // Unsecured, Secured, Jammed, Unknown

        case HMCharacteristicTypeCurrentHeatingCooling,
             HMCharacteristicTypeTargetHeatingCooling:
            return [0, 1, 2, 3]  // Off, Heat, Cool, Auto

        case HMCharacteristicTypeCurrentFanState,
             HMCharacteristicTypeTargetFanState:
            return [0, 1, 2]  // Inactive, Active, Jammed

        default:
            return nil
        }
    }

    private func registerForNotifications() {
        for home in homes {
            for accessory in home.accessories {
                accessory.delegate = self
                for service in accessory.services {
                    guard ServiceTypes.isSupported(service.serviceType) else { continue }
                    for characteristic in service.characteristics {
                        guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }

                        if characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) {
                            characteristic.enableNotification(true) { error in
                                if let error = error {
                                    AppLogger.homeKit.warning("Failed to enable notification for \(characteristic.characteristicType): \(error)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Read current values for all readable characteristics on all accessories.
    /// Uses a concurrent counter to track completion and coalesces UI updates.
    private func readAllCharacteristicValues() {
        // Snapshot the accessories array to avoid races with HomeKit delegate callbacks
        let accessories = allAccessories

        var totalReads = 0
        var completedReads = 0
        let lock = NSLock()

        for accessory in accessories where accessory.isReachable {
            for service in accessory.services {
                guard ServiceTypes.isSupported(service.serviceType) else { continue }
                for characteristic in service.characteristics {
                    guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }

                    if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                        totalReads += 1
                    }
                }
            }
        }

        guard totalReads > 0 else {
            isReadingValues = false
            isReady = true
            rebuildDeviceCache()
            return
        }

        isReadingValues = true
        isReady = true
        // Build initial cache with stale/nil values while reads happen
        rebuildDeviceCache()

        for accessory in accessories where accessory.isReachable {
            for service in accessory.services {
                guard ServiceTypes.isSupported(service.serviceType) else { continue }
                for characteristic in service.characteristics {
                    guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }

                    if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                        characteristic.readValue { [weak self] error in
                            guard let self else { return }
                            if let error = error {
                                AppLogger.homeKit.warning("Failed to read \(characteristic.characteristicType) on \(accessory.name): \(error)")
                            }

                            lock.lock()
                            completedReads += 1
                            let allDone = completedReads >= totalReads
                            lock.unlock()

                            // Coalesce cache rebuilds — don't fire for every single read
                            self.scheduleUIUpdate()

                            if allDone {
                                DispatchQueue.main.async {
                                    self.isReadingValues = false
                                    self.startPollingIfEnabled()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func refreshAccessories() {
        allAccessories = homes.flatMap { $0.accessories }
        for home in homes {
            home.delegate = self
        }
        registerForNotifications()
        readAllCharacteristicValues()
    }
}

// MARK: - HMHomeManagerDelegate
extension HomeKitManager: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        DispatchQueue.main.async {
            self.homes = manager.homes
            self.refreshAccessories()
        }
    }

    func homeManager(_ manager: HMHomeManager, didAdd home: HMHome) {
        DispatchQueue.main.async {
            self.homes = manager.homes
            self.refreshAccessories()
        }
    }

    func homeManager(_ manager: HMHomeManager, didRemove home: HMHome) {
        DispatchQueue.main.async {
            self.homes = manager.homes
            self.refreshAccessories()
        }
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }
}

// MARK: - HMHomeDelegate
extension HomeKitManager: HMHomeDelegate {
    func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        DispatchQueue.main.async {
            self.refreshAccessories()
        }
    }

    func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        DispatchQueue.main.async {
            self.refreshAccessories()
        }
    }

    func home(_ home: HMHome, didUpdate room: HMRoom, for accessory: HMAccessory) {
        DispatchQueue.main.async {
            self.rebuildDeviceCache()
        }
    }

    func home(_ home: HMHome, didAdd room: HMRoom) {
        DispatchQueue.main.async {
            self.rebuildDeviceCache()
        }
    }

    func home(_ home: HMHome, didRemove room: HMRoom) {
        DispatchQueue.main.async {
            self.rebuildDeviceCache()
        }
    }

    func home(_ home: HMHome, didUpdateNameFor room: HMRoom) {
        DispatchQueue.main.async {
            self.rebuildDeviceCache()
        }
    }
}

// MARK: - HMAccessoryDelegate
extension HomeKitManager: HMAccessoryDelegate {
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        let deviceId = accessory.uniqueIdentifier.uuidString
        let serviceId = service.uniqueIdentifier.uuidString

        guard ServiceTypes.isSupported(service.serviceType) else { return }

        let charId = characteristic.uniqueIdentifier.uuidString
        let serviceName = ServiceTypes.displayName(for: service.serviceType)

        guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { return }

        Task {
            let config = await configService.getConfig(
                deviceId: deviceId,
                serviceId: serviceId,
                characteristicId: charId
            )

            let value = characteristic.value

            let formattedName = DeviceNameFormatter.format(
                deviceName: accessory.name,
                roomName: accessory.room?.name,
                hideRoomName: storage.readHideRoomName()
            )

            let logEntry = StateChangeLog(
                id: UUID(),
                timestamp: Date(),
                deviceId: accessory.uniqueIdentifier.uuidString,
                deviceName: formattedName,
                serviceName: ServiceTypes.displayName(for: service.serviceType),
                characteristicType: characteristic.characteristicType,
                oldValue: nil,
                newValue: value.map { AnyCodable($0) },
                category: .stateChange
            )

            let change = StateChange(
                deviceId: deviceId,
                deviceName: formattedName,
                serviceId: serviceId,
                serviceName: serviceName,
                characteristicType: characteristic.characteristicType,
                oldValue: nil,
                newValue: value
            )

            if self.storage.readDeviceStateLoggingEnabled() {
                await loggingService.logEntry(logEntry)
            }

            if config.webhookEnabled {
                await webhookService.sendStateChange(change)
            }

            // Publish state change for any subscribers (e.g. WorkflowEngine).
            // Using a publisher decouples HomeKitManager from WorkflowEngine entirely.
            // Use targeted cache update — patch only the affected characteristic instead
            // of rebuilding the entire O(A×S×C) device model graph.
            await MainActor.run {
                self.stateChangePublisher.send(change)
                self.updateCachedCharacteristic(
                    deviceId: deviceId,
                    serviceId: serviceId,
                    characteristicId: charId,
                    newValue: value
                )
            }
        }
    }

    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        DispatchQueue.main.async {
            self.rebuildDeviceCache()
        }
    }
}

// MARK: - Errors
enum HomeKitError: LocalizedError {
    case deviceNotFound
    case serviceNotFound
    case characteristicNotFound
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Device not found"
        case .serviceNotFound: return "Service not found"
        case .characteristicNotFound: return "Characteristic not found"
        case .notAuthorized: return "HomeKit access not authorized"
        }
    }
}
