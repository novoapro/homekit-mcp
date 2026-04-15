import Foundation

// MARK: - State Variable Type

enum StateVariableType: String, Codable, CaseIterable, Identifiable {
    case number
    case string
    case boolean
    case datetime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .number: return "Number"
        case .string: return "String"
        case .boolean: return "Boolean"
        case .datetime: return "Date & Time"
        }
    }

    var icon: String {
        switch self {
        case .number: return "number"
        case .string: return "textformat"
        case .boolean: return "switch.2"
        case .datetime: return "calendar.badge.clock"
        }
    }

    var symbol: String {
        switch self {
        case .number: return "#"
        case .string: return "Aa"
        case .boolean: return "◉"
        case .datetime: return "⏱"
        }
    }
}

// MARK: - State Variable

struct StateVariable: Identifiable, Codable {
    let id: UUID
    var name: String
    var displayName: String?
    let type: StateVariableType
    var value: AnyCodable
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        type: StateVariableType,
        value: AnyCodable,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.type = type
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The human-readable label — falls back to `name` if no displayName is set.
    var label: String {
        if let dn = displayName, !dn.isEmpty { return dn }
        return name
    }

    /// Returns the numeric value if this is a `.number` variable.
    var numberValue: Double? {
        if let d = value.value as? Double { return d }
        if let i = value.value as? Int { return Double(i) }
        if let n = value.value as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Returns the boolean value if this is a `.boolean` variable.
    var boolValue: Bool? {
        value.value as? Bool
    }

    /// Returns the string value if this is a `.string` variable.
    var stringValue: String? {
        value.value as? String
    }

    /// Returns the date value if this is a `.datetime` variable (stored as ISO 8601 string).
    var dateValue: Date? {
        guard let str = value.value as? String else { return nil }
        return Self.dateFormatter.date(from: str) ?? Self.dateFormatterFractional.date(from: str)
    }

    /// Human-readable display of the current value.
    var displayValue: String {
        switch type {
        case .number:
            if let d = numberValue {
                return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
            }
            return "\(value.value)"
        case .string:
            return stringValue ?? "\(value.value)"
        case .boolean:
            return boolValue == true ? "true" : "false"
        case .datetime:
            if let date = dateValue {
                return Self.displayFormatter.string(from: date)
            }
            return stringValue ?? "\(value.value)"
        }
    }

    // MARK: - Date Formatters

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Parses an ISO 8601 string to a Date. Also handles special sentinel values:
    /// - `"__now__"` — current server time
    /// - `"__now-24h__"` — 24 hours ago (supports: s, m, h, d units with +/- offset)
    /// - `"__now+7d__"` — 7 days from now
    static func parseDate(_ value: Any?) -> Date? {
        if let str = value as? String {
            if str == "__now__" { return Date() }
            // Relative time: __now±Xu__ where X is a number and u is s/m/h/d
            if str.hasPrefix("__now") && str.hasSuffix("__") {
                let inner = str.dropFirst(5).dropLast(2) // e.g. "-24h" or "+7d"
                if let parsed = parseRelativeOffset(String(inner)) {
                    return Date().addingTimeInterval(parsed)
                }
            }
            return dateFormatter.date(from: str) ?? dateFormatterFractional.date(from: str)
        }
        // Also handle epoch timestamps stored as numbers
        if let d = value as? Double { return Date(timeIntervalSince1970: d) }
        if let i = value as? Int { return Date(timeIntervalSince1970: Double(i)) }
        return nil
    }

    /// Parses a relative offset string like "-24h", "+7d", "-30m", "+3600s".
    private static func parseRelativeOffset(_ offset: String) -> TimeInterval? {
        guard !offset.isEmpty else { return nil }
        let unitChar = offset.last!
        let multiplier: Double
        switch unitChar {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        case "d": multiplier = 86400
        default: return nil
        }
        guard let amount = Double(offset.dropLast()) else { return nil }
        return amount * multiplier
    }

    /// Returns true if the string is a datetime sentinel (__now__, __now-24h__, etc.)
    static func isDatetimeSentinel(_ value: String) -> Bool {
        value == "__now__" || (value.hasPrefix("__now") && value.hasSuffix("__"))
    }

    /// Human-readable description of a datetime sentinel.
    static func describeSentinel(_ value: String) -> String? {
        if value == "__now__" { return "Now" }
        guard value.hasPrefix("__now") && value.hasSuffix("__") else { return nil }
        let inner = String(value.dropFirst(5).dropLast(2))
        guard !inner.isEmpty else { return nil }
        let unitChar = inner.last!
        let unitName: String
        switch unitChar {
        case "s": unitName = "second"
        case "m": unitName = "minute"
        case "h": unitName = "hour"
        case "d": unitName = "day"
        default: return nil
        }
        guard let amount = Double(inner.dropLast()) else { return nil }
        let absAmount = abs(amount)
        let amountStr = absAmount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(absAmount)) : String(absAmount)
        let plural = absAmount == 1 ? "" : "s"
        if amount < 0 {
            return "\(amountStr) \(unitName)\(plural) ago"
        } else {
            return "\(amountStr) \(unitName)\(plural) from now"
        }
    }

