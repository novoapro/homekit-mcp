import Foundation

// MARK: - Draft Enums for Form Binding

enum TriggerConditionType: String, CaseIterable, Identifiable {
    case changed
    case equals
    case notEquals
    case transitioned
    case greaterThan
    case lessThan
    case greaterThanOrEqual
    case lessThanOrEqual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .changed: return "Any Change"
        case .equals: return "Equals"
        case .notEquals: return "Not Equals"
        case .transitioned: return "Transitioned"
        case .greaterThan: return "Greater Than"
        case .lessThan: return "Less Than"
        case .greaterThanOrEqual: return "Greater or Equal"
        case .lessThanOrEqual: return "Less or Equal"
        }
    }

    var requiresValue: Bool {
        self != .changed
    }
}

enum ComparisonType: String, CaseIterable, Identifiable {
    case equals
    case notEquals
    case greaterThan
    case lessThan
    case greaterThanOrEqual
    case lessThanOrEqual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equals: return "Equals"
        case .notEquals: return "Not Equals"
        case .greaterThan: return "Greater Than"
        case .lessThan: return "Less Than"
        case .greaterThanOrEqual: return "Greater or Equal"
        case .lessThanOrEqual: return "Less or Equal"
        }
    }
}

// MARK: - Top-Level Workflow Draft

struct WorkflowDraft {
    var id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var continueOnError: Bool
    var triggers: [TriggerDraft]
    var conditions: [ConditionDraft]
    var blocks: [BlockDraft]

    static func empty() -> WorkflowDraft {
        WorkflowDraft(
            id: UUID(),
            name: "",
            description: "",
            isEnabled: true,
            continueOnError: false,
            triggers: [],
            conditions: [],
            blocks: []
        )
    }
}

// MARK: - Trigger Draft

struct TriggerDraft: Identifiable {
    let id: UUID
    var name: String = ""
    var deviceId: String
    var serviceId: String?
    var characteristicType: String
    var conditionType: TriggerConditionType
    var conditionValue: String
    var conditionFromValue: String

    static func empty() -> TriggerDraft {
        TriggerDraft(
            id: UUID(),
            name: "",
            deviceId: "",
            serviceId: nil,
            characteristicType: "",
            conditionType: .changed,
            conditionValue: "",
            conditionFromValue: ""
        )
    }
}

// MARK: - Condition Draft

struct ConditionDraft: Identifiable {
    let id: UUID
    var deviceId: String
    var serviceId: String?
    var characteristicType: String
    var comparisonType: ComparisonType
    var comparisonValue: String

    static func empty() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            deviceId: "",
            serviceId: nil,
            characteristicType: "",
            comparisonType: .equals,
            comparisonValue: ""
        )
    }
}

// MARK: - Block Draft

struct BlockDraft: Identifiable {
    let id: UUID
    var blockType: BlockDraftType

    static func newControlDevice() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .controlDevice(ControlDeviceDraft()))
    }
    static func newWebhook() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .webhook(WebhookDraft()))
    }
    static func newLog() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .log(LogDraft()))
    }
    static func newDelay() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .delay(DelayDraft()))
    }
    static func newWaitForState() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .waitForState(WaitForStateDraft()))
    }
    static func newConditional() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .conditional(ConditionalDraft()))
    }
    static func newRepeat() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .repeatBlock(RepeatDraft()))
    }
    static func newRepeatWhile() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .repeatWhile(RepeatWhileDraft()))
    }
    static func newGroup() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .group(GroupDraft()))
    }
}

enum BlockDraftType {
    case controlDevice(ControlDeviceDraft)
    case webhook(WebhookDraft)
    case log(LogDraft)
    case delay(DelayDraft)
    case waitForState(WaitForStateDraft)
    case conditional(ConditionalDraft)
    case repeatBlock(RepeatDraft)
    case repeatWhile(RepeatWhileDraft)
    case group(GroupDraft)

    var displayName: String {
        switch self {
        case .controlDevice: return "Control Device"
        case .webhook: return "Webhook"
        case .log: return "Log Message"
        case .delay: return "Delay"
        case .waitForState: return "Wait for State"
        case .conditional: return "If/Else"
        case .repeatBlock: return "Repeat"
        case .repeatWhile: return "Repeat While"
        case .group: return "Group"
        }
    }

