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

    static func displayName(for serviceType: String) -> String {
        return mapping[serviceType] ?? serviceType
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
}
