import Foundation
import HomeKit
import Combine

/// Lightweight event for broadcasting a single characteristic value change via WebSocket.
struct CharacteristicValueChange {
    let deviceId: String        // stable registry ID
    let serviceId: String       // stable registry ID
    let characteristicId: String // stable registry ID
    let characteristicType: String
    let value: Any?
    let oldValue: Any?
    let timestamp: Date
}

class HomeKitManager: NSObject, ObservableObject, HomeKitManaging {
    @Published var homes: [HMHome] = []
    @Published var allAccessories: [HMAccessory] = []
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = []
    @Published var isReady = false
    @Published var isReadingValues = false

    /// Cached device models, rebuilt only when accessories or characteristic values change.
    @Published private(set) var cachedDevices: [DeviceModel] = []
    /// Cached scene models, rebuilt when action sets change.
    @Published private(set) var cachedScenes: [SceneModel] = []
    /// O(1) device lookup by ID, rebuilt alongside cachedDevices.
    /// Access protected by `deviceLookupLock` for thread safety.
    private var deviceLookup: [String: DeviceModel] = [:]
    private let deviceLookupLock = NSLock()

    private let homeManager = HMHomeManager()
    private let loggingService: LoggingService
    private let webhookService: WebhookService
    private let storage: StorageService
    var deviceRegistryService: DeviceRegistryService?
    private var cancellables = Set<AnyCancellable>()

    /// Publishes every HomeKit state change. AutomationEngine subscribes to this
    /// instead of being directly referenced — eliminates the bidirectional coupling.
    let stateChangePublisher = PassthroughSubject<StateChange, Never>()

    /// Publishes granular characteristic value changes for WebSocket broadcast (gated by observed setting).
    let characteristicValueChangePublisher = PassthroughSubject<CharacteristicValueChange, Never>()

    /// Coalesces rapid objectWillChange signals during bulk reads.
    private var uiUpdateWorkItem: DispatchWorkItem?

    /// Timer subscription for periodic state polling.
    private var pollingTimerCancellable: AnyCancellable?
    /// Tracks whether a poll cycle is currently in progress to prevent overlapping polls.
    private var isPolling = false

    init(loggingService: LoggingService, webhookService: WebhookService, storage: StorageService) {
        self.loggingService = loggingService
        self.webhookService = webhookService
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

    // MARK: - Scene Access

    /// Returns all scenes from the cache.
    func getAllScenes() -> [SceneModel] {
        cachedScenes
    }

    /// Returns a single scene by ID. Accepts both stable registry IDs and HomeKit UUIDs.
    func getScene(id: String) -> SceneModel? {
        if let scene = cachedScenes.first(where: { $0.id == id }) { return scene }
        // Try resolving as a stable registry ID → HomeKit UUID
        if let hkId = deviceRegistryService?.readHomeKitSceneId(id) {
            return cachedScenes.first(where: { $0.id == hkId })
        }
        return nil
    }

    /// Executes a HomeKit scene (action set) by its ID. Accepts both stable and HomeKit IDs.
    func executeScene(id: String) async throws {
        let resolvedId = deviceRegistryService?.readHomeKitSceneId(id) ?? id
        guard let (home, actionSet) = findActionSet(id: resolvedId) else {
            throw HomeKitError.sceneNotFound
        }

        let sceneName = actionSet.name
        AppLogger.scene.info("Executing scene: \(sceneName) (\(id))")

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                home.executeActionSet(actionSet) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            AppLogger.scene.info("Scene executed successfully: \(sceneName)")

            let logEntry = StateChangeLog.sceneExecution(
                sceneId: id,
                sceneName: sceneName,
                summary: "Execute scene: \(sceneName)"
            )
            await loggingService.logEntry(logEntry)

            let change = StateChange(
                deviceId: id,
                deviceName: sceneName,
                characteristicType: "scene_execution",
                oldValue: nil,
                newValue: true
            )
            await webhookService.sendStateChange(change)

            rebuildSceneCache()
        } catch {
            AppLogger.scene.error("Scene execution failed: \(sceneName) - \(error.localizedDescription)")

            let logEntry = StateChangeLog.sceneError(
                sceneId: id,
                sceneName: sceneName,
                errorDetails: error.localizedDescription,
                summary: "Execute scene: \(sceneName)"
            )
            await loggingService.logEntry(logEntry)

            throw error
        }
    }

