import Foundation
import HomeKit
import Combine

class HomeKitManager: NSObject, ObservableObject {
    @Published var homes: [HMHome] = []
    @Published var allAccessories: [HMAccessory] = []
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined
    @Published var isReady = false

    private let homeManager = HMHomeManager()
    private let loggingService: LoggingService
    private let webhookService: WebhookService
    private var cancellables = Set<AnyCancellable>()

    init(loggingService: LoggingService, webhookService: WebhookService) {
        self.loggingService = loggingService
        self.webhookService = webhookService
        super.init()
        homeManager.delegate = self
    }

    func getAllDevices() -> [DeviceModel] {
        return allAccessories.map { accessory in
            DeviceModel(
                id: accessory.uniqueIdentifier.uuidString,
                name: accessory.name,
                roomName: accessory.room?.name,
                categoryType: accessory.category.categoryType,
                services: accessory.services.compactMap { service in
                    guard service.serviceType != HMServiceTypeAccessoryInformation else { return nil }
                    return ServiceModel(
                        id: service.uniqueIdentifier.uuidString,
                        name: service.name,
                        type: service.serviceType,
                        characteristics: service.characteristics.map { char in
                            CharacteristicModel(
                                id: char.uniqueIdentifier.uuidString,
                                type: char.characteristicType,
                                value: char.value.map { AnyCodable($0) },
                                format: char.metadata?.format ?? "unknown",
                                permissions: characteristicPermissions(char)
                            )
                        }
                    )
                },
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
    private func readAllCharacteristicValues() {
        for accessory in allAccessories where accessory.isReachable {
            for service in accessory.services {
                for characteristic in service.characteristics {
                    if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                        characteristic.readValue { [weak self] error in
                            if let error = error {
                                print("Failed to read \(characteristic.characteristicType) on \(accessory.name): \(error)")
                            } else {
                                DispatchQueue.main.async {
                                    self?.objectWillChange.send()
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
        isReady = true
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
        let change = StateChange(
            deviceId: accessory.uniqueIdentifier.uuidString,
            deviceName: accessory.name,
            characteristicType: characteristic.characteristicType,
            oldValue: nil,
            newValue: characteristic.value
        )

        Task {
            await loggingService.log(change)
            await webhookService.sendStateChange(change)
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
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
