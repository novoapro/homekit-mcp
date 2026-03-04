import Foundation

/// Evaluates `.deviceStateChange` triggers against state change events.
struct DeviceStateChangeTriggerEvaluator: TriggerEvaluator {

    let registry: DeviceRegistryService?

    init(registry: DeviceRegistryService? = nil) {
        self.registry = registry
    }

    func canEvaluate(_ trigger: WorkflowTrigger) -> Bool {
        switch trigger {
        case .deviceStateChange:
            return true
        case .schedule, .webhook, .workflow, .sunEvent:
            return false
        }
    }

    func evaluate(_ trigger: WorkflowTrigger, context: TriggerContext) async -> Bool {
        switch context {
        case .stateChange(let change):
            return evaluateTrigger(trigger, change: change)
        }
    }

    // MARK: - Internal

    private func evaluateTrigger(_ trigger: WorkflowTrigger, change: StateChange) -> Bool {
        switch trigger {
        case .deviceStateChange(let t):
            return evaluateDeviceStateTrigger(t, change: change)
        case .schedule, .webhook, .workflow, .sunEvent:
            return false
        }
    }

    private func evaluateDeviceStateTrigger(_ trigger: DeviceStateTrigger, change: StateChange) -> Bool {
        // Match device
        guard change.deviceId == trigger.deviceId else { return false }

        // Match service (optional)
        if let triggerServiceId = trigger.serviceId {
            guard change.serviceId == triggerServiceId else { return false }
        }

        // Resolve stable characteristic ID → HomeKit characteristic type for matching
        let resolvedType = registry?.readCharacteristicType(forStableId: trigger.characteristicId)
            ?? CharacteristicTypes.characteristicType(forName: trigger.characteristicId)
            ?? trigger.characteristicId
        guard change.characteristicType == resolvedType else { return false }

        // Convert temperature values to user's preferred unit before condition evaluation,
        // since trigger thresholds are stored in the user's preferred unit.
        var effectiveOld = change.oldValue
        var effectiveNew = change.newValue
        if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(resolvedType) {
            if let v = effectiveOld as? Double { effectiveOld = TemperatureConversion.celsiusToFahrenheit(v) }
            else if let v = effectiveOld as? Int { effectiveOld = TemperatureConversion.celsiusToFahrenheit(Double(v)) }
            if let v = effectiveNew as? Double { effectiveNew = TemperatureConversion.celsiusToFahrenheit(v) }
            else if let v = effectiveNew as? Int { effectiveNew = TemperatureConversion.celsiusToFahrenheit(Double(v)) }
        }

        // Evaluate condition
        return evaluateTriggerCondition(trigger.condition, oldValue: effectiveOld, newValue: effectiveNew)
    }

    private func evaluateTriggerCondition(_ condition: TriggerCondition, oldValue: Any?, newValue: Any?) -> Bool {
        switch condition {
        case .changed:
            // If oldValue is nil (first observation), conservatively treat as changed.
            // Otherwise verify the value actually changed.
            if oldValue == nil { return true }
            return !ConditionEvaluator.valuesEqual(oldValue, newValue)

        case .equals(let target):
            return ConditionEvaluator.valuesEqual(newValue, target.value)

        case .notEquals(let target):
            return !ConditionEvaluator.valuesEqual(newValue, target.value)

        case .transitioned(let from, let to):
            let fromMatches = from.map { ConditionEvaluator.valuesEqual(oldValue, $0.value) } ?? true
            let toMatches = to.map { ConditionEvaluator.valuesEqual(newValue, $0.value) } ?? true
            return fromMatches && toMatches

        case .greaterThan(let target):
            guard let numericValue = ConditionEvaluator.toDouble(newValue as Any) else { return false }
            return numericValue > target

        case .lessThan(let target):
            guard let numericValue = ConditionEvaluator.toDouble(newValue as Any) else { return false }
            return numericValue < target

        case .greaterThanOrEqual(let target):
            guard let numericValue = ConditionEvaluator.toDouble(newValue as Any) else { return false }
            return numericValue >= target

        case .lessThanOrEqual(let target):
            guard let numericValue = ConditionEvaluator.toDouble(newValue as Any) else { return false }
            return numericValue <= target
        }
    }
}
