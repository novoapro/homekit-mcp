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

    static func displayName(for categoryType: String) -> String {
        mapping[categoryType] ?? categoryType
    }

    /// All known device category friendly names, sorted alphabetically.
    static var allDisplayNames: [String] {
        Array(Set(mapping.values)).sorted()
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
