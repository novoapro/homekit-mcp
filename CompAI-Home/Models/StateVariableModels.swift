import Foundation

// MARK: - State Variable Type

enum StateVariableType: String, Codable, CaseIterable, Identifiable {
    case number
    case string
    case boolean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .number: return "Number"
        case .string: return "String"
        case .boolean: return "Boolean"
        }
    }

    var icon: String {
        switch self {
        case .number: return "number"
        case .string: return "textformat"
        case .boolean: return "switch.2"
        }
    }

    var symbol: String {
        switch self {
        case .number: return "#"
        case .string: return "Aa"
        case .boolean: return "◉"
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
        }
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

    private enum OperationType: String, Codable {
        case create, remove, set
        case increment, decrement, multiply, addState, subtractState
        case toggle, andState, orState, notState
    }

    private enum CodingKeys: String, CodingKey {
        case operation
        case name, variableType, initialValue
        case variableRef, value
        case by
        case otherRef
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
        }
    }

    var displayName: String {
        switch self {
        case .create: return "Create Variable"
        case .remove: return "Remove Variable"
        case .set: return "Set Value"
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
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .multiply: return "multiply"
        case .addState: return "addState"
        case .subtractState: return "subtractState"
        case .toggle: return "toggle"
        case .andState: return "andState"
        case .orState: return "orState"
        case .notState: return "notState"
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

    init(variableRef: StateVariableRef, comparison: ComparisonOperator, compareToStateRef: StateVariableRef? = nil) {
        self.variableRef = variableRef
        self.comparison = comparison
        self.compareToStateRef = compareToStateRef
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
        guard case let .stateVariable(a) = action else { return false }
        return operationReferences(stateName: stateName, operation: a.operation)
    }

    private static func operationReferences(stateName: String, operation: StateVariableOperation) -> Bool {
        switch operation {
        case let .create(name, _, _):
            return name == stateName
        case let .remove(ref), let .set(ref, _),
             let .increment(ref, _), let .decrement(ref, _), let .multiply(ref, _),
             let .toggle(ref), let .notState(ref):
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
             let .toggle(ref), let .notState(ref):
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
