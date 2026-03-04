import HomeKit

/// Maps HomeKit characteristic type UUIDs to human-readable names.
enum CharacteristicTypes {
    private static let mapping: [String: String] = [
        HMCharacteristicTypePowerState: "Power",
        HMCharacteristicTypeBrightness: "Brightness",
        HMCharacteristicTypeHue: "Hue",
        HMCharacteristicTypeSaturation: "Saturation",
        HMCharacteristicTypeColorTemperature: "Color Temperature",
        HMCharacteristicTypeCurrentTemperature: "Current Temperature",
        HMCharacteristicTypeTargetTemperature: "Target Temperature",
        HMCharacteristicTypeTemperatureUnits: "Temperature Units",
        HMCharacteristicTypeCurrentHeatingCooling: "Current Mode",
        HMCharacteristicTypeTargetHeatingCooling: "Target Mode",
        HMCharacteristicTypeCurrentRelativeHumidity: "Current Humidity",
        HMCharacteristicTypeTargetRelativeHumidity: "Target Humidity",
        HMCharacteristicTypeCurrentDoorState: "Door State",
        HMCharacteristicTypeTargetDoorState: "Target Door State",
        HMCharacteristicTypeCurrentLockMechanismState: "Lock State",
        HMCharacteristicTypeTargetLockMechanismState: "Target Lock State",
        HMCharacteristicTypeCurrentPosition: "Current Position",
        HMCharacteristicTypeTargetPosition: "Target Position",
        HMCharacteristicTypePositionState: "Position State",
        HMCharacteristicTypeMotionDetected: "Motion Detected",
        HMCharacteristicTypeContactState: "Contact State",
        HMCharacteristicTypeOccupancyDetected: "Occupancy Detected",
        HMCharacteristicTypeSmokeDetected: "Smoke Detected",
        HMCharacteristicTypeCarbonMonoxideDetected: "CO Detected",
        HMCharacteristicTypeBatteryLevel: "Battery Level",
        HMCharacteristicTypeStatusLowBattery: "Low Battery",
        HMCharacteristicTypeChargingState: "Charging State",
        HMCharacteristicTypeOutletInUse: "Outlet In Use",
        HMCharacteristicTypeRotationSpeed: "Rotation Speed",
        HMCharacteristicTypeCurrentFanState: "Fan State",
        HMCharacteristicTypeTargetFanState: "Target Fan State",
        HMCharacteristicTypeActive: "Active",
        HMCharacteristicTypeStatusActive: "Status Active",
        HMCharacteristicTypeName: "Name",
        HMCharacteristicTypeObstructionDetected: "Obstruction Detected",
        HMCharacteristicTypeStatusFault: "Fault",
        HMCharacteristicTypeStatusTampered: "Tampered",
        HMCharacteristicTypeCurrentLightLevel: "Light Level",
        HMCharacteristicTypeInputEvent: "Input Event",
        HMCharacteristicTypeProgramMode: "Program Mode",
        HMCharacteristicTypeInUse: "In Use",
        HMCharacteristicTypeRemainingDuration: "Remaining Duration",
        HMCharacteristicTypeSetDuration: "Set Duration",
        HMCharacteristicTypeValveType: "Valve Type",
        HMCharacteristicTypeIsConfigured: "Is Configured",
    ]

    static func displayName(for characteristicType: String) -> String {
        return mapping[characteristicType] ?? characteristicType
    }
    
    /// All known characteristic type friendly names, sorted alphabetically.
    static var allDisplayNames: [String] {
        Array(Set(mapping.values)).sorted()
    }

    /// Returns the full mapping from HomeKit UUID to friendly name (for metadata tools).
    static var allMappings: [(uuid: String, displayName: String)] {
        mapping.map { (uuid: $0.key, displayName: $0.value) }.sorted { $0.displayName < $1.displayName }
    }

    /// Returns all aliases for a given HomeKit characteristic type UUID.
    static func aliases(for characteristicType: String) -> [String] {
        reverseMapping.compactMap { key, value in
            value == characteristicType ? key : nil
        }.sorted()
    }

    static func isSupported(_ type: String) -> Bool {
        // Strict allowlist: only characteristics with a mapped friendly name are supported.
        // This filters out vendor-specific (UUIDs) and other unsupported characteristics.
        return mapping[type] != nil
    }

    /// Maps human-readable names back to HMCharacteristic type UUIDs for MCP tool usage.
    private static let reverseMapping: [String: String] = {
        var result: [String: String] = [:]
        for (key, value) in mapping {
            result[value.lowercased()] = key
        }
        // Also add common shorthand names
        result["power"] = HMCharacteristicTypePowerState
        result["brightness"] = HMCharacteristicTypeBrightness
        result["hue"] = HMCharacteristicTypeHue
        result["saturation"] = HMCharacteristicTypeSaturation
        result["temperature"] = HMCharacteristicTypeTargetTemperature
        result["current_temperature"] = HMCharacteristicTypeCurrentTemperature
        result["target_position"] = HMCharacteristicTypeTargetPosition
        result["lock_state"] = HMCharacteristicTypeTargetLockMechanismState
        result["color_temperature"] = HMCharacteristicTypeColorTemperature
        result["rotation_speed"] = HMCharacteristicTypeRotationSpeed
        return result
    }()

    static func characteristicType(forName name: String) -> String? {
        return reverseMapping[name.lowercased()]
    }

    static func formatValue(_ value: Any, characteristicType: String) -> String {
        switch characteristicType {
        case HMCharacteristicTypePowerState,
             HMCharacteristicTypeMotionDetected,
             HMCharacteristicTypeContactState,
             HMCharacteristicTypeOccupancyDetected,
             HMCharacteristicTypeSmokeDetected,
             HMCharacteristicTypeCarbonMonoxideDetected,
             HMCharacteristicTypeOutletInUse,
             HMCharacteristicTypeObstructionDetected,
             HMCharacteristicTypeStatusActive,
             HMCharacteristicTypeActive:
            if let boolVal = value as? Bool {
                return boolVal ? "On" : "Off"
            }
            if let intVal = value as? Int {
                return intVal != 0 ? "On" : "Off"
            }

        case HMCharacteristicTypeBrightness,
             HMCharacteristicTypeSaturation,
             HMCharacteristicTypeBatteryLevel,
             HMCharacteristicTypeCurrentRelativeHumidity,
             HMCharacteristicTypeTargetRelativeHumidity:
            return "\(value)%"

        case HMCharacteristicTypeCurrentTemperature,
             HMCharacteristicTypeTargetTemperature:
            if let doubleVal = value as? Double {
                return String(format: "%.1f%@", doubleVal, TemperatureConversion.unitSuffix)
            }

        case HMCharacteristicTypeHue:
            return "\(value)°"

        case HMCharacteristicTypeCurrentDoorState:
            if let intVal = value as? Int {
                switch intVal {
                case 0: return "Open"
                case 1: return "Closed"
                case 2: return "Opening"
                case 3: return "Closing"
                case 4: return "Stopped"
                default: break
                }
            }

        case HMCharacteristicTypeCurrentLockMechanismState:
            if let intVal = value as? Int {
                switch intVal {
                case 0: return "Unsecured"
                case 1: return "Secured"
                case 2: return "Jammed"
                case 3: return "Unknown"
                default: break
                }
            }

        case HMCharacteristicTypeCurrentPosition,
             HMCharacteristicTypeTargetPosition:
            return "\(value)%"

        case HMCharacteristicTypeColorTemperature:
            return "\(value)K"

        case HMCharacteristicTypeRotationSpeed:
            return "\(value)%"

        default:
            break
        }

        return "\(value)"
    }
}
