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
            name: service.effectiveDisplayName,
            type: ServiceTypes.displayName(for: service.type),
            characteristics: service.characteristics.map { RESTCharacteristic.from($0) }
        )
    }
}

/// A characteristic representation for the REST API with full metadata.
/// Permissions are already resolved by the Device Registry before reaching this model —
/// `notify` is only present when the characteristic is marked as observed.
struct RESTCharacteristic: Codable {
    let id: String
    let name: String
    let value: AnyCodable?
    let format: String
    let units: String?
    let permissions: [String]
    let minValue: Double?
    let maxValue: Double?
    let stepValue: Double?
    let validValues: [RESTValidValue]?

    static func from(_ characteristic: CharacteristicModel) -> RESTCharacteristic {
        let labeledValues: [RESTValidValue]? = characteristic.validValues.map { values in
            let options = CharacteristicInputConfig.buildPickerOptions(for: characteristic.type, values: values)
            return options.map { RESTValidValue(value: Int($0.value) ?? 0, label: $0.label) }
        }

        return RESTCharacteristic(
            id: characteristic.id,
            name: CharacteristicTypes.displayName(for: characteristic.type),
            value: characteristic.value,
            format: characteristic.format,
            units: characteristic.units,
            permissions: characteristic.permissions,
            minValue: characteristic.minValue,
            maxValue: characteristic.maxValue,
            stepValue: characteristic.stepValue,
            validValues: labeledValues
        )
    }
}

/// A labeled valid value for enum-like characteristics.
struct RESTValidValue: Codable {
    let value: Int
    let label: String
}

// MARK: - Scene REST Models

/// A simplified scene representation for the REST API.
struct RESTScene: Codable {
    let id: String
    let name: String
    let type: String
    let isExecuting: Bool
    let actionCount: Int
    let actions: [RESTSceneAction]

    static func from(_ scene: SceneModel) -> RESTScene {
        RESTScene(
            id: scene.id,
            name: scene.name,
            type: scene.type,
            isExecuting: scene.isExecuting,
            actionCount: scene.actions.count,
            actions: scene.actions.map { RESTSceneAction.from($0) }
        )
    }
}

/// A simplified scene action representation for the REST API.
struct RESTSceneAction: Codable {
    let deviceName: String
    let characteristicType: String
    let targetValue: AnyCodable

    static func from(_ action: SceneActionModel) -> RESTSceneAction {
        RESTSceneAction(
            deviceName: action.deviceName,
            characteristicType: action.characteristicType,
            targetValue: action.targetValue
        )
    }
}
