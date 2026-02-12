import Foundation
import HomeKit
import Combine

class HomeKitManager: NSObject, ObservableObject {
    @Published var homes: [HMHome] = []
    @Published var allAccessories: [HMAccessory] = []
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined
    @Published var isReady = false
    @Published var isReadingValues = false

    private let homeManager = HMHomeManager()
    private let loggingService: LoggingService
    private let webhookService: WebhookService
    let configService: DeviceConfigurationService
    private var cancellables = Set<AnyCancellable>()

    /// Coalesces rapid objectWillChange signals during bulk reads.
    private var uiUpdateWorkItem: DispatchWorkItem?

    init(loggingService: LoggingService, webhookService: WebhookService, configService: DeviceConfigurationService) {
        self.loggingService = loggingService
        self.webhookService = webhookService
        self.configService = configService
        super.init()
        homeManager.delegate = self
    }

    func getAllDevices() -> [DeviceModel] {
        return allAccessories.compactMap { accessory in
            let services = accessory.services.compactMap { service -> ServiceModel? in
                guard service.serviceType != HMServiceTypeAccessoryInformation else { return nil }
                let characteristics = service.characteristics.map { char in
                    CharacteristicModel(
                        id: char.uniqueIdentifier.uuidString,
                        type: char.characteristicType,
                        value: char.value.map { AnyCodable($0) },
                        format: char.metadata?.format ?? "unknown",
                        permissions: characteristicPermissions(char)
                    )
                }
                guard !characteristics.isEmpty else { return nil }
                return ServiceModel(
                    id: service.uniqueIdentifier.uuidString,
                    name: service.name,
                    type: service.serviceType,
                    characteristics: characteristics
                )
            }
            guard !services.isEmpty else { return nil }
            return DeviceModel(
                id: accessory.uniqueIdentifier.uuidString,
                name: accessory.name,
                roomName: accessory.room?.name,
                categoryType: accessory.category.categoryType,
                services: services,
                isReachable: accessory.isReachable
            )
        }
    }

    /// Returns devices grouped by room name. Devices without a room go under "Other".
    func getDevicesGroupedByRoom() -> [(roomName: String, devices: [DeviceModel])] {
        let allDevices = getAllDevices()
        let grouped = Dictionary(grouping: allDevices) { $0.roomName ?? "Other" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (roomName: $0.key, devices: $0.value) }
    }

    func updateDevice(id: String, characteristicType: String, value: Any) async throws {
        guard let accessory = allAccessories.first(where: { $0.uniqueIdentifier.uuidString == id }) else {
            throw HomeKitError.deviceNotFound
        }

        // Support both raw UUID and human-readable name for characteristic type
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType

        for service in accessory.services {
            for characteristic in service.characteristics where characteristic.characteristicType == resolvedType {
                try await characteristic.writeValue(value)
                return
            }
        }

        throw HomeKitError.characteristicNotFound
    }

    func getDeviceState(id: String) -> DeviceModel? {
        return getAllDevices().first { $0.id == id }
    }

    /// Coalesced UI update — waits for a brief quiet period before sending objectWillChange.
    /// This prevents hundreds of individual updates from each characteristic read.
    private func scheduleUIUpdate() {
        uiUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.objectWillChange.send()
        }
        uiUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func characteristicPermissions(_ characteristic: HMCharacteristic) -> [String] {
        var perms: [String] = []
        if characteristic.properties.contains(HMCharacteristicPropertyReadable) { perms.append("read") }
        if characteristic.properties.contains(HMCharacteristicPropertyWritable) { perms.append("write") }
        if characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) { perms.append("notify") }
        return perms
    }

    private func registerForNotifications() {
        for home in homes {
            for accessory in home.accessories {
                accessory.delegate = self
                for service in accessory.services {
                    for characteristic in service.characteristics {
                        if characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) {
                            characteristic.enableNotification(true) { error in
                                if let error = error {
                                    print("Failed to enable notification for \(characteristic.characteristicType): \(error)")
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
        var totalReads = 0
        var completedReads = 0
        let lock = NSLock()

        // Count how many reads we need
        for accessory in allAccessories where accessory.isReachable {
            for service in accessory.services {
                for characteristic in service.characteristics {
                    if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                        totalReads += 1
                    }
                }
            }
        }

        guard totalReads > 0 else {
            isReadingValues = false
            isReady = true
            return
        }

        isReadingValues = true
        // Show device list immediately with stale/nil values while reads happen
        isReady = true

        for accessory in allAccessories where accessory.isReachable {
            for service in accessory.services {
                for characteristic in service.characteristics {
                    if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                        characteristic.readValue { [weak self] error in
                            guard let self else { return }
                            if let error = error {
                                print("Failed to read \(characteristic.characteristicType) on \(accessory.name): \(error)")
                            }

                            lock.lock()
                            completedReads += 1
                            let allDone = completedReads >= totalReads
                            lock.unlock()

                            // Coalesce UI updates — don't fire for every single read
                            self.scheduleUIUpdate()

                            if allDone {
                                DispatchQueue.main.async {
                                    self.isReadingValues = false
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
            self.objectWillChange.send()
        }
    }

    func home(_ home: HMHome, didAdd room: HMRoom) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func home(_ home: HMHome, didRemove room: HMRoom) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func home(_ home: HMHome, didUpdateNameFor room: HMRoom) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

// MARK: - HMAccessoryDelegate
extension HomeKitManager: HMAccessoryDelegate {
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        let deviceId = accessory.uniqueIdentifier.uuidString
        let serviceId = service.uniqueIdentifier.uuidString
        let charId = characteristic.uniqueIdentifier.uuidString

        Task {
            // Check configuration for this specific characteristic
            let config = await configService.getConfig(
                deviceId: deviceId,
                serviceId: serviceId,
                characteristicId: charId
            )
            
            // If neither MCP nor Webhook is enabled, discard the event entirely
            guard config.mcpEnabled || config.webhookEnabled else { return }

            let change = StateChange(
                deviceId: deviceId,
                deviceName: accessory.name,
                characteristicType: characteristic.characteristicType,
                oldValue: nil,
                newValue: characteristic.value
            )
            
            // Log the event since at least one service is enabled
            await loggingService.log(change)

            // Send webhook if enabled
            if config.webhookEnabled {
                await webhookService.sendStateChange(change)
            }
            
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

// MARK: - Errors
enum HomeKitError: LocalizedError {
    case deviceNotFound
    case characteristicNotFound
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Device not found"
        case .characteristicNotFound: return "Characteristic not found"
        case .notAuthorized: return "HomeKit access not authorized"
        }
    }
}
