import Foundation
import HomeKit

/// Determines the best input control type for a characteristic based on its metadata.
public enum InputControlType {
    case toggle
    case labeledToggle(offLabel: String, onLabel: String, offValue: String, onValue: String)
    case segmentedPicker(options: [(label: String, value: String)])
    case slider(min: Double, max: Double, step: Double, unit: String?)
    case picker(options: [(label: String, value: String)])
    case textField(inputType: TextFieldInputType)
}

public enum TextFieldInputType {
    case decimal
    case number
    case text
}

public struct CharacteristicInputConfig {
    /// Determines the input control type for a characteristic.
    public static func getInputType(
        for characteristicType: String,
        format: String,
        minValue: Double?,
        maxValue: Double?,
        stepValue: Double? = nil,
        validValues: [Int]?
    ) -> InputControlType {
        // 1. If boolean format → use toggle switch
        if format == "bool" {
            return .toggle
        }

        // 2. If has discrete valid values → choose control by count
        if let validValues = validValues, !validValues.isEmpty {
            let options = buildPickerOptions(for: characteristicType, values: validValues)
            if options.count == 2 {
                // Binary enum → labeled toggle (e.g. "Open ○───● Closed")
                return .labeledToggle(
                    offLabel: options[0].label,
                    onLabel: options[1].label,
                    offValue: options[0].value,
                    onValue: options[1].value
                )
            } else if options.count <= 4 {
                // 3-4 options → segmented control
                return .segmentedPicker(options: options)
            } else {
                // 5+ options → dropdown picker
                return .picker(options: options)
            }
        }

        // 3. If has min/max constraints → use slider
        if let min = minValue, let max = maxValue {
            let unit = getUnitSuffix(for: characteristicType)
            let step = stepValue ?? getSliderStep(min: min, max: max)
            return .slider(min: min, max: max, step: step, unit: unit)
        }

        // 4. If float format → use decimal keyboard
        if format == "float" {
            return .textField(inputType: .decimal)
        }

        // 5. If integer format → use number keyboard
        if ["int", "uint8", "uint16", "uint32", "uint64"].contains(format) {
            return .textField(inputType: .number)
        }

        // 6. Default to generic text field
        return .textField(inputType: .text)
    }

    /// Returns a human-readable display string for a characteristic value in auto-names.
    /// Converts boolean "true"/"false" to "On"/"Off", enum integers to labels,
    /// and appends unit suffixes when available.
    public static func displayValueForName(characteristicType: String, rawValue: String) -> String {
        if rawValue.isEmpty { return rawValue }

        // Boolean display
        if rawValue == "true" { return "On" }
        if rawValue == "false" { return "Off" }

        // Enum label lookup (e.g. "0" → "Open" for door state)
        if let intVal = Int(rawValue),
           let labelMap = enumLabelMaps[characteristicType],
           let label = labelMap[intVal] {
            return label
        }

        // Append unit suffix (e.g. "25" → "25°C")
        if let unit = getUnitSuffix(for: characteristicType) {
            return "\(rawValue)\(unit)"
        }

        return rawValue
    }

