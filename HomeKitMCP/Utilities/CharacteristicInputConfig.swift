import Foundation
import HomeKit

/// Determines the best input control type for a characteristic based on its metadata.
enum InputControlType {
    case toggle
    case slider(min: Double, max: Double, step: Double, unit: String?)
    case picker(options: [(label: String, value: String)])
    case textField(inputType: TextFieldInputType)
}

enum TextFieldInputType {
    case decimal
    case number
    case text
}

struct CharacteristicInputConfig {
    /// Determines the input control type for a characteristic.
    static func getInputType(
        for characteristicType: String,
        format: String,
        minValue: Double?,
        maxValue: Double?,
        validValues: [Int]?
    ) -> InputControlType {
        // 1. If has discrete valid values → use dropdown picker
        if let validValues = validValues, !validValues.isEmpty {
            let options = buildPickerOptions(for: characteristicType, values: validValues)
            return .picker(options: options)
        }

        // 2. If boolean format → use toggle switch
        if format == "bool" {
            return .toggle
        }

        // 3. If has min/max constraints → use slider
        if let min = minValue, let max = maxValue {
            let unit = getUnitSuffix(for: characteristicType)
            let step = getSliderStep(min: min, max: max)
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

    /// Builds picker options with labels for discrete characteristics.
    private static func buildPickerOptions(for characteristicType: String, values: [Int]) -> [(label: String, value: String)] {
        switch characteristicType {
        case HMCharacteristicTypeCurrentDoorState,
             HMCharacteristicTypeTargetDoorState:
            return buildDoorStateOptions(values)

        case HMCharacteristicTypeCurrentLockMechanismState,
             HMCharacteristicTypeTargetLockMechanismState:
            return buildLockStateOptions(values)

        case HMCharacteristicTypeCurrentHeatingCooling,
             HMCharacteristicTypeTargetHeatingCooling:
            return buildHeatingCoolingOptions(values)

        case HMCharacteristicTypeCurrentFanState,
             HMCharacteristicTypeTargetFanState:
            return buildFanStateOptions(values)

        default:
            // Generic fallback: just use the numeric values as labels
            return values.map { (label: String($0), value: String($0)) }
        }
    }

    private static func buildDoorStateOptions(_ values: [Int]) -> [(label: String, value: String)] {
        let stateMap: [Int: String] = [
            0: "Open",
            1: "Closed",
            2: "Opening",
            3: "Closing",
            4: "Stopped"
        ]
        return values.compactMap { value in
            guard let label = stateMap[value] else { return nil }
            return (label: label, value: String(value))
        }
    }

    private static func buildLockStateOptions(_ values: [Int]) -> [(label: String, value: String)] {
        let stateMap: [Int: String] = [
            0: "Unsecured",
            1: "Secured",
            2: "Jammed",
            3: "Unknown"
        ]
        return values.compactMap { value in
            guard let label = stateMap[value] else { return nil }
            return (label: label, value: String(value))
        }
    }

    private static func buildHeatingCoolingOptions(_ values: [Int]) -> [(label: String, value: String)] {
        let stateMap: [Int: String] = [
            0: "Off",
            1: "Heat",
            2: "Cool",
            3: "Auto"
        ]
        return values.compactMap { value in
            guard let label = stateMap[value] else { return nil }
            return (label: label, value: String(value))
        }
    }

    private static func buildFanStateOptions(_ values: [Int]) -> [(label: String, value: String)] {
        let stateMap: [Int: String] = [
            0: "Inactive",
            1: "Active",
            2: "Jammed"
        ]
        return values.compactMap { value in
            guard let label = stateMap[value] else { return nil }
            return (label: label, value: String(value))
        }
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
            return "°C"

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
