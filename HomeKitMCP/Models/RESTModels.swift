import Foundation

// MARK: - REST API Response Models

/// A simplified device representation for the REST API.
/// Excludes internal fields like `categoryType` and uses human-readable names.
struct RESTDevice: Codable {
    let id: String
    let name: String
    let room: String?
    let isReachable: Bool
    let services: [RESTService]

    static func from(_ device: DeviceModel) -> RESTDevice {
        RESTDevice(
            id: device.id,
            name: device.name,
            room: device.roomName,
            isReachable: device.isReachable,
            services: device.services.map { RESTService.from($0) }
        )
    }
}

/// A simplified service representation for the REST API.
struct RESTService: Codable {
    let id: String
    let name: String
    let type: String
    let characteristics: [RESTCharacteristic]

    static func from(_ service: ServiceModel) -> RESTService {
        RESTService(
            id: service.id,
            name: service.name,
            type: ServiceTypes.displayName(for: service.type),
            characteristics: service.characteristics.map { RESTCharacteristic.from($0) }
        )
    }
}

/// A simplified characteristic representation for the REST API.
/// Excludes `permissions` and `format`.
struct RESTCharacteristic: Codable {
    let id: String
    let name: String
    let value: AnyCodable?

    static func from(_ characteristic: CharacteristicModel) -> RESTCharacteristic {
        RESTCharacteristic(
            id: characteristic.id,
            name: CharacteristicTypes.displayName(for: characteristic.type),
            value: characteristic.value
        )
    }
}
