import HomeKit

/// Maps HomeKit service type UUIDs to human-readable names.
enum ServiceTypes {
    private static let mapping: [String: String] = [
        HMServiceTypeLightbulb: "Lightbulb",
        HMServiceTypeFan: "Fan",
        HMServiceTypeSwitch: "Switch",
        HMServiceTypeOutlet: "Outlet",
        HMServiceTypeThermostat: "Thermostat",
        HMServiceTypeDoor: "Door",
        HMServiceTypeDoorbell: "Doorbell",
        HMServiceTypeGarageDoorOpener: "Garage Door Opener",
        HMServiceTypeLockMechanism: "Lock",
        HMServiceTypeLockManagement: "Lock Management",
        HMServiceTypeWindow: "Window",
        HMServiceTypeWindowCovering: "Window Covering",
        HMServiceTypeMotionSensor: "Motion Sensor",
        HMServiceTypeOccupancySensor: "Occupancy Sensor",
        HMServiceTypeContactSensor: "Contact Sensor",
        HMServiceTypeTemperatureSensor: "Temperature Sensor",
        HMServiceTypeHumiditySensor: "Humidity Sensor",
        HMServiceTypeLightSensor: "Light Sensor",
        HMServiceTypeLeakSensor: "Leak Sensor",
        HMServiceTypeSmokeSensor: "Smoke Sensor",
        HMServiceTypeCarbonMonoxideSensor: "CO Sensor",
        HMServiceTypeCarbonDioxideSensor: "CO₂ Sensor",
        HMServiceTypeAirQualitySensor: "Air Quality Sensor",
        HMServiceTypeSecuritySystem: "Security System",
        HMServiceTypeBattery: "Battery",
        HMServiceTypeStatefulProgrammableSwitch: "Programmable Switch",
        HMServiceTypeStatelessProgrammableSwitch: "Stateless Switch",
        HMServiceTypeSpeaker: "Speaker",
        HMServiceTypeMicrophone: "Microphone",
        HMServiceTypeAirPurifier: "Air Purifier",
        HMServiceTypeValve: "Valve",
        HMServiceTypeAccessoryInformation: "Accessory Information",
    ]

    /// Semantic descriptions for each service type, explaining purpose and typical capabilities.
    private static let descriptions: [String: String] = [
        HMServiceTypeLightbulb: "Light source; typically supports power, brightness, hue, saturation, and color temperature",
        HMServiceTypeFan: "Ceiling or standalone fan; supports power and rotation speed control",
        HMServiceTypeSwitch: "Generic on/off switch; controls a single binary state",
        HMServiceTypeOutlet: "Smart power outlet; supports power on/off and reports whether the outlet is in use",
        HMServiceTypeThermostat: "Climate control; reads current temperature, sets target temperature and heating/cooling mode",
        HMServiceTypeDoor: "Motorized door; reports current position and accepts target position (0–100%)",
        HMServiceTypeDoorbell: "Doorbell button; fires an event when pressed, often paired with a camera",
        HMServiceTypeGarageDoorOpener: "Garage door controller; reports door state (open/closed/opening/closing) and accepts open/close commands",
        HMServiceTypeLockMechanism: "Smart lock; reports lock state (secured/unsecured/jammed) and accepts lock/unlock commands",
        HMServiceTypeLockManagement: "Lock administration; manages lock configuration and access control settings",
        HMServiceTypeWindow: "Motorized window; reports current position and accepts target position (0–100%)",
        HMServiceTypeWindowCovering: "Blinds, shades, or curtains; reports current position and accepts target position (0–100%)",
        HMServiceTypeMotionSensor: "Detects motion in an area; read-only boolean, commonly used as an automation trigger",
        HMServiceTypeOccupancySensor: "Detects room occupancy (presence); read-only, stays active while someone is present",
        HMServiceTypeContactSensor: "Detects open/close state of doors or windows; read-only boolean",
        HMServiceTypeTemperatureSensor: "Reads ambient temperature; read-only, value in °C or °F",
        HMServiceTypeHumiditySensor: "Reads relative humidity; read-only, value as percentage 0–100%",
        HMServiceTypeLightSensor: "Reads ambient light level; read-only, value in lux",
        HMServiceTypeLeakSensor: "Detects water leaks; read-only boolean, used for flood alerts",
        HMServiceTypeSmokeSensor: "Detects smoke; read-only boolean, used for fire safety alerts",
        HMServiceTypeCarbonMonoxideSensor: "Detects carbon monoxide; read-only, reports normal or abnormal levels",
        HMServiceTypeCarbonDioxideSensor: "Detects carbon dioxide; read-only, reports CO₂ concentration",
        HMServiceTypeAirQualitySensor: "Reads overall air quality index; read-only with quality levels from excellent to poor",
        HMServiceTypeSecuritySystem: "Home security system; reports armed/disarmed state and accepts arm/disarm commands",
        HMServiceTypeBattery: "Battery status; reports charge level, charging state, and low-battery warnings",
        HMServiceTypeStatefulProgrammableSwitch: "Configurable button that retains its state (on/off) after being pressed",
        HMServiceTypeStatelessProgrammableSwitch: "Configurable button that fires a momentary event (single/double/long press)",
        HMServiceTypeSpeaker: "Audio speaker; supports volume and mute controls",
        HMServiceTypeMicrophone: "Microphone input; supports volume and mute controls",
        HMServiceTypeAirPurifier: "Air purifier; supports power, active state, and fan speed",
        HMServiceTypeValve: "Water or gas valve; supports open/close and reports remaining duration",
        HMServiceTypeAccessoryInformation: "Device metadata; reports manufacturer, model, serial number, and firmware version",
    ]

    static func displayName(for serviceType: String) -> String {
        return mapping[serviceType] ?? serviceType
    }

    /// Returns the semantic description for a service type, or nil if unknown.
    static func description(for serviceType: String) -> String? {
        return descriptions[serviceType]
    }

    /// Maps human-readable names back to HMService type UUIDs.
    private static let reverseMapping: [String: String] = {
        var result: [String: String] = [:]
        for (key, value) in mapping {
            result[value.lowercased()] = key
        }
        // Common shorthand aliases
        result["light"] = HMServiceTypeLightbulb
        result["bulb"] = HMServiceTypeLightbulb
        result["lock"] = HMServiceTypeLockMechanism
        result["garage"] = HMServiceTypeGarageDoorOpener
        result["blinds"] = HMServiceTypeWindowCovering
        result["shades"] = HMServiceTypeWindowCovering
        return result
    }()

    static func serviceType(forName name: String) -> String? {
        return reverseMapping[name.lowercased()]
    }

    /// All known service type friendly names, sorted alphabetically.
    static var allDisplayNames: [String] {
        Array(Set(mapping.values)).sorted()
    }

    /// All known service types as (uuid, displayName, description) tuples, sorted by display name.
    static var allEntries: [(uuid: String, displayName: String, description: String)] {
        mapping.map { (uuid: $0.key, displayName: $0.value, description: descriptions[$0.key] ?? "") }
            .sorted { $0.displayName < $1.displayName }
    }

    static func isSupported(_ type: String) -> Bool {
        // Strict allowlist: only services with a mapped friendly name are supported.
        return mapping[type] != nil
    }
}
