import Foundation

// MARK: - Workflow (Top-Level)

struct Workflow: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String?
    var isEnabled: Bool
    var triggers: [WorkflowTrigger]
    var conditions: [WorkflowCondition]?
    var blocks: [WorkflowBlock]
    var continueOnError: Bool
    var metadata: WorkflowMetadata
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        isEnabled: Bool = true,
        triggers: [WorkflowTrigger],
        conditions: [WorkflowCondition]? = nil,
        blocks: [WorkflowBlock],
        continueOnError: Bool = false,
        metadata: WorkflowMetadata = .empty,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
        self.triggers = triggers
        self.conditions = conditions
        self.blocks = blocks
        self.continueOnError = continueOnError
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkflowMetadata: Codable {
    var createdBy: String?
    var tags: [String]?
    var lastTriggeredAt: Date?
    var totalExecutions: Int
    var consecutiveFailures: Int

    static let empty = WorkflowMetadata(
        createdBy: nil,
        tags: nil,
        lastTriggeredAt: nil,
        totalExecutions: 0,
        consecutiveFailures: 0
    )
}

// MARK: - WorkflowBlock (Action vs. Flow Control)

indirect enum WorkflowBlock: Codable {
    case action(WorkflowAction)
    case flowControl(FlowControlBlock)

    private enum BlockKind: String, Codable {
        case action
        case flowControl
    }

    private enum CodingKeys: String, CodingKey {
        case block
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(BlockKind.self, forKey: .block)
        switch kind {
        case .action:
            self = .action(try WorkflowAction(from: decoder))
        case .flowControl:
            self = .flowControl(try FlowControlBlock(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let action):
            try container.encode(BlockKind.action, forKey: .block)
            try action.encode(to: encoder)
        case .flowControl(let flowControl):
            try container.encode(BlockKind.flowControl, forKey: .block)
            try flowControl.encode(to: encoder)
        }
    }
}

// MARK: - Actions (Atomic Leaf Nodes)

enum WorkflowAction: Codable {
    case controlDevice(ControlDeviceAction)
    case webhook(WebhookActionConfig)
    case log(LogAction)

    private enum ActionType: String, Codable {
        case controlDevice
        case webhook
        case log
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case deviceId, serviceId, characteristicType, value
        case url, method, headers, body
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .controlDevice:
            self = .controlDevice(ControlDeviceAction(
                deviceId: try container.decode(String.self, forKey: .deviceId),
                serviceId: try container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: try container.decode(String.self, forKey: .characteristicType),
                value: try container.decode(AnyCodable.self, forKey: .value)
            ))
        case .webhook:
            self = .webhook(WebhookActionConfig(
                url: try container.decode(String.self, forKey: .url),
                method: try container.decode(String.self, forKey: .method),
                headers: try container.decodeIfPresent([String: String].self, forKey: .headers),
                body: try container.decodeIfPresent(AnyCodable.self, forKey: .body)
            ))
        case .log:
            self = .log(LogAction(
                message: try container.decode(String.self, forKey: .message)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .controlDevice(let action):
            try container.encode(ActionType.controlDevice, forKey: .type)
            try container.encode(action.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(action.serviceId, forKey: .serviceId)
            try container.encode(action.characteristicType, forKey: .characteristicType)
            try container.encode(action.value, forKey: .value)
        case .webhook(let action):
            try container.encode(ActionType.webhook, forKey: .type)
            try container.encode(action.url, forKey: .url)
            try container.encode(action.method, forKey: .method)
            try container.encodeIfPresent(action.headers, forKey: .headers)
            try container.encodeIfPresent(action.body, forKey: .body)
        case .log(let action):
            try container.encode(ActionType.log, forKey: .type)
            try container.encode(action.message, forKey: .message)
        }
    }

    var displayType: String {
        switch self {
        case .controlDevice: return "controlDevice"
        case .webhook: return "webhook"
        case .log: return "log"
        }
    }
}

struct ControlDeviceAction {
    let deviceId: String
    let serviceId: String?
    let characteristicType: String
    let value: AnyCodable
}

struct WebhookActionConfig {
    let url: String
    let method: String
    let headers: [String: String]?
    let body: AnyCodable?
}

struct LogAction {
    let message: String
}

// MARK: - Flow Control Blocks (Structural Nodes)

enum FlowControlBlock: Codable {
    case delay(DelayBlock)
    case waitForState(WaitForStateBlock)
    case conditional(ConditionalBlock)
    case `repeat`(RepeatBlock)
    case repeatWhile(RepeatWhileBlock)
    case group(GroupBlock)

    private enum FlowControlType: String, Codable {
        case delay
        case waitForState
        case conditional
        case `repeat`
        case repeatWhile
        case group
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case seconds
        case deviceId, serviceId, characteristicType, condition, timeoutSeconds
        case thenBlocks, elseBlocks
        case count, blocks, delayBetweenSeconds
        case maxIterations
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(FlowControlType.self, forKey: .type)
        switch type {
        case .delay:
            self = .delay(DelayBlock(
                seconds: try container.decode(Double.self, forKey: .seconds)
            ))
        case .waitForState:
            self = .waitForState(WaitForStateBlock(
                deviceId: try container.decode(String.self, forKey: .deviceId),
                serviceId: try container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: try container.decode(String.self, forKey: .characteristicType),
                condition: try container.decode(ComparisonOperator.self, forKey: .condition),
                timeoutSeconds: try container.decode(Double.self, forKey: .timeoutSeconds)
            ))
        case .conditional:
            self = .conditional(ConditionalBlock(
                condition: try container.decode(WorkflowCondition.self, forKey: .condition),
                thenBlocks: try container.decode([WorkflowBlock].self, forKey: .thenBlocks),
                elseBlocks: try container.decodeIfPresent([WorkflowBlock].self, forKey: .elseBlocks)
            ))
        case .repeat:
            self = .repeat(RepeatBlock(
                count: try container.decode(Int.self, forKey: .count),
                blocks: try container.decode([WorkflowBlock].self, forKey: .blocks),
                delayBetweenSeconds: try container.decodeIfPresent(Double.self, forKey: .delayBetweenSeconds)
            ))
        case .repeatWhile:
            self = .repeatWhile(RepeatWhileBlock(
                condition: try container.decode(WorkflowCondition.self, forKey: .condition),
                blocks: try container.decode([WorkflowBlock].self, forKey: .blocks),
                maxIterations: try container.decodeIfPresent(Int.self, forKey: .maxIterations) ?? 100,
                delayBetweenSeconds: try container.decodeIfPresent(Double.self, forKey: .delayBetweenSeconds)
            ))
        case .group:
            self = .group(GroupBlock(
                label: try container.decodeIfPresent(String.self, forKey: .label),
                blocks: try container.decode([WorkflowBlock].self, forKey: .blocks)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .delay(let block):
            try container.encode(FlowControlType.delay, forKey: .type)
            try container.encode(block.seconds, forKey: .seconds)
        case .waitForState(let block):
            try container.encode(FlowControlType.waitForState, forKey: .type)
            try container.encode(block.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(block.serviceId, forKey: .serviceId)
            try container.encode(block.characteristicType, forKey: .characteristicType)
            try container.encode(block.condition, forKey: .condition)
            try container.encode(block.timeoutSeconds, forKey: .timeoutSeconds)
        case .conditional(let block):
            try container.encode(FlowControlType.conditional, forKey: .type)
            try container.encode(block.condition, forKey: .condition)
            try container.encode(block.thenBlocks, forKey: .thenBlocks)
            try container.encodeIfPresent(block.elseBlocks, forKey: .elseBlocks)
        case .repeat(let block):
            try container.encode(FlowControlType.repeat, forKey: .type)
            try container.encode(block.count, forKey: .count)
            try container.encode(block.blocks, forKey: .blocks)
            try container.encodeIfPresent(block.delayBetweenSeconds, forKey: .delayBetweenSeconds)
        case .repeatWhile(let block):
            try container.encode(FlowControlType.repeatWhile, forKey: .type)
            try container.encode(block.condition, forKey: .condition)
            try container.encode(block.blocks, forKey: .blocks)
            try container.encode(block.maxIterations, forKey: .maxIterations)
            try container.encodeIfPresent(block.delayBetweenSeconds, forKey: .delayBetweenSeconds)
        case .group(let block):
            try container.encode(FlowControlType.group, forKey: .type)
            try container.encodeIfPresent(block.label, forKey: .label)
            try container.encode(block.blocks, forKey: .blocks)
        }
    }

    var displayType: String {
        switch self {
        case .delay: return "delay"
        case .waitForState: return "waitForState"
        case .conditional: return "conditional"
        case .repeat: return "repeat"
        case .repeatWhile: return "repeatWhile"
        case .group: return "group"
        }
    }
}

struct DelayBlock {
    let seconds: Double
}

struct WaitForStateBlock {
    let deviceId: String
    let serviceId: String?
    let characteristicType: String
    let condition: ComparisonOperator
    let timeoutSeconds: Double
}

struct ConditionalBlock {
    let condition: WorkflowCondition
    let thenBlocks: [WorkflowBlock]
    let elseBlocks: [WorkflowBlock]?
}

struct RepeatBlock {
    let count: Int
    let blocks: [WorkflowBlock]
    let delayBetweenSeconds: Double?
}

struct RepeatWhileBlock {
    let condition: WorkflowCondition
    let blocks: [WorkflowBlock]
    let maxIterations: Int
    let delayBetweenSeconds: Double?

    init(condition: WorkflowCondition, blocks: [WorkflowBlock], maxIterations: Int = 100, delayBetweenSeconds: Double? = nil) {
        self.condition = condition
        self.blocks = blocks
        self.maxIterations = maxIterations
        self.delayBetweenSeconds = delayBetweenSeconds
    }
}

struct GroupBlock {
    let label: String?
    let blocks: [WorkflowBlock]
}

// MARK: - Trigger System

indirect enum WorkflowTrigger: Codable {
    case deviceStateChange(DeviceStateTrigger)
    case compound(CompoundTrigger)

    private enum TriggerType: String, Codable {
        case deviceStateChange
        case compound
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case deviceId, serviceId, characteristicType, condition
        case logicOperator = "operator"
        case triggers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TriggerType.self, forKey: .type)
        switch type {
        case .deviceStateChange:
            self = .deviceStateChange(DeviceStateTrigger(
                deviceId: try container.decode(String.self, forKey: .deviceId),
                serviceId: try container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: try container.decode(String.self, forKey: .characteristicType),
                condition: try container.decode(TriggerCondition.self, forKey: .condition)
            ))
        case .compound:
            self = .compound(CompoundTrigger(
                logicOperator: try container.decode(LogicOperator.self, forKey: .logicOperator),
                triggers: try container.decode([WorkflowTrigger].self, forKey: .triggers)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .deviceStateChange(let trigger):
            try container.encode(TriggerType.deviceStateChange, forKey: .type)
            try container.encode(trigger.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(trigger.serviceId, forKey: .serviceId)
            try container.encode(trigger.characteristicType, forKey: .characteristicType)
            try container.encode(trigger.condition, forKey: .condition)
        case .compound(let trigger):
            try container.encode(TriggerType.compound, forKey: .type)
            try container.encode(trigger.logicOperator, forKey: .logicOperator)
            try container.encode(trigger.triggers, forKey: .triggers)
        }
    }
}

struct DeviceStateTrigger {
    let deviceId: String
    let serviceId: String?
    let characteristicType: String
    let condition: TriggerCondition
}

struct CompoundTrigger {
    let logicOperator: LogicOperator
    let triggers: [WorkflowTrigger]
}

enum LogicOperator: String, Codable {
    case and
    case or
}

// MARK: - Trigger Condition

enum TriggerCondition: Codable {
    case changed
    case equals(AnyCodable)
    case notEquals(AnyCodable)
    case transitioned(from: AnyCodable?, to: AnyCodable)
    case greaterThan(Double)
    case lessThan(Double)
    case greaterThanOrEqual(Double)
    case lessThanOrEqual(Double)

    private enum ConditionType: String, Codable {
        case changed
        case equals
        case notEquals
        case transitioned
        case greaterThan
        case lessThan
        case greaterThanOrEqual
        case lessThanOrEqual
    }

    private enum CodingKeys: String, CodingKey {
        case type, value, from, to
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ConditionType.self, forKey: .type)
        switch type {
        case .changed:
            self = .changed
        case .equals:
            self = .equals(try container.decode(AnyCodable.self, forKey: .value))
        case .notEquals:
            self = .notEquals(try container.decode(AnyCodable.self, forKey: .value))
        case .transitioned:
            self = .transitioned(
                from: try container.decodeIfPresent(AnyCodable.self, forKey: .from),
                to: try container.decode(AnyCodable.self, forKey: .to)
            )
        case .greaterThan:
            self = .greaterThan(try container.decode(Double.self, forKey: .value))
        case .lessThan:
            self = .lessThan(try container.decode(Double.self, forKey: .value))
        case .greaterThanOrEqual:
            self = .greaterThanOrEqual(try container.decode(Double.self, forKey: .value))
        case .lessThanOrEqual:
            self = .lessThanOrEqual(try container.decode(Double.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .changed:
            try container.encode(ConditionType.changed, forKey: .type)
        case .equals(let value):
            try container.encode(ConditionType.equals, forKey: .type)
            try container.encode(value, forKey: .value)
        case .notEquals(let value):
            try container.encode(ConditionType.notEquals, forKey: .type)
            try container.encode(value, forKey: .value)
        case .transitioned(let from, let to):
            try container.encode(ConditionType.transitioned, forKey: .type)
            try container.encodeIfPresent(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .greaterThan(let value):
            try container.encode(ConditionType.greaterThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case .lessThan(let value):
            try container.encode(ConditionType.lessThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case .greaterThanOrEqual(let value):
            try container.encode(ConditionType.greaterThanOrEqual, forKey: .type)
            try container.encode(value, forKey: .value)
        case .lessThanOrEqual(let value):
            try container.encode(ConditionType.lessThanOrEqual, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

// MARK: - Workflow Conditions (Guard Expressions)

indirect enum WorkflowCondition: Codable {
    case deviceState(DeviceStateCondition)
    case and([WorkflowCondition])
    case or([WorkflowCondition])
    case not(WorkflowCondition)

    private enum ConditionType: String, Codable {
        case deviceState
        case and
        case or
        case not
    }

    private enum CodingKeys: String, CodingKey {
        case type, conditions, condition
        case deviceId, serviceId, characteristicType, comparison
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ConditionType.self, forKey: .type)
        switch type {
        case .deviceState:
            self = .deviceState(DeviceStateCondition(
                deviceId: try container.decode(String.self, forKey: .deviceId),
                serviceId: try container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: try container.decode(String.self, forKey: .characteristicType),
                comparison: try container.decode(ComparisonOperator.self, forKey: .comparison)
            ))
        case .and:
            self = .and(try container.decode([WorkflowCondition].self, forKey: .conditions))
        case .or:
            self = .or(try container.decode([WorkflowCondition].self, forKey: .conditions))
        case .not:
            self = .not(try container.decode(WorkflowCondition.self, forKey: .condition))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .deviceState(let cond):
            try container.encode(ConditionType.deviceState, forKey: .type)
            try container.encode(cond.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(cond.serviceId, forKey: .serviceId)
            try container.encode(cond.characteristicType, forKey: .characteristicType)
            try container.encode(cond.comparison, forKey: .comparison)
        case .and(let conditions):
            try container.encode(ConditionType.and, forKey: .type)
            try container.encode(conditions, forKey: .conditions)
        case .or(let conditions):
            try container.encode(ConditionType.or, forKey: .type)
            try container.encode(conditions, forKey: .conditions)
        case .not(let condition):
            try container.encode(ConditionType.not, forKey: .type)
            try container.encode(condition, forKey: .condition)
        }
    }
}

struct DeviceStateCondition {
    let deviceId: String
    let serviceId: String?
    let characteristicType: String
    let comparison: ComparisonOperator
}

// MARK: - Shared: ComparisonOperator

enum ComparisonOperator: Codable {
    case equals(AnyCodable)
    case notEquals(AnyCodable)
    case greaterThan(Double)
    case lessThan(Double)
    case greaterThanOrEqual(Double)
    case lessThanOrEqual(Double)

    private enum OperatorType: String, Codable {
        case equals
        case notEquals
        case greaterThan
        case lessThan
        case greaterThanOrEqual
        case lessThanOrEqual
    }

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(OperatorType.self, forKey: .type)
        switch type {
        case .equals:
            self = .equals(try container.decode(AnyCodable.self, forKey: .value))
        case .notEquals:
            self = .notEquals(try container.decode(AnyCodable.self, forKey: .value))
        case .greaterThan:
            self = .greaterThan(try container.decode(Double.self, forKey: .value))
        case .lessThan:
            self = .lessThan(try container.decode(Double.self, forKey: .value))
        case .greaterThanOrEqual:
            self = .greaterThanOrEqual(try container.decode(Double.self, forKey: .value))
        case .lessThanOrEqual:
            self = .lessThanOrEqual(try container.decode(Double.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .equals(let value):
            try container.encode(OperatorType.equals, forKey: .type)
            try container.encode(value, forKey: .value)
        case .notEquals(let value):
            try container.encode(OperatorType.notEquals, forKey: .type)
            try container.encode(value, forKey: .value)
        case .greaterThan(let value):
            try container.encode(OperatorType.greaterThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case .lessThan(let value):
            try container.encode(OperatorType.lessThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case .greaterThanOrEqual(let value):
            try container.encode(OperatorType.greaterThanOrEqual, forKey: .type)
            try container.encode(value, forKey: .value)
        case .lessThanOrEqual(let value):
            try container.encode(OperatorType.lessThanOrEqual, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

// MARK: - Trigger Evaluator Protocol

protocol TriggerEvaluator {
    func canEvaluate(_ trigger: WorkflowTrigger) -> Bool
    func evaluate(_ trigger: WorkflowTrigger, context: TriggerContext) async -> Bool
}

enum TriggerContext {
    case stateChange(StateChange)
}

// MARK: - Execution Log Models

struct WorkflowExecutionLog: Identifiable, Codable {
    let id: UUID
    let workflowId: UUID
    let workflowName: String
    let triggeredAt: Date
    var completedAt: Date?
    let triggerEvent: TriggerEvent?
    var conditionResults: [ConditionResult]?
    var blockResults: [BlockResult]
    var status: ExecutionStatus
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        workflowId: UUID,
        workflowName: String,
        triggeredAt: Date = Date(),
        completedAt: Date? = nil,
        triggerEvent: TriggerEvent? = nil,
        conditionResults: [ConditionResult]? = nil,
        blockResults: [BlockResult] = [],
        status: ExecutionStatus = .running,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.triggeredAt = triggeredAt
        self.completedAt = completedAt
        self.triggerEvent = triggerEvent
        self.conditionResults = conditionResults
        self.blockResults = blockResults
        self.status = status
        self.errorMessage = errorMessage
    }
}

struct TriggerEvent: Codable {
    let deviceId: String
    let deviceName: String
    let serviceId: String?
    let characteristicType: String
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
}

struct ConditionResult: Codable {
    let conditionDescription: String
    let passed: Bool
}

struct BlockResult: Codable {
    let blockIndex: Int
    let blockKind: String
    let blockType: String
    var status: ExecutionStatus
    let startedAt: Date
    var completedAt: Date?
    var detail: String?
    var errorMessage: String?
    var nestedResults: [BlockResult]?

    init(
        blockIndex: Int,
        blockKind: String,
        blockType: String,
        status: ExecutionStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        detail: String? = nil,
        errorMessage: String? = nil,
        nestedResults: [BlockResult]? = nil
    ) {
        self.blockIndex = blockIndex
        self.blockKind = blockKind
        self.blockType = blockType
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.detail = detail
        self.errorMessage = errorMessage
        self.nestedResults = nestedResults
    }
}

enum ExecutionStatus: String, Codable {
    case running
    case success
    case failure
    case skipped
    case conditionNotMet
}
