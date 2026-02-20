import Foundation

/// Evaluates `WorkflowCondition` guard expressions against current device state.
/// Used by the engine for pre-execution guards, conditional blocks, and repeatWhile blocks.
struct ConditionEvaluator {
    private let homeKitManager: HomeKitManager

    init(homeKitManager: HomeKitManager) {
        self.homeKitManager = homeKitManager
    }

    /// Evaluate a single condition. Returns true if the condition is met.
    func evaluate(_ condition: WorkflowCondition) async -> ConditionResult {
        let (passed, description) = await evaluateInternal(condition)
        return ConditionResult(conditionDescription: description, passed: passed)
    }

    /// Evaluate all conditions (AND semantics). Returns individual results and overall pass/fail.
    func evaluateAll(_ conditions: [WorkflowCondition]) async -> (allPassed: Bool, results: [ConditionResult]) {
        var results: [ConditionResult] = []
        var allPassed = true
        for condition in conditions {
            let result = await evaluate(condition)
            results.append(result)
            if !result.passed {
                allPassed = false
            }
        }
        return (allPassed, results)
    }

    /// Evaluate a `ComparisonOperator` against a known value.
    func evaluateComparison(_ comparison: ComparisonOperator, against value: Any?) -> Bool {
        guard let value else { return false }
        return Self.compare(value, using: comparison)
    }

    // MARK: - Internal

    private func evaluateInternal(_ condition: WorkflowCondition) async -> (Bool, String) {
        switch condition {
        case .deviceState(let cond):
            return await evaluateDeviceState(cond)
        case .and(let conditions):
            var allPassed = true
            var descriptions: [String] = []
            for c in conditions {
                let (passed, desc) = await evaluateInternal(c)
                descriptions.append(desc)
                if !passed { allPassed = false }
            }
            return (allPassed, "AND(\(descriptions.joined(separator: ", ")))")
        case .or(let conditions):
            var anyPassed = false
            var descriptions: [String] = []
            for c in conditions {
                let (passed, desc) = await evaluateInternal(c)
                descriptions.append(desc)
                if passed { anyPassed = true }
            }
            return (anyPassed, "OR(\(descriptions.joined(separator: ", ")))")
        case .not(let condition):
            let (passed, desc) = await evaluateInternal(condition)
            return (!passed, "NOT(\(desc))")
        }
    }

    private func evaluateDeviceState(_ condition: DeviceStateCondition) async -> (Bool, String) {
        let resolvedType = CharacteristicTypes.characteristicType(forName: condition.characteristicType) ?? condition.characteristicType
        let displayName = CharacteristicTypes.displayName(for: resolvedType)

        guard let device = await MainActor.run(body: { homeKitManager.getDeviceState(id: condition.deviceId) }) else {
            return (false, "\(displayName): device not found")
        }

        let currentValue = findCharacteristicValue(in: device, characteristicType: resolvedType, serviceId: condition.serviceId)
        let passed = Self.compare(currentValue as Any, using: condition.comparison)
        let compDesc = Self.comparisonDescription(condition.comparison)
        return (passed, "\(device.name).\(displayName) \(compDesc) = \(passed)")
    }

    private func findCharacteristicValue(in device: DeviceModel, characteristicType: String, serviceId: String?) -> Any? {
        let services: [ServiceModel]
        if let serviceId {
            services = device.services.filter { $0.id == serviceId }
        } else {
            services = device.services
        }

        for service in services {
            for characteristic in service.characteristics where characteristic.type == characteristicType {
                return characteristic.value?.value
            }
        }
        return nil
    }

    // MARK: - Comparison Logic

    static func compare(_ value: Any?, using comparison: ComparisonOperator) -> Bool {
        guard let value else { return false }

        switch comparison {
        case .equals(let target):
            return valuesEqual(value, target.value)
        case .notEquals(let target):
            return !valuesEqual(value, target.value)
        case .greaterThan(let target):
            guard let numericValue = toDouble(value) else { return false }
            return numericValue > target
        case .lessThan(let target):
            guard let numericValue = toDouble(value) else { return false }
            return numericValue < target
        case .greaterThanOrEqual(let target):
            guard let numericValue = toDouble(value) else { return false }
            return numericValue >= target
        case .lessThanOrEqual(let target):
            guard let numericValue = toDouble(value) else { return false }
            return numericValue <= target
        }
    }

    /// Flexible equality with type coercion (Bool↔Int, Int↔Double).
    static func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a, let b else { return false }

        // Same-type comparisons
        if let a = a as? Bool, let b = b as? Bool { return a == b }
        if let a = a as? String, let b = b as? String { return a == b }

        // Numeric comparisons (Int, Double, Bool as numeric)
        if let aNum = toDouble(a), let bNum = toDouble(b) {
            return aNum == bNum
        }

        return false
    }

    /// Convert a value to Double for numeric comparison. Supports Bool, Int, Double.
    static func toDouble(_ value: Any) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        if let v = value as? Bool { return v ? 1.0 : 0.0 }
        if let v = value as? Float { return Double(v) }
        return nil
    }

    static func comparisonDescription(_ comparison: ComparisonOperator) -> String {
        switch comparison {
        case .equals(let v): return "== \(v.value)"
        case .notEquals(let v): return "!= \(v.value)"
        case .greaterThan(let v): return "> \(v)"
        case .lessThan(let v): return "< \(v)"
        case .greaterThanOrEqual(let v): return ">= \(v)"
        case .lessThanOrEqual(let v): return "<= \(v)"
        }
    }
}
