import HomeKit

/// Maps HomeKit accessory category type strings to human-readable names.
enum DeviceCategories {
    private static let mapping: [String: String] = [
        "HMAccessoryCategoryTypeLightbulb": "Lightbulb",
        "HMAccessoryCategoryTypeSwitch": "Switch",
        "HMAccessoryCategoryTypeProgrammableSwitch": "Programmable Switch",
        "HMAccessoryCategoryTypeOutlet": "Outlet",
        "HMAccessoryCategoryTypeThermostat": "Thermostat",
        "HMAccessoryCategoryTypeFan": "Fan",
        "HMAccessoryCategoryTypeDoor": "Door",
        "HMAccessoryCategoryTypeDoorLock": "Door Lock",
        "HMAccessoryCategoryTypeWindow": "Window",
        "HMAccessoryCategoryTypeWindowCovering": "Window Covering",
        "HMAccessoryCategoryTypeGarageDoorOpener": "Garage Door Opener",
        "HMAccessoryCategoryTypeSensor": "Sensor",
        "HMAccessoryCategoryTypeSecuritySystem": "Security System",
        "HMAccessoryCategoryTypeBridge": "Bridge",
        "HMAccessoryCategoryTypeAirConditioner": "Air Conditioner",
        "HMAccessoryCategoryTypeAirHeater": "Air Heater",
        "HMAccessoryCategoryTypeAirPurifier": "Air Purifier",
        "HMAccessoryCategoryTypeAirHumidifier": "Air Humidifier",
        "HMAccessoryCategoryTypeAirDehumidifier": "Air Dehumidifier",
        "HMAccessoryCategoryTypeFaucet": "Faucet",
        "HMAccessoryCategoryTypeShowerHead": "Shower Head",
        "HMAccessoryCategoryTypeSprinkler": "Sprinkler",
        "HMAccessoryCategoryTypeDoorbell": "Doorbell",
    ]

    /// Semantic descriptions for each device category, explaining what kind of physical device it represents.
    private static let descriptions: [String: String] = [
        "HMAccessoryCategoryTypeLightbulb": "Lighting device such as a bulb, light strip, or smart lamp",
        "HMAccessoryCategoryTypeSwitch": "Wall switch or smart switch that toggles one or more circuits",
        "HMAccessoryCategoryTypeProgrammableSwitch": "Configurable button (e.g. Hue dimmer, IKEA shortcut button) that fires events on press",
        "HMAccessoryCategoryTypeOutlet": "Smart power outlet or plug that can be switched on/off remotely",
        "HMAccessoryCategoryTypeThermostat": "Heating/cooling controller with temperature reading and target setting",
        "HMAccessoryCategoryTypeFan": "Ceiling fan or standalone fan with speed control",
        "HMAccessoryCategoryTypeDoor": "Motorized door that can be opened/closed to a target position",
        "HMAccessoryCategoryTypeDoorLock": "Smart door lock that can be locked/unlocked remotely",
        "HMAccessoryCategoryTypeWindow": "Motorized window that can be opened/closed to a target position",
        "HMAccessoryCategoryTypeWindowCovering": "Blinds, shades, shutters, or curtains with position control",
        "HMAccessoryCategoryTypeGarageDoorOpener": "Garage door motor with open/close control and state reporting",
        "HMAccessoryCategoryTypeSensor": "Environmental or state sensor (motion, temperature, humidity, contact, leak, etc.)",
        "HMAccessoryCategoryTypeSecuritySystem": "Home alarm system with arm/disarm modes and intrusion detection",
        "HMAccessoryCategoryTypeBridge": "Hub that connects non-HomeKit devices to HomeKit (e.g. Hue Bridge, IKEA gateway)",
        "HMAccessoryCategoryTypeAirConditioner": "Air conditioning unit with cooling, temperature, and fan controls",
        "HMAccessoryCategoryTypeAirHeater": "Heating appliance with temperature target and power controls",
        "HMAccessoryCategoryTypeAirPurifier": "Air purifier with fan speed and filter status",
        "HMAccessoryCategoryTypeAirHumidifier": "Adds moisture to the air; supports target humidity level",
        "HMAccessoryCategoryTypeAirDehumidifier": "Removes moisture from the air; supports target humidity level",
        "HMAccessoryCategoryTypeFaucet": "Smart faucet with flow control",
        "HMAccessoryCategoryTypeShowerHead": "Smart shower head with flow or temperature control",
        "HMAccessoryCategoryTypeSprinkler": "Irrigation sprinkler with on/off and duration control",
        "HMAccessoryCategoryTypeDoorbell": "Video or non-video doorbell that fires an event when pressed",
    ]

    static func displayName(for categoryType: String) -> String {
        mapping[categoryType] ?? categoryType
    }

    /// Returns the semantic description for a device category, or nil if unknown.
    static func description(for categoryType: String) -> String? {
        descriptions[categoryType]
    }

    /// Returns the semantic description for a display name, or nil if unknown.
    static func descriptionByName(_ name: String) -> String? {
        guard let key = reverseMapping[name.lowercased()] else { return nil }
        return descriptions[key]
    }

    /// All known device category friendly names, sorted alphabetically.
    static var allDisplayNames: [String] {
        Array(Set(mapping.values)).sorted()
    }

    /// All known device categories as (displayName, description) tuples, sorted by display name.
    static var allEntries: [(displayName: String, description: String)] {
        mapping.map { (displayName: $0.value, description: descriptions[$0.key] ?? "") }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Maps human-readable names back to HMAccessoryCategoryType strings.
    private static let reverseMapping: [String: String] = {
        var result: [String: String] = [:]
        for (key, value) in mapping {
            result[value.lowercased()] = key
        }
        // Common shorthand aliases
        result["light"] = "HMAccessoryCategoryTypeLightbulb"
        result["lock"] = "HMAccessoryCategoryTypeDoorLock"
        result["garage"] = "HMAccessoryCategoryTypeGarageDoorOpener"
        result["blinds"] = "HMAccessoryCategoryTypeWindowCovering"
        result["shades"] = "HMAccessoryCategoryTypeWindowCovering"
        return result
    }()

    static func categoryType(forName name: String) -> String? {
        reverseMapping[name.lowercased()]
    }
}
