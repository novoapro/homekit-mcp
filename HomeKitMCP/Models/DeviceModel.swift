import Foundation
import HomeKit

struct DeviceModel: Identifiable, Codable {
    let id: String
    let name: String
    let roomName: String?
    let categoryType: String
    let services: [ServiceModel]
    var isReachable: Bool
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

struct CharacteristicConfiguration: Codable, Equatable {
    var externalAccessEnabled: Bool
    var webhookEnabled: Bool

    static let `default` = CharacteristicConfiguration(externalAccessEnabled: true, webhookEnabled: false)
}
