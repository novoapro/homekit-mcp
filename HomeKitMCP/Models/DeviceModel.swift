import Foundation
import HomeKit

struct DeviceModel: Identifiable, Codable {
    let id: String
    let name: String
    let roomName: String?
    let categoryType: String
    let services: [ServiceModel]
    var isReachable: Bool

    // Hardware identity from AccessoryInformation service (cross-device stable)
    let manufacturer: String?
    let model: String?
    let serialNumber: String?
    let firmwareRevision: String?

    /// Composite hardware key for cross-device matching. Nil if any required field is missing.
    var hardwareKey: String? {
        guard let mfr = manufacturer, let mdl = model, let sn = serialNumber,
              !mfr.isEmpty, !mdl.isEmpty, !sn.isEmpty else { return nil }
        return "\(mfr):\(mdl):\(sn)"
    }
}

struct ServiceModel: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let characteristics: [CharacteristicModel]

    /// Human-readable service type name (e.g. "Fan", "Lightbulb").
    var displayName: String {
        ServiceTypes.displayName(for: type)
    }

    /// Returns the best available human-readable name for this service.
    ///
    /// Fallback chain:
    /// 1. The "Name" characteristic value (if present on this service and non-empty)
    /// 2. `HMService.name` (stored in `self.name`) — the user/manufacturer-assigned name,
    ///    but only if it differs from the generic type name (indicating it's been customized)
    /// 3. The generic type-based display name (e.g. "Switch", "Outlet")
    ///
    /// This is essential for multi-component accessories (power strips, multi-button switches)
    /// where each service of the same type has a distinct name (e.g., "Outlet 1", "Outlet 2").
    var effectiveDisplayName: String {
        // 1. Try the Name characteristic value (if present on this service)
        if let nameChar = characteristics.first(where: { $0.type == HMCharacteristicTypeName }),
           let nameValue = nameChar.value?.value as? String,
           !nameValue.isEmpty {
            return nameValue
        }
        // 2. Try HMService.name — only if it's a custom name (differs from the generic type name)
        if !name.isEmpty && name != displayName {
            return name
        }
        // 3. Fall back to generic type-based name
        return displayName
    }
}

// MARK: - Device + Service Name Resolution

extension DeviceModel {
    /// Returns a descriptive name for a specific service within this device.
    /// For multi-service devices, appends the service's effective display name
    /// (e.g. "Power Strip › Outlet 1"). For single-service devices, returns just the device name.
    func nameIncludingService(serviceId: String?) -> String {
        guard let serviceId,
              services.count > 1,
              let service = services.first(where: { $0.id == serviceId }) else {
            return name
        }
        return "\(name) › \(service.effectiveDisplayName)"
    }
}

extension Array where Element == DeviceModel {
    /// Resolves a device ID and optional service ID to a descriptive name.
    /// For multi-service devices with a service ID, returns "DeviceName › ServiceName".
    func resolvedName(deviceId: String, serviceId: String? = nil) -> String {
        guard let device = first(where: { $0.id == deviceId }) else { return deviceId }
        return device.nameIncludingService(serviceId: serviceId)
    }
}

struct CharacteristicModel: Identifiable, Codable {
    let id: String
    let type: String
    var value: AnyCodable?
    let format: String
    let units: String?
    let permissions: [String]
    var minValue: Double?
    var maxValue: Double?
    var stepValue: Double?

    // Enum values for discrete characteristics (door state, lock state, etc.)
    let validValues: [Int]?
}

// MARK: - Characteristic Display

extension CharacteristicModel {
    /// Human-readable name derived from the HomeKit characteristic type.
    var displayName: String {
        CharacteristicTypes.displayName(for: type)
    }
}

extension Array where Element == DeviceModel {
    /// Resolves a characteristic's display name from a stable characteristic ID.
    /// Searches across all devices and services for a matching characteristic.
    /// Falls back to `CharacteristicTypes.displayName` (for legacy HK type strings) or the raw ID.
    func resolvedCharacteristicName(deviceId: String, characteristicId: String) -> String {
        if let device = first(where: { $0.id == deviceId }) {
            for service in device.services {
                if let char = service.characteristics.first(where: { $0.id == characteristicId }) {
                    return char.displayName
                }
            }
        }
        // Fallback for legacy values that are still HK type strings
        let name = CharacteristicTypes.displayName(for: characteristicId)
        if name != characteristicId { return name }
        return characteristicId
    }
}

extension Array where Element == DeviceModel {
    /// Resolves a stable characteristic ID to its HomeKit characteristic type string.
    /// Returns the stable ID itself as fallback (for legacy values that are already HK types).
    func resolvedCharacteristicType(deviceId: String, characteristicId: String) -> String {
        if let device = first(where: { $0.id == deviceId }) {
            for service in device.services {
                if let char = service.characteristics.first(where: { $0.id == characteristicId }) {
                    return char.type
                }
            }
        }
        return characteristicId
    }
}

// MARK: - Characteristic Display Filtering

extension CharacteristicModel {
    /// Metadata-only characteristics that should be hidden from user-facing lists.
    /// Their info is surfaced elsewhere (e.g., Name is shown in the service header via `effectiveDisplayName`).
    static let hiddenDisplayNames: Set<String> = ["Name", "Is Configured", "Status Active"]

    /// Whether this characteristic should appear in user-facing lists (pickers, device rows, MCP output, AI context).
    var isUserFacing: Bool {
        !Self.hiddenDisplayNames.contains(CharacteristicTypes.displayName(for: type))
    }
}