    /// Formats a Date as ISO 8601 string for storage.
    static func formatDateISO(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

// MARK: - State Variable Reference

/// Identifies a state variable by name or by ID.
enum StateVariableRef: Codable, Equatable {
    case byName(String)
    case byId(UUID)

    private enum RefType: String, Codable {
        case byName
        case byId
    }

    private enum CodingKeys: String, CodingKey {
        case type, name, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let refType = try container.decode(RefType.self, forKey: .type)
        switch refType {
        case .byName:
            self = try .byName(container.decode(String.self, forKey: .name))
        case .byId:
            self = try .byId(container.decode(UUID.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .byName(name):
            try container.encode(RefType.byName, forKey: .type)
            try container.encode(name, forKey: .name)
        case let .byId(id):
            try container.encode(RefType.byId, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }

    var displayDescription: String {
        switch self {
        case let .byName(name): return "'\(name)'"
        case let .byId(id): return "id:\(id.uuidString.prefix(8))"
        }
    }
}

// MARK: - State Variable Operation

enum StateVariableOperation: Codable {
    // CRUD
    case create(name: String, variableType: StateVariableType, initialValue: AnyCodable)
    case remove(variableRef: StateVariableRef)
    case set(variableRef: StateVariableRef, value: AnyCodable)

    // Number operations
    case increment(variableRef: StateVariableRef, by: Double)
    case decrement(variableRef: StateVariableRef, by: Double)
    case multiply(variableRef: StateVariableRef, by: Double)
    case addState(variableRef: StateVariableRef, otherRef: StateVariableRef)
    case subtractState(variableRef: StateVariableRef, otherRef: StateVariableRef)

    // Boolean operations
    case toggle(variableRef: StateVariableRef)
    case andState(variableRef: StateVariableRef, otherRef: StateVariableRef)
    case orState(variableRef: StateVariableRef, otherRef: StateVariableRef)
    case notState(variableRef: StateVariableRef)

    // DateTime operations
    case setToNow(variableRef: StateVariableRef)
    case addTime(variableRef: StateVariableRef, amount: Double, unit: TimeUnit)
    case subtractTime(variableRef: StateVariableRef, amount: Double, unit: TimeUnit)

    // Device characteristic operations
    case setFromCharacteristic(variableRef: StateVariableRef, deviceId: String, characteristicId: String, serviceId: String?)

    /// Time unit for datetime arithmetic.
    enum TimeUnit: String, Codable, CaseIterable, Identifiable {
        case seconds, minutes, hours, days
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .seconds: return "Seconds"
            case .minutes: return "Minutes"
            case .hours: return "Hours"
            case .days: return "Days"
            }
        }
        var inSeconds: Double {
            switch self {
            case .seconds: return 1
            case .minutes: return 60
            case .hours: return 3600
            case .days: return 86400
            }
        }
    }

    private enum OperationType: String, Codable {
        case create, remove, set
        case increment, decrement, multiply, addState, subtractState
        case toggle, andState, orState, notState
        case setToNow, addTime, subtractTime
        case setFromCharacteristic
    }

    private enum CodingKeys: String, CodingKey {
        case operation
        case name, variableType, initialValue
        case variableRef, value
        case by
        case otherRef
        case amount, unit
        case deviceId, characteristicId, serviceId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(OperationType.self, forKey: .operation)
        switch op {
        case .create:
            self = try .create(
                name: container.decode(String.self, forKey: .name),
                variableType: container.decode(StateVariableType.self, forKey: .variableType),
                initialValue: container.decode(AnyCodable.self, forKey: .initialValue)
            )
        case .remove:
            self = try .remove(variableRef: container.decode(StateVariableRef.self, forKey: .variableRef))
        case .set:
            self = try .set(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                value: container.decode(AnyCodable.self, forKey: .value)
            )
        case .increment:
            self = try .increment(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                by: container.decode(Double.self, forKey: .by)
            )
        case .decrement:
            self = try .decrement(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                by: container.decode(Double.self, forKey: .by)
            )
        case .multiply:
            self = try .multiply(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                by: container.decode(Double.self, forKey: .by)
            )
        case .addState:
            self = try .addState(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                otherRef: container.decode(StateVariableRef.self, forKey: .otherRef)
            )
        case .subtractState:
            self = try .subtractState(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                otherRef: container.decode(StateVariableRef.self, forKey: .otherRef)
            )
        case .toggle:
            self = try .toggle(variableRef: container.decode(StateVariableRef.self, forKey: .variableRef))
        case .andState:
            self = try .andState(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                otherRef: container.decode(StateVariableRef.self, forKey: .otherRef)
            )
        case .orState:
            self = try .orState(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                otherRef: container.decode(StateVariableRef.self, forKey: .otherRef)
            )
        case .notState:
            self = try .notState(variableRef: container.decode(StateVariableRef.self, forKey: .variableRef))
        case .setToNow:
            self = try .setToNow(variableRef: container.decode(StateVariableRef.self, forKey: .variableRef))
        case .addTime:
            self = try .addTime(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                amount: container.decode(Double.self, forKey: .amount),
                unit: container.decode(TimeUnit.self, forKey: .unit)
            )
        case .subtractTime:
            self = try .subtractTime(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                amount: container.decode(Double.self, forKey: .amount),
                unit: container.decode(TimeUnit.self, forKey: .unit)
            )
        case .setFromCharacteristic:
            self = try .setFromCharacteristic(
                variableRef: container.decode(StateVariableRef.self, forKey: .variableRef),
                deviceId: container.decode(String.self, forKey: .deviceId),
                characteristicId: container.decode(String.self, forKey: .characteristicId),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .create(name, variableType, initialValue):
            try container.encode(OperationType.create, forKey: .operation)
            try container.encode(name, forKey: .name)
            try container.encode(variableType, forKey: .variableType)
            try container.encode(initialValue, forKey: .value)
        case let .remove(ref):
            try container.encode(OperationType.remove, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
        case let .set(ref, value):
            try container.encode(OperationType.set, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(value, forKey: .value)
        case let .increment(ref, amount):
            try container.encode(OperationType.increment, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(amount, forKey: .by)
        case let .decrement(ref, amount):
            try container.encode(OperationType.decrement, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(amount, forKey: .by)
        case let .multiply(ref, amount):
            try container.encode(OperationType.multiply, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(amount, forKey: .by)
        case let .addState(ref, otherRef):
            try container.encode(OperationType.addState, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(otherRef, forKey: .otherRef)
        case let .subtractState(ref, otherRef):
            try container.encode(OperationType.subtractState, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(otherRef, forKey: .otherRef)
        case let .toggle(ref):
            try container.encode(OperationType.toggle, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
        case let .andState(ref, otherRef):
            try container.encode(OperationType.andState, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(otherRef, forKey: .otherRef)
        case let .orState(ref, otherRef):
            try container.encode(OperationType.orState, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(otherRef, forKey: .otherRef)
        case let .notState(ref):
            try container.encode(OperationType.notState, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
        case let .setToNow(ref):
            try container.encode(OperationType.setToNow, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
        case let .addTime(ref, amount, unit):
            try container.encode(OperationType.addTime, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        case let .subtractTime(ref, amount, unit):
            try container.encode(OperationType.subtractTime, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        case let .setFromCharacteristic(ref, deviceId, characteristicId, serviceId):
            try container.encode(OperationType.setFromCharacteristic, forKey: .operation)
            try container.encode(ref, forKey: .variableRef)
            try container.encode(deviceId, forKey: .deviceId)
            try container.encode(characteristicId, forKey: .characteristicId)
            try container.encodeIfPresent(serviceId, forKey: .serviceId)
        }
    }

    var displayName: String {
        switch self {
        case .create: return "Create Variable"
        case .remove: return "Remove Variable"
        case .set: return "Set Value"
        case .setFromCharacteristic: return "Set from Device"
        case .setToNow: return "Set to Now"
        case .addTime: return "Add Time"
        case .subtractTime: return "Subtract Time"
        case .increment: return "Increment"
        case .decrement: return "Decrement"
        case .multiply: return "Multiply"
        case .addState: return "Add State"
        case .subtractState: return "Subtract State"
        case .toggle: return "Toggle"
        case .andState: return "AND State"
        case .orState: return "OR State"
        case .notState: return "NOT State"
        }
    }

    /// The operation type string for Codable and display.
    var operationType: String {
        switch self {
        case .create: return "create"
        case .remove: return "remove"
        case .set: return "set"
        case .setToNow: return "setToNow"
        case .addTime: return "addTime"
        case .subtractTime: return "subtractTime"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .multiply: return "multiply"
        case .addState: return "addState"
        case .subtractState: return "subtractState"
        case .toggle: return "toggle"
        case .andState: return "andState"
        case .orState: return "orState"
        case .notState: return "notState"
        case .setFromCharacteristic: return "setFromCharacteristic"
        }
    }
}

// MARK: - State Variable Action (for AutomationAction)

struct StateVariableAction {
    let operation: StateVariableOperation
    let name: String?

    init(operation: StateVariableOperation, name: String? = nil) {
        self.operation = operation
        self.name = name
    }
}

// MARK: - Engine State Condition (for AutomationCondition)

struct EngineStateCondition {
    let variableRef: StateVariableRef
    let comparison: ComparisonOperator
    /// When set, compare against another variable's current value instead of the literal in `comparison`.
    let compareToStateRef: StateVariableRef?
    /// When set (e.g. "__now__", "__now-24h__"), the comparison value is resolved dynamically
    /// at evaluation time instead of using the static value in `comparison`.
    let dynamicDateValue: String?

    init(variableRef: StateVariableRef, comparison: ComparisonOperator, compareToStateRef: StateVariableRef? = nil, dynamicDateValue: String? = nil) {
        self.variableRef = variableRef
        self.comparison = comparison
        self.compareToStateRef = compareToStateRef
        self.dynamicDateValue = dynamicDateValue
    }
}

// MARK: - State Variable Reference Scanning

enum StateVariableReferenceScanner {

    /// Returns the IDs of all automations that reference a given state variable name
    /// in their blocks (stateVariable actions) or conditions (engineState).
    static func automationsReferencing(stateName: String, in automations: [Automation]) -> [Automation] {
        automations.filter { automation in
            blocksReference(stateName: stateName, in: automation.blocks) ||
            conditionsReference(stateName: stateName, in: automation.conditions ?? []) ||
            triggersReference(stateName: stateName, in: automation.triggers)
        }
    }

    // MARK: - Blocks

    private static func blocksReference(stateName: String, in blocks: [AutomationBlock]) -> Bool {
        for block in blocks {
            switch block {
            case let .action(action, _):
                if actionReferences(stateName: stateName, action: action) { return true }
            case let .flowControl(fc, _):
                if flowControlReferences(stateName: stateName, fc: fc) { return true }
            }
        }
        return false
    }

    private static func actionReferences(stateName: String, action: AutomationAction) -> Bool {
        switch action {
        case let .stateVariable(a):
            return operationReferences(stateName: stateName, operation: a.operation)
        case let .controlDevice(a):
            if let ref = a.valueRef { return refMatches(ref, name: stateName) }
            return false
        default:
            return false
        }
    }

    private static func operationReferences(stateName: String, operation: StateVariableOperation) -> Bool {
        switch operation {
        case let .create(name, _, _):
            return name == stateName
        case let .remove(ref), let .set(ref, _),
             let .increment(ref, _), let .decrement(ref, _), let .multiply(ref, _),
             let .toggle(ref), let .notState(ref),
             let .setToNow(ref), let .addTime(ref, _, _), let .subtractTime(ref, _, _),
             let .setFromCharacteristic(ref, _, _, _):
            return refMatches(ref, name: stateName)
        case let .addState(ref, otherRef), let .subtractState(ref, otherRef),
             let .andState(ref, otherRef), let .orState(ref, otherRef):
            return refMatches(ref, name: stateName) || refMatches(otherRef, name: stateName)
        }
    }

    private static func flowControlReferences(stateName: String, fc: FlowControlBlock) -> Bool {
        switch fc {
        case let .conditional(b):
            if conditionReferences(stateName: stateName, condition: b.condition) { return true }
            if blocksReference(stateName: stateName, in: b.thenBlocks) { return true }
            if let elseBlocks = b.elseBlocks, blocksReference(stateName: stateName, in: elseBlocks) { return true }
        case let .repeatWhile(b):
            if conditionReferences(stateName: stateName, condition: b.condition) { return true }
            if blocksReference(stateName: stateName, in: b.blocks) { return true }
        case let .waitForState(b):
            if conditionReferences(stateName: stateName, condition: b.condition) { return true }
        case let .repeat(b):
            if blocksReference(stateName: stateName, in: b.blocks) { return true }
        case let .group(b):
            if blocksReference(stateName: stateName, in: b.blocks) { return true }
        default:
            break
        }
        return false
    }

    // MARK: - Conditions

    private static func conditionsReference(stateName: String, in conditions: [AutomationCondition]) -> Bool {
        conditions.contains { conditionReferences(stateName: stateName, condition: $0) }
    }

    private static func conditionReferences(stateName: String, condition: AutomationCondition) -> Bool {
        switch condition {
        case let .engineState(c):
            if refMatches(c.variableRef, name: stateName) { return true }
            if let otherRef = c.compareToStateRef, refMatches(otherRef, name: stateName) { return true }
            return false
        case let .and(children), let .or(children):
            return children.contains { conditionReferences(stateName: stateName, condition: $0) }
        case let .not(inner):
            return conditionReferences(stateName: stateName, condition: inner)
        default:
            return false
        }
    }

    // MARK: - Triggers (per-trigger guard conditions)

    private static func triggersReference(stateName: String, in triggers: [AutomationTrigger]) -> Bool {
        for trigger in triggers {
            if let conditions = triggerConditions(trigger), conditionsReference(stateName: stateName, in: conditions) {
                return true
            }
        }
        return false
    }

    private static func triggerConditions(_ trigger: AutomationTrigger) -> [AutomationCondition]? {
        switch trigger {
        case let .deviceStateChange(t): return t.conditions
        case let .schedule(t): return t.conditions
        case let .webhook(t): return t.conditions
        case let .automation(t): return t.conditions
        case let .sunEvent(t): return t.conditions
        }
    }

    // MARK: - Collect All Referenced Names

    /// Collects all state variable names referenced in an automation (blocks + conditions + triggers).
    static func collectReferencedStateNames(in automation: Automation) -> Set<String> {
        var names = Set<String>()
        collectNamesFromBlocks(automation.blocks, into: &names)
        for condition in automation.conditions ?? [] {
            collectNamesFromCondition(condition, into: &names)
        }
        for trigger in automation.triggers {
            if let conditions = triggerConditions(trigger) {
                for c in conditions { collectNamesFromCondition(c, into: &names) }
            }
        }
        return names
    }

    private static func collectNamesFromBlocks(_ blocks: [AutomationBlock], into names: inout Set<String>) {
        for block in blocks {
            switch block {
            case let .action(action, _):
                if case let .stateVariable(a) = action {
                    collectNamesFromOperation(a.operation, into: &names)
                }
                if case let .controlDevice(a) = action, let ref = a.valueRef {
                    if case let .byName(n) = ref { names.insert(n) }
                }
            case let .flowControl(fc, _):
                switch fc {
                case let .conditional(b):
                    collectNamesFromCondition(b.condition, into: &names)
                    collectNamesFromBlocks(b.thenBlocks, into: &names)
                    if let elseBlocks = b.elseBlocks { collectNamesFromBlocks(elseBlocks, into: &names) }
                case let .repeatWhile(b):
                    collectNamesFromCondition(b.condition, into: &names)
                    collectNamesFromBlocks(b.blocks, into: &names)
                case let .waitForState(b):
                    collectNamesFromCondition(b.condition, into: &names)
                case let .repeat(b): collectNamesFromBlocks(b.blocks, into: &names)
                case let .group(b): collectNamesFromBlocks(b.blocks, into: &names)
                default: break
                }
            }
        }
    }

    private static func collectNamesFromOperation(_ operation: StateVariableOperation, into names: inout Set<String>) {
        switch operation {
        case let .create(name, _, _): names.insert(name)
        case let .remove(ref), let .set(ref, _),
             let .increment(ref, _), let .decrement(ref, _), let .multiply(ref, _),
             let .toggle(ref), let .notState(ref),
             let .setToNow(ref), let .addTime(ref, _, _), let .subtractTime(ref, _, _),
             let .setFromCharacteristic(ref, _, _, _):
            if case let .byName(n) = ref { names.insert(n) }
        case let .addState(ref, otherRef), let .subtractState(ref, otherRef),
             let .andState(ref, otherRef), let .orState(ref, otherRef):
            if case let .byName(n) = ref { names.insert(n) }
            if case let .byName(n) = otherRef { names.insert(n) }
        }
    }

    private static func collectNamesFromCondition(_ condition: AutomationCondition, into names: inout Set<String>) {
        switch condition {
        case let .engineState(c):
            if case let .byName(n) = c.variableRef { names.insert(n) }
            if let ref = c.compareToStateRef, case let .byName(n) = ref { names.insert(n) }
        case let .and(children), let .or(children):
            for child in children { collectNamesFromCondition(child, into: &names) }
        case let .not(inner):
            collectNamesFromCondition(inner, into: &names)
        default: break
        }
    }

    // MARK: - Helpers

    private static func refMatches(_ ref: StateVariableRef, name: String) -> Bool {
        if case let .byName(n) = ref { return n == name }
        return false
    }
}
