import Foundation

/// Evaluates `WorkflowCondition` guard expressions against current device state.
/// Used by the engine for pre-execution guards, conditional blocks, and repeatWhile blocks.
struct ConditionEvaluator {
    private let homeKitManager: HomeKitManager
    private let storage: StorageService?
    private let loggingService: LoggingService?
    private let registry: DeviceRegistryService?

    /// Workflow context for orphan logging. Set by the engine before evaluation.
    var workflowId: UUID?
    var workflowName: String?

    /// Block execution results from the current run, keyed by stable block ID.
    /// Only populated during workflow execution; empty for standalone condition tests.
    var blockResults: [UUID: ExecutionStatus] = [:]

    init(homeKitManager: HomeKitManager, storage: StorageService? = nil, loggingService: LoggingService? = nil, registry: DeviceRegistryService? = nil) {
        self.homeKitManager = homeKitManager
        self.storage = storage
        self.loggingService = loggingService
        self.registry = registry
    }

    /// Evaluate a single condition. Returns a tree-structured result with sub-results for compound conditions.
    func evaluate(_ condition: WorkflowCondition) async -> ConditionResult {
        switch condition {
        case .and(let conditions):
            var allPassed = true
            var subResults: [ConditionResult] = []
            for c in conditions {
                let sub = await evaluate(c)
                subResults.append(sub)
                if !sub.passed { allPassed = false }
            }
            let descriptions = subResults.map(\.conditionDescription)
            return ConditionResult(
                conditionDescription: "AND(\(descriptions.joined(separator: ", ")))",
                passed: allPassed,
                subResults: subResults,
                logicOperator: "AND"
            )
        case .or(let conditions):
            var anyPassed = false
            var subResults: [ConditionResult] = []
            for c in conditions {
                let sub = await evaluate(c)
                subResults.append(sub)
                if sub.passed { anyPassed = true }
            }
            let descriptions = subResults.map(\.conditionDescription)
            return ConditionResult(
                conditionDescription: "OR(\(descriptions.joined(separator: ", ")))",
                passed: anyPassed,
                subResults: subResults,
                logicOperator: "OR"
            )
        case .not(let inner):
            let innerResult = await evaluate(inner)
            return ConditionResult(
                conditionDescription: "NOT(\(innerResult.conditionDescription))",
                passed: !innerResult.passed,
                subResults: [innerResult],
                logicOperator: "NOT"
            )
        default:
            let (passed, description) = await evaluateLeaf(condition)
            return ConditionResult(conditionDescription: description, passed: passed)
        }
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

    /// Evaluate a leaf condition (deviceState, timeCondition, sceneActive). Compound conditions are handled by `evaluate(_:)`.
    private func evaluateLeaf(_ condition: WorkflowCondition) async -> (Bool, String) {
        switch condition {
        case .deviceState(let cond):
            return await evaluateDeviceState(cond)
        case .timeCondition(let cond):
            return evaluateTimeCondition(cond)
        case .sceneActive(let cond):
            return await evaluateSceneActive(cond)
        case .blockResult(let cond):
            return evaluateBlockResult(cond)
        case .and, .or, .not:
            // Should not reach here — compound conditions are handled in evaluate(_:)
            return (false, "Unexpected compound condition in leaf evaluator")
        }
    }

    private func evaluateBlockResult(_ condition: BlockResultCondition) -> (Bool, String) {
        let wfName = workflowName ?? "Unknown"
        switch condition.scope {
        case .specific(let blockId):
            guard let status = blockResults[blockId] else {
                AppLogger.workflow.warning("[\(wfName)] Block Result condition: block \(blockId.uuidString.prefix(8)) has no result (not yet executed) — evaluating as false")
                return (false, "Block \(blockId.uuidString.prefix(8)): not yet executed — evaluated as false")
            }
            let passed = status == condition.expectedStatus
            return (passed, "Block \(blockId.uuidString.prefix(8)) is \(status.displayName) (expected \(condition.expectedStatus.displayName)) = \(passed)")
        case .all:
            guard !blockResults.isEmpty else {
                AppLogger.workflow.warning("[\(wfName)] Block Result condition: no blocks executed yet — evaluating as false")
                return (false, "All blocks: no blocks executed yet — evaluated as false")
            }
            let allMatch = blockResults.values.allSatisfy { $0 == condition.expectedStatus }
            return (allMatch, "All \(blockResults.count) blocks are \(condition.expectedStatus.displayName) = \(allMatch)")
        case .any:
            guard !blockResults.isEmpty else {
                AppLogger.workflow.warning("[\(wfName)] Block Result condition: no blocks executed yet — evaluating as false")
                return (false, "Any block: no blocks executed yet — evaluated as false")
            }
            let anyMatch = blockResults.values.contains(condition.expectedStatus)
            return (anyMatch, "Any block is \(condition.expectedStatus.displayName) = \(anyMatch)")
        }
    }

    private func evaluateDeviceState(_ condition: DeviceStateCondition) async -> (Bool, String) {
        let resolvedType = registry?.readCharacteristicType(forStableId: condition.characteristicId)
            ?? CharacteristicTypes.characteristicType(forName: condition.characteristicId)
            ?? condition.characteristicId
        let displayName = CharacteristicTypes.displayName(for: resolvedType)

        guard let device = await MainActor.run(body: { homeKitManager.getDeviceState(id: condition.deviceId) }) else {
            await logOrphan(
                location: "condition",
                detail: "\(displayName): device not found"
            )
            return (false, "\(displayName): device not found — orphaned reference")
        }

        var currentValue = findCharacteristicValue(in: device, characteristicType: resolvedType, serviceId: condition.serviceId)
        // Convert temperature to user's preferred unit before comparing against user-defined thresholds
        if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(resolvedType) {
            if let v = currentValue as? Double { currentValue = TemperatureConversion.celsiusToFahrenheit(v) }
            else if let v = currentValue as? Int { currentValue = TemperatureConversion.celsiusToFahrenheit(Double(v)) }
        }
        let passed = Self.compare(currentValue as Any, using: condition.comparison)
        let compDesc = Self.comparisonDescription(condition.comparison)

        let roomPart = device.roomName.map { " (\($0))" } ?? ""
        let svcName = resolveServiceDisplayName(in: device, serviceId: condition.serviceId)
        let svcPart = svcName.map { "\($0)." } ?? ""
        return (passed, "\(device.name)\(roomPart) \(svcPart)\(displayName) \(compDesc) = \(passed)")
    }

    private func evaluateTimeCondition(_ condition: TimeCondition) -> (Bool, String) {
        let modeDesc = condition.mode.displayName

        // Time range mode doesn't need location
        if condition.mode == .timeRange {
            return evaluateTimeRange(condition)
        }

        // All other modes need solar calculations
        let latitude = storage?.readSunEventLatitude() ?? 0
        let longitude = storage?.readSunEventLongitude() ?? 0

        guard latitude != 0 || longitude != 0 else {
            return (false, "\(modeDesc): location not configured")
        }

        let now = Date()
        let (sunrise, sunset) = SolarCalculator.sunTimes(for: now, latitude: latitude, longitude: longitude)

        switch condition.mode {
        case .beforeSunrise:
            // Night before dawn: between yesterday's sunset and today's sunrise
            guard let sunrise, let sunset else { return (false, "\(modeDesc): cannot compute (polar region)") }
            let passed = now < sunrise || now > sunset
            return (passed, "\(modeDesc) = \(passed)")

        case .afterSunrise:
            // Daytime: between today's sunrise and sunset
            guard let sunrise, let sunset else { return (false, "\(modeDesc): cannot compute (polar region)") }
            let passed = now > sunrise && now < sunset
            return (passed, "\(modeDesc) = \(passed)")

        case .beforeSunset:
            // Daytime (before dusk): between today's sunrise and sunset
            guard let sunrise, let sunset else { return (false, "\(modeDesc): cannot compute (polar region)") }
            let passed = now > sunrise && now < sunset
            return (passed, "\(modeDesc) = \(passed)")

        case .afterSunset:
            // Nighttime (after dusk): between today's sunset and tomorrow's sunrise
            guard let sunrise, let sunset else { return (false, "\(modeDesc): cannot compute (polar region)") }
            let passed = now < sunrise || now > sunset
            return (passed, "\(modeDesc) = \(passed)")

        case .daytime:
            guard let sunrise, let sunset else { return (false, "\(modeDesc): cannot compute (polar region)") }
            let passed = now > sunrise && now < sunset
            return (passed, "\(modeDesc) = \(passed)")

        case .nighttime:
            guard let sunrise, let sunset else { return (false, "\(modeDesc): cannot compute (polar region)") }
            let passed = now < sunrise || now > sunset
            return (passed, "\(modeDesc) = \(passed)")

        case .timeRange:
            return evaluateTimeRange(condition) // unreachable, handled above
        }
    }

    private func evaluateTimeRange(_ condition: TimeCondition) -> (Bool, String) {
        guard let start = condition.startTime, let end = condition.endTime else {
            return (false, "Time Range: start/end time not configured")
        }

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMins = hour * 60 + minute
        let startMins = start.totalMinutes
        let endMins = end.totalMinutes

        let passed: Bool
        if startMins <= endMins {
            // Same-day range (e.g., 9:00–17:00)
            passed = nowMins >= startMins && nowMins < endMins
        } else {
            // Cross-midnight range (e.g., 23:00–02:00)
            passed = nowMins >= startMins || nowMins < endMins
        }

        return (passed, "Time Range \(start.formatted)–\(end.formatted) = \(passed)")
    }

    private func evaluateSceneActive(_ condition: SceneActiveCondition) async -> (Bool, String) {
        guard let scene = await MainActor.run(body: { homeKitManager.getScene(id: condition.sceneId) }) else {
            return (false, "Scene not found")
        }

        var allMatch = true
        for action in scene.actions {
            guard let device = await MainActor.run(body: { homeKitManager.getDeviceState(id: action.deviceId) }) else {
                await logOrphan(
                    location: "scene condition '\(scene.name)'",
                    detail: "device in scene not found"
                )
                allMatch = false
                break
            }

            let currentValue = findCharacteristicValue(in: device, characteristicType: action.characteristicType, serviceId: nil)
            if !Self.valuesEqual(currentValue, action.targetValue.value) {
                allMatch = false
                break
            }
        }

        if condition.isActive {
            // Checking if scene IS active
            return (allMatch, allMatch ? "Scene '\(scene.name)' is active" : "Scene '\(scene.name)' is not active")
        } else {
            // Checking if scene is NOT active
            return (!allMatch, !allMatch ? "Scene '\(scene.name)' is not active" : "Scene '\(scene.name)' is active")
        }
    }

    private func findCharacteristicValue(in device: DeviceModel, characteristicType: String, serviceId: String?) -> Any? {
        let services: [ServiceModel]
        if let serviceId {
            // Resolve stable registry ID → HomeKit UUID for service matching
            let resolvedServiceId = registry?.readHomeKitServiceId(serviceId) ?? serviceId
            services = device.services.filter { $0.id == resolvedServiceId }
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

    private func resolveServiceDisplayName(in device: DeviceModel, serviceId: String?) -> String? {
        guard let serviceId else { return nil }
        let resolvedId = registry?.readHomeKitServiceId(serviceId) ?? serviceId
        return device.services.first(where: { $0.id == resolvedId })?.displayName
    }

    // MARK: - Orphan Logging

    private func logOrphan(location: String, detail: String) async {
        guard let workflowName else { return }

        // Orphan details are captured in the WorkflowExecutionLog's condition/block results.
        AppLogger.workflow.warning("[\(workflowName)] Orphaned reference in \(location): unknown device")
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

    /// Convert a value to Double for numeric comparison.
    /// Supports Bool, Int, Double, Float, and String (including "true"/"false").
    static func toDouble(_ value: Any) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        if let v = value as? Bool { return v ? 1.0 : 0.0 }
        if let v = value as? Float { return Double(v) }
        if let v = value as? String {
            if let d = Double(v) { return d }
            let lowered = v.lowercased()
            if lowered == "true" { return 1.0 }
            if lowered == "false" { return 0.0 }
        }
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