    /// Known enum label maps keyed by characteristic type UUID.
    /// Used to convert raw integer valid values into human-readable labels.
    static let enumLabelMaps: [String: [Int: String]] = {
        var maps: [String: [Int: String]] = [:]

        let doorStates: [Int: String] = [0: "Open", 1: "Closed", 2: "Opening", 3: "Closing", 4: "Stopped"]
        maps[HMCharacteristicTypeCurrentDoorState] = doorStates
        maps[HMCharacteristicTypeTargetDoorState] = doorStates

        let lockStates: [Int: String] = [0: "Unsecured", 1: "Secured", 2: "Jammed", 3: "Unknown"]
        maps[HMCharacteristicTypeCurrentLockMechanismState] = lockStates
        maps[HMCharacteristicTypeTargetLockMechanismState] = lockStates

        let heatingCooling: [Int: String] = [0: "Off", 1: "Heat", 2: "Cool", 3: "Auto"]
        maps[HMCharacteristicTypeCurrentHeatingCooling] = heatingCooling
        maps[HMCharacteristicTypeTargetHeatingCooling] = heatingCooling

        let fanStates: [Int: String] = [0: "Inactive", 1: "Idle", 2: "Blowing"]
        maps[HMCharacteristicTypeCurrentFanState] = fanStates

        let targetFanStates: [Int: String] = [0: "Manual", 1: "Auto"]
        maps[HMCharacteristicTypeTargetFanState] = targetFanStates

        let active: [Int: String] = [0: "Inactive", 1: "Active"]
        maps[HMCharacteristicTypeActive] = active

        let contactState: [Int: String] = [0: "Detected", 1: "Not Detected"]
        maps[HMCharacteristicTypeContactState] = contactState

        let occupancy: [Int: String] = [0: "Not Detected", 1: "Detected"]
        maps[HMCharacteristicTypeOccupancyDetected] = occupancy

        let smoke: [Int: String] = [0: "None", 1: "Detected"]
        maps[HMCharacteristicTypeSmokeDetected] = smoke

        let co: [Int: String] = [0: "Normal", 1: "Abnormal"]
        maps[HMCharacteristicTypeCarbonMonoxideDetected] = co

        let lowBattery: [Int: String] = [0: "Normal", 1: "Low"]
        maps[HMCharacteristicTypeStatusLowBattery] = lowBattery

        let chargingState: [Int: String] = [0: "Not Charging", 1: "Charging", 2: "Not Chargeable"]
        maps[HMCharacteristicTypeChargingState] = chargingState

        let positionState: [Int: String] = [0: "Decreasing", 1: "Increasing", 2: "Stopped"]
        maps[HMCharacteristicTypePositionState] = positionState

        let tempUnits: [Int: String] = [0: "Celsius", 1: "Fahrenheit"]
        maps[HMCharacteristicTypeTemperatureUnits] = tempUnits

        let inUse: [Int: String] = [0: "Not In Use", 1: "In Use"]
        maps[HMCharacteristicTypeInUse] = inUse

        let valveType: [Int: String] = [0: "Generic", 1: "Irrigation", 2: "Shower Head", 3: "Water Faucet"]
        maps[HMCharacteristicTypeValveType] = valveType

        let programMode: [Int: String] = [0: "No Program", 1: "Scheduled", 2: "Manual"]
        maps[HMCharacteristicTypeProgramMode] = programMode

        let isConfigured: [Int: String] = [0: "Not Configured", 1: "Configured"]
        maps[HMCharacteristicTypeIsConfigured] = isConfigured

        let inputEvent: [Int: String] = [0: "Single Press", 1: "Double Press", 2: "Long Press"]
        maps[HMCharacteristicTypeInputEvent] = inputEvent

        let statusFault: [Int: String] = [0: "No Fault", 1: "Fault"]
        maps[HMCharacteristicTypeStatusFault] = statusFault

        let tampered: [Int: String] = [0: "Normal", 1: "Tampered"]
        maps[HMCharacteristicTypeStatusTampered] = tampered

        let obstruction: [Int: String] = [0: "No Obstruction", 1: "Obstruction"]
        maps[HMCharacteristicTypeObstructionDetected] = obstruction

        return maps
    }()

    /// Builds picker options with labels for discrete characteristics.
    static func buildPickerOptions(for characteristicType: String, values: [Int]) -> [(label: String, value: String)] {
        if let labelMap = enumLabelMaps[characteristicType] {
            return values.compactMap { value in
                guard let label = labelMap[value] else { return nil }
                return (label: label, value: String(value))
            }
        }
        // Generic fallback: just use the numeric values as labels
        return values.map { (label: String($0), value: String($0)) }
    }

    /// Determines the unit suffix for displaying slider values.
    private static func getUnitSuffix(for characteristicType: String) -> String? {
        switch characteristicType {
        // Percentage-based characteristics
        case HMCharacteristicTypeBrightness,
             HMCharacteristicTypeSaturation,
             HMCharacteristicTypeBatteryLevel,
             HMCharacteristicTypeCurrentRelativeHumidity,
             HMCharacteristicTypeTargetRelativeHumidity,
             HMCharacteristicTypeCurrentPosition,
             HMCharacteristicTypeTargetPosition,
             HMCharacteristicTypeRotationSpeed:
            return "%"

        // Temperature characteristics
        case HMCharacteristicTypeCurrentTemperature,
             HMCharacteristicTypeTargetTemperature:
            return TemperatureConversion.unitSuffix

        // Color characteristics
        case HMCharacteristicTypeHue:
            return "°"

        case HMCharacteristicTypeColorTemperature:
            return "K"

        default:
            return nil
        }
    }

    /// Calculates an appropriate step size for slider.
    /// Divides the range into roughly 100 steps for smooth interaction.
    private static func getSliderStep(min: Double, max: Double) -> Double {
        let range = max - min
        let step = range / 100.0
        // Round to reasonable precision (0.1, 1, or 5)
        if step < 0.1 { return 0.1 }
        if step < 1 { return 1 }
        return step
    }
}