    var icon: String {
        switch self {
        case .controlDevice: return "house.fill"
        case .webhook: return "globe"
        case .log: return "text.bubble"
        case .delay: return "clock"
        case .waitForState: return "hourglass"
        case .conditional: return "arrow.triangle.branch"
        case .repeatBlock: return "repeat"
        case .repeatWhile: return "repeat.circle"
        case .group: return "folder"
        }
    }

    var isFlowControl: Bool {
        switch self {
        case .controlDevice, .webhook, .log: return false
        default: return true
        }
    }

    var hasNestedBlocks: Bool {
        switch self {
        case .conditional, .repeatBlock, .repeatWhile, .group: return true
        default: return false
        }
    }
}

// MARK: - Block Type-Specific Drafts

struct ControlDeviceDraft {
    var name: String = ""
    var deviceId: String = ""
    var serviceId: String?
    var characteristicType: String = ""
    var value: String = ""
}

struct WebhookDraft {
    var name: String = ""
    var url: String = ""
    var method: String = "POST"
    var body: String = ""
}

struct LogDraft {
    var name: String = ""
    var message: String = ""
}

struct DelayDraft {
    var name: String = ""
    var seconds: Double = 1.0
}

struct WaitForStateDraft {
    var name: String = ""
    var deviceId: String = ""
    var serviceId: String?
    var characteristicType: String = ""
    var comparisonType: ComparisonType = .equals
    var comparisonValue: String = ""
    var timeoutSeconds: Double = 30.0
}

struct ConditionalDraft {
    var name: String = ""
    var conditionDeviceId: String = ""
    var conditionServiceId: String?
    var conditionCharacteristicType: String = ""
    var comparisonType: ComparisonType = .equals
    var comparisonValue: String = ""
    var thenBlocks: [BlockDraft] = []
    var elseBlocks: [BlockDraft] = []
}

struct RepeatDraft {
    var name: String = ""
    var count: Int = 3
    var delayBetweenSeconds: Double = 0
    var blocks: [BlockDraft] = []
}

struct RepeatWhileDraft {
    var name: String = ""
    var conditionDeviceId: String = ""
    var conditionServiceId: String?
    var conditionCharacteristicType: String = ""
    var comparisonType: ComparisonType = .equals
    var comparisonValue: String = ""
    var maxIterations: Int = 100
    var delayBetweenSeconds: Double = 0
    var blocks: [BlockDraft] = []
}

struct GroupDraft {
    var name: String = ""
    var label: String = ""
    var blocks: [BlockDraft] = []
}

// MARK: - Validation

struct WorkflowValidation {
    let isValid: Bool
    let errors: [String]
}

extension WorkflowDraft {
    func validate() -> WorkflowValidation {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Name is required")
        }
        if triggers.isEmpty {
            errors.append("At least one trigger is required")
        }
        for (i, trigger) in triggers.enumerated() {
            if trigger.deviceId.isEmpty {
                errors.append("Trigger \(i + 1): select a device")
            }
            if trigger.characteristicType.isEmpty {
                errors.append("Trigger \(i + 1): select a characteristic")
            }
        }
        if blocks.isEmpty {
            errors.append("At least one block is required")
        }
        return WorkflowValidation(isValid: errors.isEmpty, errors: errors)
    }
}

// MARK: - Conversion: Workflow → WorkflowDraft

extension WorkflowDraft {
    init(from workflow: Workflow) {
        self.id = workflow.id
        self.name = workflow.name
        self.description = workflow.description ?? ""
        self.isEnabled = workflow.isEnabled
        self.continueOnError = workflow.continueOnError
        self.triggers = workflow.triggers.compactMap { Self.convertTrigger($0) }
        self.conditions = (workflow.conditions ?? []).compactMap { Self.convertCondition($0) }
        self.blocks = workflow.blocks.map { Self.convertBlock($0) }
    }

