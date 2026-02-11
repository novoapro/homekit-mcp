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
                return String(format: "%.1f°C", doubleVal)
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