    /// Finds the HMActionSet and its parent HMHome by scene ID.
    private func findActionSet(id: String) -> (HMHome, HMActionSet)? {
        for home in homes {
            if let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == id }) {
                return (home, actionSet)
            }
        }
        return nil
    }

    /// Returns devices grouped by room name. Devices without a room go under "Other".
    func getDevicesGroupedByRoom() -> [(roomName: String, devices: [DeviceModel])] {
        let grouped = Dictionary(grouping: cachedDevices) { $0.roomName ?? "Other" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (roomName: $0.key, devices: $0.value) }
    }

    func updateDevice(id: String, characteristicType: String, value: Any, serviceId: String? = nil) async throws {
        // Resolve ID through registry: accept both stable IDs and HomeKit UUIDs
        let resolvedDeviceId = resolveDeviceId(id)
        let resolvedServiceId = serviceId.flatMap { resolveServiceId($0) } ?? serviceId

        guard let accessory = allAccessories.first(where: { $0.uniqueIdentifier.uuidString == resolvedDeviceId }) else {
            throw HomeKitError.deviceNotFound
        }

        // Support both raw UUID and human-readable name for characteristic type
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType

        // When a serviceId is provided, target only that specific service
        let targetServices: [HMService]
        if let resolvedServiceId {
            guard let matchedService = accessory.services.first(where: { $0.uniqueIdentifier.uuidString == resolvedServiceId }) else {
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

    /// O(1) device lookup by ID. Accepts both stable registry IDs and HomeKit UUIDs.
    /// Thread-safe: protected by deviceLookupLock.
    func getDeviceState(id: String) -> DeviceModel? {
        deviceLookupLock.lock()
        defer { deviceLookupLock.unlock() }
        if let device = deviceLookup[id] { return device }
        // Try resolving as a stable registry ID → HomeKit UUID
        let hkId = deviceRegistryService?.readHomeKitDeviceId(id)
        return hkId.flatMap { deviceLookup[$0] }
    }

    /// Resolves an ID that may be either a stable registry ID or a HomeKit UUID to a HomeKit UUID.
    func resolveDeviceId(_ id: String) -> String {
        deviceRegistryService?.readHomeKitDeviceId(id) ?? id
    }

    /// Resolves a service ID that may be either a stable registry ID or a HomeKit UUID.
    func resolveServiceId(_ id: String) -> String {
        deviceRegistryService?.readHomeKitServiceId(id) ?? id
    }

    // MARK: - Device Cache

    /// Rebuilds the device model cache from the current HMAccessory list.
    /// Called when accessories change, characteristic values are read, or settings change.
    private func rebuildDeviceCache(suppressRegistrySync: Bool = false) {
        let devices = allAccessories.compactMap { accessory -> DeviceModel? in
            // Read hardware identity from HMAccessory properties (iOS 11+)
            let manufacturer = accessory.manufacturer
            let model = accessory.model
            let firmwareRevision = accessory.firmwareVersion
            // Serial number has no replacement property; read from characteristic
            var serialNumber: String?
            if let infoService = accessory.services.first(where: { $0.serviceType == HMServiceTypeAccessoryInformation }) {
                for char in infoService.characteristics where char.characteristicType == "00000030-0000-1000-8000-0026BB765291" {
                    serialNumber = char.value as? String
                }
            }

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
                        units: extractUnits(from: char.metadata),
                        permissions: characteristicPermissions(char),
                        minValue: char.metadata?.minimumValue?.doubleValue,
                        maxValue: char.metadata?.maximumValue?.doubleValue,
                        stepValue: char.metadata?.stepValue?.doubleValue,
                        validValues: extractValidValues(for: char)
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
                isReachable: accessory.isReachable,
                manufacturer: manufacturer,
                model: model,
                serialNumber: serialNumber,
                firmwareRevision: firmwareRevision
            )
        }

        cachedDevices = devices
        deviceLookupLock.lock()
        deviceLookup = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        deviceLookupLock.unlock()
        objectWillChange.send()

        // Sync the device registry with the latest HomeKit state (skip for value-only cache patches)
        if !suppressRegistrySync, let registry = deviceRegistryService {
            let snapshot = devices
            Task { await registry.syncDevices(snapshot) }
        }
    }

    // MARK: - Scene Cache

    /// Rebuilds the scene model cache from all homes' action sets.
    private func rebuildSceneCache() {
        var scenes: [SceneModel] = []
        for home in homes {
            for actionSet in home.actionSets {
                let actions = actionSet.actions.compactMap { action -> SceneActionModel? in
                    guard let writeAction = action as? HMCharacteristicWriteAction<NSCopying> else { return nil }
                    let characteristic = writeAction.characteristic
                    guard let service = characteristic.service,
                          let accessory = service.accessory else { return nil }
                    return SceneActionModel(
                        id: characteristic.uniqueIdentifier.uuidString,
                        deviceId: accessory.uniqueIdentifier.uuidString,
                        deviceName: accessory.name,
                        serviceName: service.name,
                        characteristicType: CharacteristicTypes.displayName(for: characteristic.characteristicType),
                        targetValue: AnyCodable(writeAction.targetValue)
                    )
                }
                let scene = SceneModel(
                    id: actionSet.uniqueIdentifier.uuidString,
                    name: actionSet.name,
                    type: Self.actionSetTypeDisplayName(actionSet.actionSetType),
                    isExecuting: actionSet.isExecuting,
                    actions: actions
                )
                scenes.append(scene)
            }
        }
        cachedScenes = scenes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        objectWillChange.send()

        // Sync the scene registry
        if let registry = deviceRegistryService {
            let snapshot = cachedScenes
            Task { await registry.syncScenes(snapshot) }
        }
    }

    /// Maps HMActionSetType constants to human-readable names.
    private static func actionSetTypeDisplayName(_ type: String) -> String {
        switch type {
        case HMActionSetTypeUserDefined: return "User Defined"
        case HMActionSetTypeWakeUp: return "Wake Up"
        case HMActionSetTypeSleep: return "Sleep"
        case HMActionSetTypeHomeDeparture: return "Home Departure"
        case HMActionSetTypeHomeArrival: return "Home Arrival"
        case HMActionSetTypeTriggerOwned: return "Trigger Owned"
        default: return type
        }
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
            // Device not in cache yet — trigger a full rebuild (suppress registry sync since topology hasn't changed).
            rebuildDeviceCache(suppressRegistrySync: true)
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
                    units: char.units,
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
            // Characteristic not found in cache — fall back to full rebuild (suppress registry sync since topology hasn't changed).
            rebuildDeviceCache(suppressRegistrySync: true)
            return
        }

        let updatedDevice = DeviceModel(
            id: device.id,
            name: device.name,
            roomName: device.roomName,
            categoryType: device.categoryType,
            services: updatedServices,
            isReachable: device.isReachable,
            manufacturer: device.manufacturer,
            model: device.model,
            serialNumber: device.serialNumber,
            firmwareRevision: device.firmwareRevision
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

    /// Maximum number of concurrent HomeKit characteristic reads during polling.
    /// Limits backpressure on the HomeKit daemon and reduces main-thread contention.
    private static let maxConcurrentReads = 20

    /// Reads all readable characteristics and compares against cached values.
    /// Fires the state-change pipeline for any differences (missed delegate callbacks).
    /// Uses a semaphore to limit concurrent reads and batches main-thread comparisons.
    private func pollForStateChanges() {
        guard !isPolling else {
            AppLogger.homeKit.debug("Skipping poll — previous cycle still in progress")
            return
        }
        guard isReady else { return }

        isPolling = true
        let accessories = allAccessories

        // Collect all readable characteristics upfront
        struct PollItem {
            let accessory: HMAccessory
            let service: HMService
            let characteristic: HMCharacteristic
            let deviceId: String
            let serviceId: String
            let charId: String
        }
        var items: [PollItem] = []

        for accessory in accessories where accessory.isReachable {
            let deviceId = accessory.uniqueIdentifier.uuidString
            for service in accessory.services {
                guard ServiceTypes.isSupported(service.serviceType) else { continue }
                guard service.serviceType != HMServiceTypeAccessoryInformation else { continue }
                let serviceId = service.uniqueIdentifier.uuidString
                for characteristic in service.characteristics {
                    guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }
                    guard characteristic.properties.contains(HMCharacteristicPropertyReadable) else { continue }
                    items.append(PollItem(
                        accessory: accessory, service: service, characteristic: characteristic,
                        deviceId: deviceId, serviceId: serviceId,
                        charId: characteristic.uniqueIdentifier.uuidString
                    ))
                }
            }
        }

        guard !items.isEmpty else {
            isPolling = false
            return
        }

        let semaphore = DispatchSemaphore(value: Self.maxConcurrentReads)
        let group = DispatchGroup()
        let pollQueue = DispatchQueue(label: "com.mnplab.compai-home.poll", qos: .utility)

        // Collect changed items and dispatch to main thread in a single batch
        let changedLock = NSLock()
        var changedItems: [PollItem] = []

        for item in items {
            group.enter()
            pollQueue.async {
                semaphore.wait()
                item.characteristic.readValue { [weak self] error in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    guard self != nil else { return }

                    if error != nil { return }

                    changedLock.lock()
                    changedItems.append(item)
                    changedLock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            for item in changedItems {
                self.compareAndEmitIfChanged(
                    accessory: item.accessory,
                    service: item.service,
                    characteristic: item.characteristic,
                    deviceId: item.deviceId,
                    serviceId: item.serviceId,
                    charId: item.charId
                )
            }
            self.isPolling = false
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
        let settings = deviceRegistryService?.readCharacteristicSettings(forHomeKitCharId: charId)
        let isObserved = settings?.observed ?? false

        Task {
            let formattedName = DeviceNameFormatter.format(
                deviceName: accessory.name,
                roomName: accessory.room?.name,
                hideRoomName: self.storage.readHideRoomName()
            )

            let roomName = accessory.room?.name

            // Convert temperature values for logging and external broadcasts
            let isTemp = TemperatureConversion.isTemperatureCharacteristic(characteristic.characteristicType)
            let convertedOld: AnyCodable? = cachedValue.flatMap { v in
                if isTemp, let d = v as? Double { return AnyCodable(TemperatureConversion.convertFromCelsius(d)) }
                if isTemp, let i = v as? Int { return AnyCodable(TemperatureConversion.convertFromCelsius(Double(i))) }
                return AnyCodable(v)
            }
            let convertedNew: AnyCodable? = newValue.flatMap { v in
                if isTemp, let d = v as? Double { return AnyCodable(TemperatureConversion.convertFromCelsius(d)) }
                if isTemp, let i = v as? Int { return AnyCodable(TemperatureConversion.convertFromCelsius(Double(i))) }
                return AnyCodable(v)
            }

            let unit = CharacteristicTypes.unitForCharacteristicType(characteristic.characteristicType)

            let logEntry = StateChangeLog.stateChange(
                deviceId: deviceId,
                deviceName: formattedName,
                roomName: roomName,
                serviceName: serviceName,
                characteristicType: characteristic.characteristicType,
                oldValue: convertedOld,
                newValue: convertedNew,
                unit: unit
            )

            // Translate to stable registry IDs for published StateChange
            let stableDeviceId = self.deviceRegistryService?.readStableDeviceId(deviceId) ?? deviceId
            let stableServiceId = self.deviceRegistryService?.readStableServiceId(serviceId) ?? serviceId

            let change = StateChange(
                deviceId: stableDeviceId,
                deviceName: formattedName,
                roomName: roomName,
                serviceId: stableServiceId,
                serviceName: serviceName,
                characteristicType: characteristic.characteristicType,
                oldValue: cachedValue,
                newValue: newValue
            )

            if isObserved {
                if self.storage.readLoggingEnabled() && self.storage.readDeviceStateLoggingEnabled() {
                    await self.loggingService.logEntry(logEntry)
                }

                await self.webhookService.sendStateChange(change)

                let stableCharId = self.deviceRegistryService?.readStableCharacteristicId(charId) ?? charId
                self.characteristicValueChangePublisher.send(CharacteristicValueChange(
                    deviceId: stableDeviceId,
                    serviceId: stableServiceId,
                    characteristicId: stableCharId,
                    characteristicType: characteristic.characteristicType,
                    value: newValue,
                    oldValue: change.oldValue,
                    timestamp: Date()
                ))
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

    /// Maps HMCharacteristicMetadata units to a human-readable string.
    private func extractUnits(from metadata: HMCharacteristicMetadata?) -> String? {
        guard let units = metadata?.units else { return nil }
        switch units {
        case HMCharacteristicMetadataUnitsCelsius: return "celsius"
        case HMCharacteristicMetadataUnitsFahrenheit: return "fahrenheit"
        case HMCharacteristicMetadataUnitsPercentage: return "%"
        case HMCharacteristicMetadataUnitsArcDegree: return "arcdegrees"
        case HMCharacteristicMetadataUnitsSeconds: return "seconds"
        case HMCharacteristicMetadataUnitsLux: return "lux"
        case HMCharacteristicMetadataUnitsPartsPerMillion: return "ppm"
        case HMCharacteristicMetadataUnitsMicrogramsPerCubicMeter: return "μg/m³"
        default: return units
        }
    }

    /// Extracts valid values for discrete characteristics.
    /// Prefers device-reported metadata (respects device-specific subsets),
    /// falls back to well-known HAP defaults by characteristic type.
    private func extractValidValues(for characteristic: HMCharacteristic) -> [Int]? {
        // 1. Prefer metadata.validValues from the actual device (device-specific subset)
        if let metadataValues = characteristic.metadata?.validValues, !metadataValues.isEmpty {
            return metadataValues.map { $0.intValue }.sorted()
        }

        // 2. Fall back to well-known HAP defaults by characteristic type
        return Self.defaultValidValues[characteristic.characteristicType]
    }

    /// Well-known valid value sets from the HAP specification, keyed by characteristic type.
    private static let defaultValidValues: [String: [Int]] = {
        var map: [String: [Int]] = [:]

        map[HMCharacteristicTypeCurrentDoorState] = [0, 1, 2, 3, 4]
        map[HMCharacteristicTypeTargetDoorState] = [0, 1]
        map[HMCharacteristicTypeCurrentLockMechanismState] = [0, 1, 2, 3]
        map[HMCharacteristicTypeTargetLockMechanismState] = [0, 1]
        map[HMCharacteristicTypeCurrentHeatingCooling] = [0, 1, 2]
        map[HMCharacteristicTypeTargetHeatingCooling] = [0, 1, 2, 3]
        map[HMCharacteristicTypeCurrentFanState] = [0, 1, 2]
        map[HMCharacteristicTypeTargetFanState] = [0, 1]
        map[HMCharacteristicTypeActive] = [0, 1]
        map[HMCharacteristicTypeContactState] = [0, 1]
        map[HMCharacteristicTypeOccupancyDetected] = [0, 1]
        map[HMCharacteristicTypeSmokeDetected] = [0, 1]
        map[HMCharacteristicTypeCarbonMonoxideDetected] = [0, 1]
        map[HMCharacteristicTypeStatusLowBattery] = [0, 1]
        map[HMCharacteristicTypeChargingState] = [0, 1, 2]
        map[HMCharacteristicTypePositionState] = [0, 1, 2]
        map[HMCharacteristicTypeTemperatureUnits] = [0, 1]
        map[HMCharacteristicTypeInUse] = [0, 1]
        map[HMCharacteristicTypeValveType] = [0, 1, 2, 3]
        map[HMCharacteristicTypeProgramMode] = [0, 1, 2]
        map[HMCharacteristicTypeIsConfigured] = [0, 1]
        map[HMCharacteristicTypeInputEvent] = [0, 1, 2]
        map[HMCharacteristicTypeStatusFault] = [0, 1]
        map[HMCharacteristicTypeStatusTampered] = [0, 1]
        map[HMCharacteristicTypeObstructionDetected] = [0, 1]

        return map
    }()

    private func registerForNotifications() {
        for home in homes {
            for accessory in home.accessories {
                accessory.delegate = self
                for service in accessory.services {
                    guard ServiceTypes.isSupported(service.serviceType) else { continue }
                    for characteristic in service.characteristics {
                        guard CharacteristicTypes.isSupported(characteristic.characteristicType) else { continue }
                        guard characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) else { continue }

                        let charId = characteristic.uniqueIdentifier.uuidString
                        let settings = deviceRegistryService?.readCharacteristicSettings(forHomeKitCharId: charId)
                        let shouldObserve = settings?.observed ?? false

                        characteristic.enableNotification(shouldObserve) { error in
                            if let error = error {
                                AppLogger.homeKit.warning("Failed to \(shouldObserve ? "enable" : "disable") notification for \(characteristic.characteristicType): \(error)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Re-registers HomeKit notifications based on current observed settings.
    /// Call after changing observed settings to dynamically toggle subscriptions.
    func refreshNotificationRegistrations() {
        registerForNotifications()
    }

    /// Triggers a full rebuild of device and scene caches, which in turn
    /// syncs them to the device registry. Use after clearing the registry
    /// to re-import all devices with new stable IDs.
    func resyncAllDevices() {
        rebuildDeviceCache()
        rebuildSceneCache()
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

        // Read serial number characteristic so hardware identity is available when the cache rebuilds.
        // (manufacturer, model, firmwareVersion are read from HMAccessory properties directly)
        let serialNumberType = "00000030-0000-1000-8000-0026BB765291"
        for accessory in accessories where accessory.isReachable {
            if let infoService = accessory.services.first(where: { $0.serviceType == HMServiceTypeAccessoryInformation }) {
                for char in infoService.characteristics where char.characteristicType == serialNumberType {
                    if char.properties.contains(HMCharacteristicPropertyReadable) {
                        char.readValue { error in
                            if let error {
                                AppLogger.homeKit.warning("Failed to read serial number on \(accessory.name): \(error)")
                            }
                        }
                    }
                }
            }
        }

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
                            DispatchQueue.main.async {
                                self.scheduleUIUpdate()
                                if allDone {
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
        rebuildSceneCache()
    }
}

// MARK: - HMHomeManagerDelegate
extension HomeKitManager: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
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

    // MARK: - Scene Delegate

    func home(_ home: HMHome, didAdd actionSet: HMActionSet) {
        DispatchQueue.main.async {
            self.rebuildSceneCache()
        }
    }

    func home(_ home: HMHome, didRemove actionSet: HMActionSet) {
        DispatchQueue.main.async {
            self.rebuildSceneCache()
        }
    }

    func home(_ home: HMHome, didUpdateNameFor actionSet: HMActionSet) {
        DispatchQueue.main.async {
            self.rebuildSceneCache()
        }
    }

    func home(_ home: HMHome, didUpdateActionsFor actionSet: HMActionSet) {
        DispatchQueue.main.async {
            self.rebuildSceneCache()
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

        let settings = deviceRegistryService?.readCharacteristicSettings(forHomeKitCharId: charId)
        let isObserved = settings?.observed ?? false

        Task {
            let value = characteristic.value

            // Look up cached value BEFORE updating cache so we can detect actual changes
            self.deviceLookupLock.lock()
            let cachedDevice = self.deviceLookup[deviceId]
            self.deviceLookupLock.unlock()

            let cachedValue: Any? = cachedDevice?.services
                .first(where: { $0.id == serviceId })?
                .characteristics
                .first(where: { $0.id == charId })?
                .value?.value

            // Skip broadcast if value hasn't actually changed (HomeKit sometimes emits spurious callbacks)
            let oldStr = cachedValue.map { "\($0)" } ?? "nil"
            let newStr = value.map { "\($0)" } ?? "nil"
            if oldStr == newStr {
                return
            }

            let formattedName = DeviceNameFormatter.format(
                deviceName: accessory.name,
                roomName: accessory.room?.name,
                hideRoomName: storage.readHideRoomName()
            )

            let roomName = accessory.room?.name

            // Convert temperature values for logging (persisted in user's preferred unit)
            let isTemp = TemperatureConversion.isTemperatureCharacteristic(characteristic.characteristicType)
            let convertedOld: AnyCodable? = cachedValue.flatMap { v in
                if isTemp, let d = v as? Double { return AnyCodable(TemperatureConversion.convertFromCelsius(d)) }
                if isTemp, let i = v as? Int { return AnyCodable(TemperatureConversion.convertFromCelsius(Double(i))) }
                return AnyCodable(v)
            }
            let convertedNew: AnyCodable? = value.flatMap { v in
                if isTemp, let d = v as? Double { return AnyCodable(TemperatureConversion.convertFromCelsius(d)) }
                if isTemp, let i = v as? Int { return AnyCodable(TemperatureConversion.convertFromCelsius(Double(i))) }
                return AnyCodable(v)
            }

            let unit = CharacteristicTypes.unitForCharacteristicType(characteristic.characteristicType)

            let logEntry = StateChangeLog.stateChange(
                deviceId: accessory.uniqueIdentifier.uuidString,
                deviceName: formattedName,
                roomName: roomName,
                serviceName: ServiceTypes.displayName(for: service.serviceType),
                characteristicType: characteristic.characteristicType,
                oldValue: convertedOld,
                newValue: convertedNew,
                unit: unit
            )

            // Translate to stable registry IDs for published StateChange.
            // Automations and triggers reference stable IDs, so StateChange must use them.
            let stableDeviceId = self.deviceRegistryService?.readStableDeviceId(deviceId) ?? deviceId
            let stableServiceId = self.deviceRegistryService?.readStableServiceId(serviceId) ?? serviceId

            let change = StateChange(
                deviceId: stableDeviceId,
                deviceName: formattedName,
                roomName: roomName,
                serviceId: stableServiceId,
                serviceName: serviceName,
                characteristicType: characteristic.characteristicType,
                oldValue: cachedValue,
                newValue: value
            )

            if isObserved {
                if self.storage.readLoggingEnabled() && self.storage.readDeviceStateLoggingEnabled() {
                    await loggingService.logEntry(logEntry)
                }

                await webhookService.sendStateChange(change)

                let stableCharId = self.deviceRegistryService?.readStableCharacteristicId(charId) ?? charId
                self.characteristicValueChangePublisher.send(CharacteristicValueChange(
                    deviceId: stableDeviceId,
                    serviceId: stableServiceId,
                    characteristicId: stableCharId,
                    characteristicType: characteristic.characteristicType,
                    value: value,
                    oldValue: change.oldValue,
                    timestamp: Date()
                ))
            }

            // Publish state change for any subscribers (e.g. AutomationEngine).
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
    case sceneNotFound

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Device not found"
        case .serviceNotFound: return "Service not found"
        case .characteristicNotFound: return "Characteristic not found"
        case .notAuthorized: return "HomeKit access not authorized"
        case .sceneNotFound: return "Scene not found"
        }
    }
}
