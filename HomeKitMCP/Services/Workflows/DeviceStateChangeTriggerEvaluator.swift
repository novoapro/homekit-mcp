import Foundation

/// Evaluates `.deviceStateChange` and `.compound` triggers against state change events.
struct DeviceStateChangeTriggerEvaluator: TriggerEvaluator {

    func canEvaluate(_ trigger: WorkflowTrigger) -> Bool {
        switch trigger {
        case .deviceStateChange, .compound:
            return true
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
        case .compound(let t):
            return evaluateCompoundTrigger(t, change: change)
        }
    }

    private func evaluateDeviceStateTrigger(_ trigger: DeviceStateTrigger, change: StateChange) -> Bool {
        // Match device
        guard change.deviceId == trigger.deviceId else { return false }

        // Match service (optional)
        if let triggerServiceId = trigger.serviceId {
            guard change.serviceId == triggerServiceId else { return false }
        }

        // Match characteristic type — support both UUID and human-readable name
        let resolvedType = CharacteristicTypes.characteristicType(forName: trigger.characteristicType) ?? trigger.characteristicType
        guard change.characteristicType == resolvedType else { return false }

        // Evaluate condition
        return evaluateTriggerCondition(trigger.condition, oldValue: change.oldValue, newValue: change.newValue)
    }

    private func evaluateCompoundTrigger(_ trigger: CompoundTrigger, change: StateChange) -> Bool {
        switch trigger.logicOperator {
        case .and:
            return trigger.triggers.allSatisfy { evaluateTrigger($0, change: change) }
        case .or:
            return trigger.triggers.contains { evaluateTrigger($0, change: change) }
        }
    }

    private func evaluateTriggerCondition(_ condition: TriggerCondition, oldValue: Any?, newValue: Any?) -> Bool {
        switch condition {
        case .changed:
            // Any value change counts
            return true

        case .equals(let target):
            return ConditionEvaluator.valuesEqual(newValue, target.value)

        case .notEquals(let target):
            return !ConditionEvaluator.valuesEqual(newValue, target.value)

        case .transitioned(let from, let to):
            let toMatches = ConditionEvaluator.valuesEqual(newValue, to.value)
            if let from {
                let fromMatches = ConditionEvaluator.valuesEqual(oldValue, from.value)
                return fromMatches && toMatches
            }
            return toMatches

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