    private static func convertTrigger(_ trigger: WorkflowTrigger) -> TriggerDraft? {
        switch trigger {
        case .deviceStateChange(let t):
            let (condType, condValue, condFrom) = convertTriggerCondition(t.condition)
            return TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                deviceId: t.deviceId,
                serviceId: t.serviceId,
                characteristicType: t.characteristicType,
                conditionType: condType,
                conditionValue: condValue,
                conditionFromValue: condFrom
            )
        case .compound:
            // Compound triggers not editable in the UI editor
            return nil
        }
    }

    private static func convertTriggerCondition(_ condition: TriggerCondition) -> (TriggerConditionType, String, String) {
        switch condition {
        case .changed:
            return (.changed, "", "")
        case .equals(let v):
            return (.equals, stringFromAny(v.value), "")
        case .notEquals(let v):
            return (.notEquals, stringFromAny(v.value), "")
        case .transitioned(let from, let to):
            return (.transitioned, stringFromAny(to.value), from.map { stringFromAny($0.value) } ?? "")
        case .greaterThan(let v):
            return (.greaterThan, String(v), "")
        case .lessThan(let v):
            return (.lessThan, String(v), "")
        case .greaterThanOrEqual(let v):
            return (.greaterThanOrEqual, String(v), "")
        case .lessThanOrEqual(let v):
            return (.lessThanOrEqual, String(v), "")
        }
    }

    private static func convertCondition(_ condition: WorkflowCondition) -> ConditionDraft? {
        switch condition {
        case .deviceState(let c):
            let (compType, compValue) = convertComparison(c.comparison)
            return ConditionDraft(
                id: UUID(),
                deviceId: c.deviceId,
                serviceId: c.serviceId,
                characteristicType: c.characteristicType,
                comparisonType: compType,
                comparisonValue: compValue
            )
        case .and, .or, .not:
            // Compound conditions not editable in the UI editor
            return nil
        }
    }

    private static func convertComparison(_ comparison: ComparisonOperator) -> (ComparisonType, String) {
        switch comparison {
        case .equals(let v): return (.equals, stringFromAny(v.value))
        case .notEquals(let v): return (.notEquals, stringFromAny(v.value))
        case .greaterThan(let v): return (.greaterThan, String(v))
        case .lessThan(let v): return (.lessThan, String(v))
        case .greaterThanOrEqual(let v): return (.greaterThanOrEqual, String(v))
        case .lessThanOrEqual(let v): return (.lessThanOrEqual, String(v))
        }
    }

    static func convertBlock(_ block: WorkflowBlock) -> BlockDraft {
        switch block {
        case .action(let action):
            return convertAction(action)
        case .flowControl(let fc):
            return convertFlowControl(fc)
        }
    }

    private static func convertAction(_ action: WorkflowAction) -> BlockDraft {
        switch action {
        case .controlDevice(let a):
            return BlockDraft(id: UUID(), blockType: .controlDevice(ControlDeviceDraft(
                name: a.name ?? "",
                deviceId: a.deviceId,
                serviceId: a.serviceId,
                characteristicType: a.characteristicType,
                value: stringFromAny(a.value.value)
            )))
        case .webhook(let a):
            return BlockDraft(id: UUID(), blockType: .webhook(WebhookDraft(
                name: a.name ?? "",
                url: a.url,
                method: a.method,
                body: a.body.map { stringFromAny($0.value) } ?? ""
            )))
        case .log(let a):
            return BlockDraft(id: UUID(), blockType: .log(LogDraft(name: a.name ?? "", message: a.message)))
        }
    }

    private static func convertFlowControl(_ fc: FlowControlBlock) -> BlockDraft {
        switch fc {
        case .delay(let b):
            return BlockDraft(id: UUID(), blockType: .delay(DelayDraft(name: b.name ?? "", seconds: b.seconds)))
        case .waitForState(let b):
            let (compType, compValue) = convertComparison(b.condition)
            return BlockDraft(id: UUID(), blockType: .waitForState(WaitForStateDraft(
                name: b.name ?? "",
                deviceId: b.deviceId,
                serviceId: b.serviceId,
                characteristicType: b.characteristicType,
                comparisonType: compType,
                comparisonValue: compValue,
                timeoutSeconds: b.timeoutSeconds
            )))
        case .conditional(let b):
            let (devId, svcId, charType, compType, compValue) = extractDeviceCondition(b.condition)
            return BlockDraft(id: UUID(), blockType: .conditional(ConditionalDraft(
                name: b.name ?? "",
                conditionDeviceId: devId,
                conditionServiceId: svcId,
                conditionCharacteristicType: charType,
                comparisonType: compType,
                comparisonValue: compValue,
                thenBlocks: b.thenBlocks.map { convertBlock($0) },
                elseBlocks: (b.elseBlocks ?? []).map { convertBlock($0) }
            )))
        case .repeat(let b):
            return BlockDraft(id: UUID(), blockType: .repeatBlock(RepeatDraft(
                name: b.name ?? "",
                count: b.count,
                delayBetweenSeconds: b.delayBetweenSeconds ?? 0,
                blocks: b.blocks.map { convertBlock($0) }
            )))
        case .repeatWhile(let b):
            let (devId, svcId, charType, compType, compValue) = extractDeviceCondition(b.condition)
            return BlockDraft(id: UUID(), blockType: .repeatWhile(RepeatWhileDraft(
                name: b.name ?? "",
                conditionDeviceId: devId,
                conditionServiceId: svcId,
                conditionCharacteristicType: charType,
                comparisonType: compType,
                comparisonValue: compValue,
                maxIterations: b.maxIterations,
                delayBetweenSeconds: b.delayBetweenSeconds ?? 0,
                blocks: b.blocks.map { convertBlock($0) }
            )))
        case .group(let b):
            return BlockDraft(id: UUID(), blockType: .group(GroupDraft(
                name: b.name ?? "",
                label: b.label ?? "",
                blocks: b.blocks.map { convertBlock($0) }
            )))
        }
    }

    private static func extractDeviceCondition(_ condition: WorkflowCondition) -> (String, String?, String, ComparisonType, String) {
        switch condition {
        case .deviceState(let c):
            let (compType, compValue) = convertComparison(c.comparison)
            return (c.deviceId, c.serviceId, c.characteristicType, compType, compValue)
        default:
            return ("", nil, "", .equals, "")
        }
    }
}

