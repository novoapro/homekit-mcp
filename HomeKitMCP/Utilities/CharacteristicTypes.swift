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

    /// Semantic descriptions explaining what each characteristic represents.
    private static let descriptions: [String: String] = [
        HMCharacteristicTypePowerState: "On/off state of a device",
        HMCharacteristicTypeBrightness: "Light intensity level",
        HMCharacteristicTypeHue: "Color hue component on the color wheel",
        HMCharacteristicTypeSaturation: "Color saturation intensity; 0% is white, 100% is full color",
        HMCharacteristicTypeColorTemperature: "White light warmth; low values are warm (yellow), high values are cool (blue)",
        HMCharacteristicTypeCurrentTemperature: "Ambient temperature reading from a sensor (read-only)",
        HMCharacteristicTypeTargetTemperature: "Desired temperature setpoint for a thermostat",
        HMCharacteristicTypeTemperatureUnits: "Display unit preference for temperature (Celsius or Fahrenheit)",
        HMCharacteristicTypeCurrentHeatingCooling: "Current operating mode of a thermostat (off, heating, or cooling) (read-only)",
        HMCharacteristicTypeTargetHeatingCooling: "Desired operating mode for a thermostat (off, heat, cool, or auto)",
        HMCharacteristicTypeCurrentRelativeHumidity: "Current relative humidity reading from a sensor (read-only)",
        HMCharacteristicTypeTargetRelativeHumidity: "Desired humidity level for a humidifier/dehumidifier",
        HMCharacteristicTypeCurrentDoorState: "Current physical state of a door (open, closed, opening, closing, stopped) (read-only)",
        HMCharacteristicTypeTargetDoorState: "Desired state for a motorized door (open or closed)",
        HMCharacteristicTypeCurrentLockMechanismState: "Current state of a lock (secured, unsecured, jammed, unknown) (read-only)",
        HMCharacteristicTypeTargetLockMechanismState: "Desired state for a lock (secured or unsecured)",
        HMCharacteristicTypeCurrentPosition: "Current position of a window covering, door, or window as percentage (read-only)",
        HMCharacteristicTypeTargetPosition: "Desired position for a window covering, door, or window as percentage",
        HMCharacteristicTypePositionState: "Movement direction of a positionable device (increasing, decreasing, stopped) (read-only)",
        HMCharacteristicTypeMotionDetected: "Whether motion is currently detected in the sensor's field (read-only)",
        HMCharacteristicTypeContactState: "Whether a door or window is open or closed (read-only)",
        HMCharacteristicTypeOccupancyDetected: "Whether a room is currently occupied (read-only)",
        HMCharacteristicTypeSmokeDetected: "Whether smoke is detected by the sensor (read-only)",
        HMCharacteristicTypeCarbonMonoxideDetected: "Whether carbon monoxide is at abnormal levels (read-only)",
        HMCharacteristicTypeBatteryLevel: "Remaining battery charge as a percentage (read-only)",
        HMCharacteristicTypeStatusLowBattery: "Whether battery level is critically low (read-only)",
        HMCharacteristicTypeChargingState: "Whether the device battery is currently charging (read-only)",
        HMCharacteristicTypeOutletInUse: "Whether an outlet is currently supplying power to a connected device (read-only)",
        HMCharacteristicTypeRotationSpeed: "Fan or motor rotation speed as a percentage",
        HMCharacteristicTypeCurrentFanState: "Current operating state of a fan (inactive, idle, blowing) (read-only)",
        HMCharacteristicTypeTargetFanState: "Desired fan operating mode (manual or auto)",
        HMCharacteristicTypeActive: "Whether a device is actively operating (e.g. air purifier running, valve open)",
        HMCharacteristicTypeStatusActive: "Whether a device is currently active and functional (read-only)",
        HMCharacteristicTypeName: "User-assigned name of the accessory or service (read-only)",
        HMCharacteristicTypeObstructionDetected: "Whether a physical obstruction is blocking a device like a garage door (read-only)",
        HMCharacteristicTypeStatusFault: "Whether the device has detected an internal fault (read-only)",
        HMCharacteristicTypeStatusTampered: "Whether the device has been physically tampered with (read-only)",
        HMCharacteristicTypeCurrentLightLevel: "Ambient light level measured in lux (read-only)",
        HMCharacteristicTypeInputEvent: "Button press event type (single press, double press, long press) (read-only)",
        HMCharacteristicTypeProgramMode: "Current scheduling/program mode of a valve or irrigation system (read-only)",
        HMCharacteristicTypeInUse: "Whether a valve or sprinkler is currently running water (read-only)",
        HMCharacteristicTypeRemainingDuration: "Seconds remaining in the current valve/sprinkler cycle (read-only)",
        HMCharacteristicTypeSetDuration: "Duration in seconds to run a valve or sprinkler when activated",
        HMCharacteristicTypeValveType: "Type of valve (generic, irrigation, shower head, faucet) (read-only)",
        HMCharacteristicTypeIsConfigured: "Whether a service has been set up and is ready to use (read-only)",
    ]

    static func displayName(for characteristicType: String) -> String {
        return mapping[characteristicType] ?? characteristicType
    }

    /// Returns the semantic description for a characteristic type, or nil if unknown.
    static func description(for characteristicType: String) -> String? {
        return descriptions[characteristicType]
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
