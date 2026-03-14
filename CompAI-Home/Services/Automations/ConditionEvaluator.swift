import Foundation

/// Evaluates `AutomationCondition` guard expressions against current device state.
/// Used by the engine for pre-execution guards, conditional blocks, and repeatWhile blocks.
class ConditionEvaluator {
    private let homeKitManager: HomeKitManager
    private let storage: StorageService?
    private let loggingService: LoggingService?
    private let registry: DeviceRegistryService?

    /// Automation context for orphan logging. Set by the engine before evaluation.
    var automationId: UUID?
    var automationName: String?

    /// Block execution results from the current run, keyed by stable block ID.
    /// Only populated during automation execution; empty for standalone condition tests.
    var blockResults: [UUID: ExecutionStatus] = [:]

    init(homeKitManager: HomeKitManager, storage: StorageService? = nil, loggingService: LoggingService? = nil, registry: DeviceRegistryService? = nil) {
        self.homeKitManager = homeKitManager
        self.storage = storage
        self.loggingService = loggingService
        self.registry = registry
    }

    /// Evaluate a single condition. Returns a tree-structured result with sub-results for compound conditions.
    func evaluate(_ condition: AutomationCondition) async -> ConditionResult {
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
                conditionDescription: "(\(descriptions.joined(separator: ", ")))",
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
                conditionDescription: "(\(descriptions.joined(separator: ", ")))",
                passed: anyPassed,
                subResults: subResults,
                logicOperator: "OR"
            )
        case .not(let inner):
            let innerResult = await evaluate(inner)
            return ConditionResult(
                conditionDescription: "(\(innerResult.conditionDescription))",
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
    /// Pre-fetches all needed device states in a single MainActor hop to avoid per-condition round-trips.
    func evaluateAll(_ conditions: [AutomationCondition]) async -> (allPassed: Bool, results: [ConditionResult]) {
        // Batch-fetch all device states needed by any condition in one MainActor call
        let deviceIds = Self.collectDeviceIds(from: conditions)
        if !deviceIds.isEmpty {
            prefetchedDeviceStates = await MainActor.run {
                Dictionary(uniqueKeysWithValues: deviceIds.compactMap { id in
                    homeKitManager.getDeviceState(id: id).map { (id, $0) }
                })
            }
        }

        var results: [ConditionResult] = []
        var allPassed = true
        for condition in conditions {
            let result = await evaluate(condition)
            results.append(result)
            if !result.passed {
                allPassed = false
            }
        }
        prefetchedDeviceStates = nil
        return (allPassed, results)
    }

    /// Pre-fetched device states for the current evaluation batch.
    /// Set by `evaluateAll` before evaluating conditions, cleared after.
    private var prefetchedDeviceStates: [String: DeviceModel]?

    /// Recursively collects all device IDs referenced by deviceState conditions.
    private static func collectDeviceIds(from conditions: [AutomationCondition]) -> Set<String> {
        var ids = Set<String>()
        for condition in conditions {
            collectDeviceIds(from: condition, into: &ids)
        }
        return ids
    }

    private static func collectDeviceIds(from condition: AutomationCondition, into ids: inout Set<String>) {
        switch condition {
        case .deviceState(let c):
            ids.insert(c.deviceId)
        case .and(let children), .or(let children):
            for child in children { collectDeviceIds(from: child, into: &ids) }
        case .not(let inner):
            collectDeviceIds(from: inner, into: &ids)
        default:
            break
        }
    }

    /// Evaluate a `ComparisonOperator` against a known value.
    func evaluateComparison(_ comparison: ComparisonOperator, against value: Any?) -> Bool {
        guard let value else { return false }
        return Self.compare(value, using: comparison)
    }

    // MARK: - Internal

    /// Evaluate a leaf condition (deviceState, timeCondition, blockResult). Compound conditions are handled by `evaluate(_:)`.
    private func evaluateLeaf(_ condition: AutomationCondition) async -> (Bool, String) {
        switch condition {
        case .deviceState(let cond):
            return await evaluateDeviceState(cond)
        case .timeCondition(let cond):
            return evaluateTimeCondition(cond)
        case .sceneActive:
            // Legacy: sceneActive conditions are no longer supported; always pass
            return (true, "Scene condition (legacy, always passes)")
        case .blockResult(let cond):
            return evaluateBlockResult(cond)
        case .and, .or, .not:
            // Should not reach here — compound conditions are handled in evaluate(_:)
            return (false, "Unexpected compound condition in leaf evaluator")
        }
    }

    private func evaluateBlockResult(_ condition: BlockResultCondition) -> (Bool, String) {
        let wfName = automationName ?? "Unknown"
        switch condition.scope {
        case .specific(let blockId):
            guard let status = blockResults[blockId] else {
                AppLogger.automation.warning("[\(wfName)] Block Result condition: block \(blockId.uuidString.prefix(8)) has no result (not yet executed) — evaluating as false")
                return (false, "Block \(blockId.uuidString.prefix(8)): not yet executed — evaluated as false")
            }
            let passed = status == condition.expectedStatus
            return (passed, "Block \(blockId.uuidString.prefix(8)) is \(status.displayName) (expected \(condition.expectedStatus.displayName)) = \(passed)")
        case .all:
            guard !blockResults.isEmpty else {
                AppLogger.automation.warning("[\(wfName)] Block Result condition: no blocks executed yet — evaluating as false")
                return (false, "All blocks: no blocks executed yet — evaluated as false")
            }
            let allMatch = blockResults.values.allSatisfy { $0 == condition.expectedStatus }
            return (allMatch, "All \(blockResults.count) blocks are \(condition.expectedStatus.displayName) = \(allMatch)")
        case .any:
            guard !blockResults.isEmpty else {
                AppLogger.automation.warning("[\(wfName)] Block Result condition: no blocks executed yet — evaluating as false")
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

        // Use prefetched state if available (batch path), otherwise fall back to single fetch
        let device: DeviceModel?
        if let cached = prefetchedDeviceStates?[condition.deviceId] {
            device = cached
        } else {
            device = await MainActor.run(body: { homeKitManager.getDeviceState(id: condition.deviceId) })
        }

        guard let device else {
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

        // Resolve time points (markers like sunrise/sunset need location)
        guard let startMins = resolveTimePoint(start), let endMins = resolveTimePoint(end) else {
            return (false, "Time Range: cannot resolve \(start.formatted)–\(end.formatted) (location not configured or polar region)")
        }

        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMins = hour * 60 + minute

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

    /// Resolves a TimePoint to minutes since midnight. Returns nil if location is needed but not available.
    private func resolveTimePoint(_ point: TimePoint) -> Int? {
        switch point {
        case .fixed(let tod):
            return tod.totalMinutes
        case .marker(let marker):
            switch marker {
            case .midnight: return 0
            case .noon: return 720
            case .sunrise, .sunset:
                let latitude = storage?.readSunEventLatitude() ?? 0
                let longitude = storage?.readSunEventLongitude() ?? 0
                guard latitude != 0 || longitude != 0 else { return nil }
                let now = Date()
                let (sunrise, sunset) = SolarCalculator.sunTimes(for: now, latitude: latitude, longitude: longitude)
                let calendar = Calendar.current
                if marker == .sunrise {
                    guard let sunrise else { return nil }
                    return calendar.component(.hour, from: sunrise) * 60 + calendar.component(.minute, from: sunrise)
                } else {
                    guard let sunset else { return nil }
                    return calendar.component(.hour, from: sunset) * 60 + calendar.component(.minute, from: sunset)
                }
            }
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
        guard let automationName else { return }

        // Orphan details are captured in the AutomationExecutionLog's condition/block results.
        AppLogger.automation.warning("[\(automationName)] Orphaned reference in \(location): unknown device")
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