// MARK: - Conversion: WorkflowDraft → Workflow

extension WorkflowDraft {
    func toWorkflow(existingMetadata: WorkflowMetadata?, createdAt: Date?) -> Workflow {
        Workflow(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            isEnabled: isEnabled,
            triggers: triggers.map { $0.toTrigger() },
            conditions: conditions.isEmpty ? nil : conditions.map { $0.toCondition() },
            blocks: blocks.map { $0.toBlock() },
            continueOnError: continueOnError,
            metadata: existingMetadata ?? .empty,
            createdAt: createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}

extension TriggerDraft {
    func toTrigger() -> WorkflowTrigger {
        .deviceStateChange(DeviceStateTrigger(
            deviceId: deviceId,
            serviceId: serviceId,
            characteristicType: characteristicType,
            condition: toTriggerCondition(),
            name: name.isEmpty ? nil : name
        ))
    }

    private func toTriggerCondition() -> TriggerCondition {
        switch conditionType {
        case .changed:
            return .changed
        case .equals:
            return .equals(parseValue(conditionValue))
        case .notEquals:
            return .notEquals(parseValue(conditionValue))
        case .transitioned:
            let from = conditionFromValue.isEmpty ? nil : parseValue(conditionFromValue)
            return .transitioned(from: from, to: parseValue(conditionValue))
        case .greaterThan:
            return .greaterThan(Double(conditionValue) ?? 0)
        case .lessThan:
            return .lessThan(Double(conditionValue) ?? 0)
        case .greaterThanOrEqual:
            return .greaterThanOrEqual(Double(conditionValue) ?? 0)
        case .lessThanOrEqual:
            return .lessThanOrEqual(Double(conditionValue) ?? 0)
        }
    }
}

extension ConditionDraft {
    func toCondition() -> WorkflowCondition {
        .deviceState(DeviceStateCondition(
            deviceId: deviceId,
            serviceId: serviceId,
            characteristicType: characteristicType,
            comparison: toComparison()
        ))
    }

    func toComparison() -> ComparisonOperator {
        comparisonType.toOperator(value: comparisonValue)
    }
}

extension ComparisonType {
    func toOperator(value: String) -> ComparisonOperator {
        switch self {
        case .equals: return .equals(parseValue(value))
        case .notEquals: return .notEquals(parseValue(value))
        case .greaterThan: return .greaterThan(Double(value) ?? 0)
        case .lessThan: return .lessThan(Double(value) ?? 0)
        case .greaterThanOrEqual: return .greaterThanOrEqual(Double(value) ?? 0)
        case .lessThanOrEqual: return .lessThanOrEqual(Double(value) ?? 0)
        }
    }
}

extension BlockDraft {
    func toBlock() -> WorkflowBlock {
        switch blockType {
        case .controlDevice(let d):
            return .action(.controlDevice(ControlDeviceAction(
                deviceId: d.deviceId,
                serviceId: d.serviceId,
                characteristicType: d.characteristicType,
                value: parseValue(d.value),
                name: d.name.isEmpty ? nil : d.name
            )))
        case .webhook(let d):
            return .action(.webhook(WebhookActionConfig(
                url: d.url,
                method: d.method,
                headers: nil,
                body: d.body.isEmpty ? nil : AnyCodable(d.body),
                name: d.name.isEmpty ? nil : d.name
            )))
        case .log(let d):
            return .action(.log(LogAction(message: d.message, name: d.name.isEmpty ? nil : d.name)))
        case .delay(let d):
            return .flowControl(.delay(DelayBlock(seconds: d.seconds, name: d.name.isEmpty ? nil : d.name)))
        case .waitForState(let d):
            return .flowControl(.waitForState(WaitForStateBlock(
                deviceId: d.deviceId,
                serviceId: d.serviceId,
                characteristicType: d.characteristicType,
                condition: d.comparisonType.toOperator(value: d.comparisonValue),
                timeoutSeconds: d.timeoutSeconds,
                name: d.name.isEmpty ? nil : d.name
            )))
        case .conditional(let d):
            return .flowControl(.conditional(ConditionalBlock(
                condition: .deviceState(DeviceStateCondition(
                    deviceId: d.conditionDeviceId,
                    serviceId: d.conditionServiceId,
                    characteristicType: d.conditionCharacteristicType,
                    comparison: d.comparisonType.toOperator(value: d.comparisonValue)
                )),
                thenBlocks: d.thenBlocks.map { $0.toBlock() },
                elseBlocks: d.elseBlocks.isEmpty ? nil : d.elseBlocks.map { $0.toBlock() },
                name: d.name.isEmpty ? nil : d.name
            )))
        case .repeatBlock(let d):
            return .flowControl(.repeat(RepeatBlock(
                count: d.count,
                blocks: d.blocks.map { $0.toBlock() },
                delayBetweenSeconds: d.delayBetweenSeconds > 0 ? d.delayBetweenSeconds : nil,
                name: d.name.isEmpty ? nil : d.name
            )))
        case .repeatWhile(let d):
            return .flowControl(.repeatWhile(RepeatWhileBlock(
                condition: .deviceState(DeviceStateCondition(
                    deviceId: d.conditionDeviceId,
                    serviceId: d.conditionServiceId,
                    characteristicType: d.conditionCharacteristicType,
                    comparison: d.comparisonType.toOperator(value: d.comparisonValue)
                )),
                blocks: d.blocks.map { $0.toBlock() },
                maxIterations: d.maxIterations,
                delayBetweenSeconds: d.delayBetweenSeconds > 0 ? d.delayBetweenSeconds : nil,
                name: d.name.isEmpty ? nil : d.name
            )))
        case .group(let d):
            return .flowControl(.group(GroupBlock(
                label: d.label.isEmpty ? nil : d.label,
                blocks: d.blocks.map { $0.toBlock() },
                name: d.name.isEmpty ? nil : d.name
            )))
        }
    }
}

// MARK: - Value Parsing Helpers

/// Parse a string value to the most appropriate AnyCodable type.
/// Tries Bool → Int → Double → String.
func parseValue(_ string: String) -> AnyCodable {
    let trimmed = string.trimmingCharacters(in: .whitespaces)

    // Boolean
    if trimmed.lowercased() == "true" { return AnyCodable(true) }
    if trimmed.lowercased() == "false" { return AnyCodable(false) }

    // Integer
    if let intVal = Int(trimmed) { return AnyCodable(intVal) }

    // Double
    if let doubleVal = Double(trimmed) { return AnyCodable(doubleVal) }

    // String fallback
    return AnyCodable(trimmed)
}

/// Convert Any value to a display String.
func stringFromAny(_ value: Any) -> String {
    if let bool = value as? Bool { return bool ? "true" : "false" }
    if let int = value as? Int { return String(int) }
    if let double = value as? Double { return String(double) }
    return "\(value)"
}
