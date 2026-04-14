import Foundation
import HomeKit

/// Shared temperature conversion utilities.
/// HomeKit always stores values in Celsius; this converts for display when the user prefers Fahrenheit.
enum TemperatureConversion {

    static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        celsius * 9.0 / 5.0 + 32.0
    }

    static func fahrenheitToCelsius(_ fahrenheit: Double) -> Double {
        (fahrenheit - 32.0) * 5.0 / 9.0
    }

    /// Whether the given HomeKit characteristic type is a temperature characteristic
    /// whose value/units should be converted based on user preference.
    static func isTemperatureCharacteristic(_ type: String) -> Bool {
        type == HMCharacteristicTypeCurrentTemperature ||
        type == HMCharacteristicTypeTargetTemperature
    }

    /// The user's preferred temperature unit, read directly from UserDefaults.
    /// Returns `"celsius"` or `"fahrenheit"`.
    static var preferredUnit: String {
        UserDefaults.standard.string(forKey: "temperatureUnit") ?? "celsius"
    }

    /// Whether the user prefers Fahrenheit.
    static var isFahrenheit: Bool {
        preferredUnit == "fahrenheit"
    }

    /// Returns the appropriate unit suffix string for temperature display.
    static var unitSuffix: String {
        isFahrenheit ? "°F" : "°C"
    }

    /// Converts a Celsius value to the user's preferred unit.
    static func convertFromCelsius(_ value: Double) -> Double {
        isFahrenheit ? celsiusToFahrenheit(value) : value
    }

    /// Converts a value in the user's preferred unit back to Celsius.
    static func convertToCelsius(_ value: Double) -> Double {
        isFahrenheit ? fahrenheitToCelsius(value) : value
    }

    /// Converts a step value (delta) from Celsius to Fahrenheit scale.
    /// Step values are deltas, so only the scaling factor applies (no offset).
    static func convertStepFromCelsius(_ step: Double) -> Double {
        isFahrenheit ? step * 9.0 / 5.0 : step
    }

    // MARK: - Automation Migration

    /// Migrates all automation temperature values when the unit preference changes.
    /// `convert` is the conversion function (e.g., C→F or F→C).
    static func migrateAutomations(
        automationStorage: AutomationStorageService,
        registry: DeviceRegistryService?,
        convert: @escaping (Double) -> Double
    ) async {
        let automations = await automationStorage.getAllAutomations()
        for automation in automations {
            await automationStorage.updateAutomation(id: automation.id) { w in
                w.triggers = w.triggers.map { migrateTrigger($0, registry: registry, convert: convert) }
                w.conditions = w.conditions?.map { migrateCondition($0, registry: registry, convert: convert) }
                w.blocks = w.blocks.map { migrateBlock($0, registry: registry, convert: convert) }
            }
        }
    }

    // MARK: - Migration Helpers

    private static func isTemperatureCharId(_ charId: String, registry: DeviceRegistryService?) -> Bool {
        if let type = registry?.readCharacteristicType(forStableId: charId) {
            return isTemperatureCharacteristic(type)
        }
        // Fallback: try interpreting as a HomeKit type or name
        if let type = CharacteristicTypes.characteristicType(forName: charId) {
            return isTemperatureCharacteristic(type)
        }
        return isTemperatureCharacteristic(charId)
    }

    private static func migrateTrigger(_ trigger: AutomationTrigger, registry: DeviceRegistryService?, convert: @escaping (Double) -> Double) -> AutomationTrigger {
        switch trigger {
        case .deviceStateChange(let t):
            guard isTemperatureCharId(t.characteristicId, registry: registry) else { return trigger }
            let newCondition = migrateTriggerCondition(t.matchOperator, convert: convert)
            return .deviceStateChange(DeviceStateTrigger(
                deviceId: t.deviceId, deviceName: t.deviceName, roomName: t.roomName,
                serviceId: t.serviceId, characteristicId: t.characteristicId,
                matchOperator: newCondition, name: t.name, retriggerPolicy: t.retriggerPolicy
            ))
        default:
            return trigger
        }
    }

    private static func migrateTriggerCondition(_ condition: TriggerCondition, convert: (Double) -> Double) -> TriggerCondition {
        switch condition {
        case .changed:
            return .changed
        case .equals(let v):
            return .equals(convertAnyCodableValue(v, convert: convert))
        case .notEquals(let v):
            return .notEquals(convertAnyCodableValue(v, convert: convert))
        case .transitioned(let from, let to):
            return .transitioned(
                from: from.map { convertAnyCodableValue($0, convert: convert) },
                to: to.map { convertAnyCodableValue($0, convert: convert) }
            )
        case .greaterThan(let v):
            return .greaterThan(convert(v))
        case .lessThan(let v):
            return .lessThan(convert(v))
        case .greaterThanOrEqual(let v):
            return .greaterThanOrEqual(convert(v))
        case .lessThanOrEqual(let v):
            return .lessThanOrEqual(convert(v))
        }
    }

    private static func migrateCondition(_ condition: AutomationCondition, registry: DeviceRegistryService?, convert: @escaping (Double) -> Double) -> AutomationCondition {
        switch condition {
        case .deviceState(let c):
            guard isTemperatureCharId(c.characteristicId, registry: registry) else { return condition }
            let newComparison = migrateComparison(c.comparison, convert: convert)
            return .deviceState(DeviceStateCondition(
                deviceId: c.deviceId, deviceName: c.deviceName, roomName: c.roomName,
                serviceId: c.serviceId, characteristicId: c.characteristicId,
                comparison: newComparison
            ))
        case .and(let conditions):
            return .and(conditions.map { migrateCondition($0, registry: registry, convert: convert) })
        case .or(let conditions):
            return .or(conditions.map { migrateCondition($0, registry: registry, convert: convert) })
        case .not(let inner):
            return .not(migrateCondition(inner, registry: registry, convert: convert))
        default:
            return condition
        }
    }

    private static func migrateComparison(_ comparison: ComparisonOperator, convert: (Double) -> Double) -> ComparisonOperator {
        switch comparison {
        case .equals(let v):
            return .equals(convertAnyCodableValue(v, convert: convert))
        case .notEquals(let v):
            return .notEquals(convertAnyCodableValue(v, convert: convert))
        case .greaterThan(let v):
            return .greaterThan(convert(v))
        case .lessThan(let v):
            return .lessThan(convert(v))
        case .greaterThanOrEqual(let v):
            return .greaterThanOrEqual(convert(v))
        case .lessThanOrEqual(let v):
            return .lessThanOrEqual(convert(v))
        case .isEmpty, .isNotEmpty, .contains:
            return comparison
        }
    }

    private static func migrateBlock(_ block: AutomationBlock, registry: DeviceRegistryService?, convert: @escaping (Double) -> Double) -> AutomationBlock {
        switch block {
        case .action(let action, let blockId):
            return .action(migrateAction(action, registry: registry, convert: convert), blockId: blockId)
        case .flowControl(let fc, let blockId):
            return .flowControl(migrateFlowControl(fc, registry: registry, convert: convert), blockId: blockId)
        }
    }

    private static func migrateAction(_ action: AutomationAction, registry: DeviceRegistryService?, convert: @escaping (Double) -> Double) -> AutomationAction {
        switch action {
        case .controlDevice(let a):
            guard isTemperatureCharId(a.characteristicId, registry: registry) else { return action }
            let newValue = convertAnyCodableValue(a.value, convert: convert)
            return .controlDevice(ControlDeviceAction(
                deviceId: a.deviceId, deviceName: a.deviceName, roomName: a.roomName,
                serviceId: a.serviceId, characteristicId: a.characteristicId,
                value: newValue, name: a.name
            ))
        default:
            return action
        }
    }

    private static func migrateFlowControl(_ fc: FlowControlBlock, registry: DeviceRegistryService?, convert: @escaping (Double) -> Double) -> FlowControlBlock {
        switch fc {
        case .conditional(let block):
            let newCondition = migrateCondition(block.condition, registry: registry, convert: convert)
            return .conditional(ConditionalBlock(
                condition: newCondition,
                thenBlocks: block.thenBlocks.map { migrateBlock($0, registry: registry, convert: convert) },
                elseBlocks: block.elseBlocks?.map { migrateBlock($0, registry: registry, convert: convert) },
                name: block.name
            ))
        case .repeatWhile(let block):
            let newCondition = migrateCondition(block.condition, registry: registry, convert: convert)
            return .repeatWhile(RepeatWhileBlock(
                condition: newCondition,
                blocks: block.blocks.map { migrateBlock($0, registry: registry, convert: convert) },
                maxIterations: block.maxIterations,
                delayBetweenSeconds: block.delayBetweenSeconds,
                name: block.name
            ))
        case .repeat(let block):
            return .repeat(RepeatBlock(
                count: block.count,
                blocks: block.blocks.map { migrateBlock($0, registry: registry, convert: convert) },
                delayBetweenSeconds: block.delayBetweenSeconds,
                name: block.name
            ))
        case .group(let block):
            return .group(GroupBlock(
                label: block.label,
                blocks: block.blocks.map { migrateBlock($0, registry: registry, convert: convert) },
                name: block.name
            ))
        case .delay, .waitForState, .stop, .executeAutomation:
            return fc
        }
    }

    private static func convertAnyCodableValue(_ value: AnyCodable, convert: (Double) -> Double) -> AnyCodable {
        if let d = value.value as? Double {
            return AnyCodable(convert(d))
        }
        if let i = value.value as? Int {
            return AnyCodable(convert(Double(i)))
        }
        return value
    }
}
