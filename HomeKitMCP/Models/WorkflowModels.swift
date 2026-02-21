import Foundation

// MARK: - Concurrent Execution Policy

enum ConcurrentExecutionPolicy: String, Codable, CaseIterable, Identifiable {
    /// Ignore the new trigger while the workflow is already running.
    case ignoreNew
    /// Cancel the running execution and start fresh from the new trigger.
    case cancelAndRestart
    /// Queue the new trigger; it will execute after the current run finishes.
    case queueAndExecute

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .ignoreNew: return "Ignore New Trigger"
        case .cancelAndRestart: return "Cancel & Restart"
        case .queueAndExecute: return "Queue & Execute"
        }
    }

    var description: String {
        switch self {
        case .ignoreNew: return "New triggers are ignored while the workflow is running."
        case .cancelAndRestart: return "The running execution is cancelled and restarted with the new trigger."
        case .queueAndExecute: return "New triggers are queued and executed once the current run completes."
        }
    }
}

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
    var retriggerPolicy: ConcurrentExecutionPolicy
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
        retriggerPolicy: ConcurrentExecutionPolicy = .ignoreNew,
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
        self.retriggerPolicy = retriggerPolicy
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Custom Codable to handle backward compatibility (missing retriggerPolicy defaults to .ignoreNew)
    private enum CodingKeys: String, CodingKey {
        case id, name, description, isEnabled, triggers, conditions, blocks
        case continueOnError, retriggerPolicy, metadata, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        triggers = try container.decode([WorkflowTrigger].self, forKey: .triggers)
        conditions = try container.decodeIfPresent([WorkflowCondition].self, forKey: .conditions)
        blocks = try container.decode([WorkflowBlock].self, forKey: .blocks)
        continueOnError = try container.decode(Bool.self, forKey: .continueOnError)
        retriggerPolicy = try container.decodeIfPresent(ConcurrentExecutionPolicy.self, forKey: .retriggerPolicy) ?? .ignoreNew
        metadata = try container.decode(WorkflowMetadata.self, forKey: .metadata)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
            self = try .action(WorkflowAction(from: decoder))
        case .flowControl:
            self = try .flowControl(FlowControlBlock(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .action(action):
            try container.encode(BlockKind.action, forKey: .block)
            try action.encode(to: encoder)
        case let .flowControl(flowControl):
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
        case type, name
        case deviceId, serviceId, characteristicType, value
        case url, method, headers, body
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        switch type {
        case .controlDevice:
            self = try .controlDevice(ControlDeviceAction(
                deviceId: container.decode(String.self, forKey: .deviceId),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: container.decode(String.self, forKey: .characteristicType),
                value: container.decode(AnyCodable.self, forKey: .value),
                name: name
            ))
        case .webhook:
            self = try .webhook(WebhookActionConfig(
                url: container.decode(String.self, forKey: .url),
                method: container.decode(String.self, forKey: .method),
                headers: container.decodeIfPresent([String: String].self, forKey: .headers),
                body: container.decodeIfPresent(AnyCodable.self, forKey: .body),
                name: name
            ))
        case .log:
            self = try .log(LogAction(
                message: container.decode(String.self, forKey: .message),
                name: name
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .controlDevice(action):
            try container.encode(ActionType.controlDevice, forKey: .type)
            try container.encodeIfPresent(action.name, forKey: .name)
            try container.encode(action.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(action.serviceId, forKey: .serviceId)
            try container.encode(action.characteristicType, forKey: .characteristicType)
            try container.encode(action.value, forKey: .value)
        case let .webhook(action):
            try container.encode(ActionType.webhook, forKey: .type)
            try container.encodeIfPresent(action.name, forKey: .name)
            try container.encode(action.url, forKey: .url)
            try container.encode(action.method, forKey: .method)
            try container.encodeIfPresent(action.headers, forKey: .headers)
            try container.encodeIfPresent(action.body, forKey: .body)
        case let .log(action):
            try container.encode(ActionType.log, forKey: .type)
            try container.encodeIfPresent(action.name, forKey: .name)
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
    let name: String?

    init(deviceId: String, serviceId: String? = nil, characteristicType: String, value: AnyCodable, name: String? = nil) {
        self.deviceId = deviceId
        self.serviceId = serviceId
        self.characteristicType = characteristicType
        self.value = value
        self.name = name
    }
}

struct WebhookActionConfig {
    let url: String
    let method: String
    let headers: [String: String]?
    let body: AnyCodable?
    let name: String?

    init(url: String, method: String, headers: [String: String]? = nil, body: AnyCodable? = nil, name: String? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.name = name
    }
}

struct LogAction {
    let message: String
    let name: String?

    init(message: String, name: String? = nil) {
        self.message = message
        self.name = name
    }
}

// MARK: - Flow Control Blocks (Structural Nodes)

enum FlowControlBlock: Codable {
    case delay(DelayBlock)
    case waitForState(WaitForStateBlock)
    case conditional(ConditionalBlock)
    case `repeat`(RepeatBlock)
    case repeatWhile(RepeatWhileBlock)
    case group(GroupBlock)
    case stop(StopBlock)
    case executeWorkflow(ExecuteWorkflowBlock)

    private enum FlowControlType: String, Codable {
        case delay
        case waitForState
        case conditional
        case `repeat`
        case repeatWhile
        case group
        case stop
        case executeWorkflow
    }

    private enum CodingKeys: String, CodingKey {
        case type, name
        case seconds
        case deviceId, serviceId, characteristicType, condition, timeoutSeconds
        case thenBlocks, elseBlocks
        case count, blocks, delayBetweenSeconds
        case maxIterations
        case label
        case outcome, message
        case targetWorkflowId, executionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(FlowControlType.self, forKey: .type)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        switch type {
        case .delay:
            self = try .delay(DelayBlock(
                seconds: container.decode(Double.self, forKey: .seconds),
                name: name
            ))
        case .waitForState:
            self = try .waitForState(WaitForStateBlock(
                deviceId: container.decode(String.self, forKey: .deviceId),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: container.decode(String.self, forKey: .characteristicType),
                condition: container.decode(ComparisonOperator.self, forKey: .condition),
                timeoutSeconds: container.decode(Double.self, forKey: .timeoutSeconds),
                name: name
            ))
        case .conditional:
            self = try .conditional(ConditionalBlock(
                condition: container.decode(WorkflowCondition.self, forKey: .condition),
                thenBlocks: container.decode([WorkflowBlock].self, forKey: .thenBlocks),
                elseBlocks: container.decodeIfPresent([WorkflowBlock].self, forKey: .elseBlocks),
                name: name
            ))
        case .repeat:
            self = try .repeat(RepeatBlock(
                count: container.decode(Int.self, forKey: .count),
                blocks: container.decode([WorkflowBlock].self, forKey: .blocks),
                delayBetweenSeconds: container.decodeIfPresent(Double.self, forKey: .delayBetweenSeconds),
                name: name
            ))
        case .repeatWhile:
            self = try .repeatWhile(RepeatWhileBlock(
                condition: container.decode(WorkflowCondition.self, forKey: .condition),
                blocks: container.decode([WorkflowBlock].self, forKey: .blocks),
                maxIterations: container.decodeIfPresent(Int.self, forKey: .maxIterations) ?? 100,
                delayBetweenSeconds: container.decodeIfPresent(Double.self, forKey: .delayBetweenSeconds),
                name: name
            ))
        case .group:
            self = try .group(GroupBlock(
                label: container.decodeIfPresent(String.self, forKey: .label),
                blocks: container.decode([WorkflowBlock].self, forKey: .blocks),
                name: name
            ))
        case .stop:
            self = try .stop(StopBlock(
                outcome: container.decode(StopOutcome.self, forKey: .outcome),
                message: container.decodeIfPresent(String.self, forKey: .message),
                name: name
            ))
        case .executeWorkflow:
            self = try .executeWorkflow(ExecuteWorkflowBlock(
                targetWorkflowId: container.decode(UUID.self, forKey: .targetWorkflowId),
                executionMode: container.decode(ExecutionMode.self, forKey: .executionMode),
                name: name
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .delay(block):
            try container.encode(FlowControlType.delay, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.seconds, forKey: .seconds)
        case let .waitForState(block):
            try container.encode(FlowControlType.waitForState, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(block.serviceId, forKey: .serviceId)
            try container.encode(block.characteristicType, forKey: .characteristicType)
            try container.encode(block.condition, forKey: .condition)
            try container.encode(block.timeoutSeconds, forKey: .timeoutSeconds)
        case let .conditional(block):
            try container.encode(FlowControlType.conditional, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.condition, forKey: .condition)
            try container.encode(block.thenBlocks, forKey: .thenBlocks)
            try container.encodeIfPresent(block.elseBlocks, forKey: .elseBlocks)
        case let .repeat(block):
            try container.encode(FlowControlType.repeat, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.count, forKey: .count)
            try container.encode(block.blocks, forKey: .blocks)
            try container.encodeIfPresent(block.delayBetweenSeconds, forKey: .delayBetweenSeconds)
        case let .repeatWhile(block):
            try container.encode(FlowControlType.repeatWhile, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.condition, forKey: .condition)
            try container.encode(block.blocks, forKey: .blocks)
            try container.encode(block.maxIterations, forKey: .maxIterations)
            try container.encodeIfPresent(block.delayBetweenSeconds, forKey: .delayBetweenSeconds)
        case let .group(block):
            try container.encode(FlowControlType.group, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encodeIfPresent(block.label, forKey: .label)
            try container.encode(block.blocks, forKey: .blocks)
        case let .stop(block):
            try container.encode(FlowControlType.stop, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.outcome, forKey: .outcome)
            try container.encodeIfPresent(block.message, forKey: .message)
        case let .executeWorkflow(block):
            try container.encode(FlowControlType.executeWorkflow, forKey: .type)
            try container.encodeIfPresent(block.name, forKey: .name)
            try container.encode(block.targetWorkflowId, forKey: .targetWorkflowId)
            try container.encode(block.executionMode, forKey: .executionMode)
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
        case .stop: return "stop"
        case .executeWorkflow: return "executeWorkflow"
        }
    }
}

struct DelayBlock {
    let seconds: Double
    let name: String?

    init(seconds: Double, name: String? = nil) {
        self.seconds = seconds
        self.name = name
    }
}

struct WaitForStateBlock {
    let deviceId: String
    let serviceId: String?
    let characteristicType: String
    let condition: ComparisonOperator
    let timeoutSeconds: Double
    let name: String?

    init(deviceId: String, serviceId: String? = nil, characteristicType: String, condition: ComparisonOperator, timeoutSeconds: Double, name: String? = nil) {
        self.deviceId = deviceId
        self.serviceId = serviceId
        self.characteristicType = characteristicType
        self.condition = condition
        self.timeoutSeconds = timeoutSeconds
        self.name = name
    }
}

struct ConditionalBlock {
    let condition: WorkflowCondition
    let thenBlocks: [WorkflowBlock]
    let elseBlocks: [WorkflowBlock]?
    let name: String?

    init(condition: WorkflowCondition, thenBlocks: [WorkflowBlock], elseBlocks: [WorkflowBlock]? = nil, name: String? = nil) {
        self.condition = condition
        self.thenBlocks = thenBlocks
        self.elseBlocks = elseBlocks
        self.name = name
    }
}

struct RepeatBlock {
    let count: Int
    let blocks: [WorkflowBlock]
    let delayBetweenSeconds: Double?
    let name: String?

    init(count: Int, blocks: [WorkflowBlock], delayBetweenSeconds: Double? = nil, name: String? = nil) {
        self.count = count
        self.blocks = blocks
        self.delayBetweenSeconds = delayBetweenSeconds
        self.name = name
    }
}

struct RepeatWhileBlock {
    let condition: WorkflowCondition
    let blocks: [WorkflowBlock]
    let maxIterations: Int
    let delayBetweenSeconds: Double?
    let name: String?

    init(condition: WorkflowCondition, blocks: [WorkflowBlock], maxIterations: Int = 100, delayBetweenSeconds: Double? = nil, name: String? = nil) {
        self.condition = condition
        self.blocks = blocks
        self.maxIterations = maxIterations
        self.delayBetweenSeconds = delayBetweenSeconds
        self.name = name
    }
}

struct GroupBlock {
    let label: String?
    let blocks: [WorkflowBlock]
    let name: String?

    init(label: String? = nil, blocks: [WorkflowBlock], name: String? = nil) {
        self.label = label
        self.blocks = blocks
        self.name = name
    }
}

struct StopBlock: Codable {
    let outcome: StopOutcome
    let message: String?
    let name: String?

    init(outcome: StopOutcome = .success, message: String? = nil, name: String? = nil) {
        self.outcome = outcome
        self.message = message
        self.name = name
    }
}

enum StopOutcome: String, Codable, CaseIterable, Identifiable {
    case success
    case error
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .success: return "Success"
        case .error: return "Error"
        case .cancelled: return "Cancelled"
        }
    }
}

enum ExecutionMode: String, Codable, CaseIterable, Identifiable {
    case inline
    case parallel
    case delegate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inline: return "Inline (Wait)"
        case .parallel: return "Parallel"
        case .delegate: return "Delegate"
        }
    }

    var description: String {
        switch self {
        case .inline: return "Wait for the target workflow to finish before continuing"
        case .parallel: return "Launch the target workflow and continue immediately"
        case .delegate: return "Launch the target workflow and stop this one"
        }
    }
}

struct ExecuteWorkflowBlock: Codable {
    let targetWorkflowId: UUID
    let executionMode: ExecutionMode
    let name: String?

    init(targetWorkflowId: UUID, executionMode: ExecutionMode = .inline, name: String? = nil) {
        self.targetWorkflowId = targetWorkflowId
        self.executionMode = executionMode
        self.name = name
    }
}

// MARK: - Trigger System

indirect enum WorkflowTrigger: Codable {
    case deviceStateChange(DeviceStateTrigger)
    case compound(CompoundTrigger)
    case schedule(ScheduleTrigger)
    case webhook(WebhookTrigger)
    case workflow(WorkflowCallTrigger)

    private enum TriggerType: String, Codable {
        case deviceStateChange
        case compound
        case schedule
        case webhook
        case workflow
    }

    private enum CodingKeys: String, CodingKey {
        case type, name
        case deviceId, serviceId, characteristicType, condition
        case logicOperator = "operator"
        case triggers
        case scheduleType, token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TriggerType.self, forKey: .type)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        switch type {
        case .deviceStateChange:
            self = try .deviceStateChange(DeviceStateTrigger(
                deviceId: container.decode(String.self, forKey: .deviceId),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: container.decode(String.self, forKey: .characteristicType),
                condition: container.decode(TriggerCondition.self, forKey: .condition),
                name: name
            ))
        case .compound:
            self = try .compound(CompoundTrigger(
                logicOperator: container.decode(LogicOperator.self, forKey: .logicOperator),
                triggers: container.decode([WorkflowTrigger].self, forKey: .triggers),
                name: name
            ))
        case .schedule:
            self = try .schedule(ScheduleTrigger(
                scheduleType: container.decode(ScheduleType.self, forKey: .scheduleType),
                name: name
            ))
        case .webhook:
            self = try .webhook(WebhookTrigger(
                token: container.decode(String.self, forKey: .token),
                name: name
            ))
        case .workflow:
            self = .workflow(WorkflowCallTrigger(name: name))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .deviceStateChange(trigger):
            try container.encode(TriggerType.deviceStateChange, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(trigger.serviceId, forKey: .serviceId)
            try container.encode(trigger.characteristicType, forKey: .characteristicType)
            try container.encode(trigger.condition, forKey: .condition)
        case let .compound(trigger):
            try container.encode(TriggerType.compound, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.logicOperator, forKey: .logicOperator)
            try container.encode(trigger.triggers, forKey: .triggers)
        case let .schedule(trigger):
            try container.encode(TriggerType.schedule, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.scheduleType, forKey: .scheduleType)
        case let .webhook(trigger):
            try container.encode(TriggerType.webhook, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.token, forKey: .token)
        case let .workflow(trigger):
            try container.encode(TriggerType.workflow, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
        }
    }
}

struct DeviceStateTrigger {
    let deviceId: String
    let serviceId: String?
    let characteristicType: String
    let condition: TriggerCondition
    let name: String?

    init(deviceId: String, serviceId: String? = nil, characteristicType: String, condition: TriggerCondition, name: String? = nil) {
        self.deviceId = deviceId
        self.serviceId = serviceId
        self.characteristicType = characteristicType
        self.condition = condition
        self.name = name
    }
}

struct CompoundTrigger {
    let logicOperator: LogicOperator
    let triggers: [WorkflowTrigger]
    let name: String?

    init(logicOperator: LogicOperator, triggers: [WorkflowTrigger], name: String? = nil) {
        self.logicOperator = logicOperator
        self.triggers = triggers
        self.name = name
    }
}

struct ScheduleTrigger {
    let scheduleType: ScheduleType
    let name: String?

    init(scheduleType: ScheduleType, name: String? = nil) {
        self.scheduleType = scheduleType
        self.name = name
    }
}

enum ScheduleType: Codable {
    case once(date: Date)
    case daily(time: ScheduleTime)
    case weekly(time: ScheduleTime, days: Set<ScheduleWeekday>)
    case interval(seconds: TimeInterval)

    private enum TypeKey: String, Codable {
        case once, daily, weekly, interval
    }

    private enum CodingKeys: String, CodingKey {
        case type, date, time, days, seconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeKey.self, forKey: .type)
        switch type {
        case .once:
            self = try .once(date: container.decode(Date.self, forKey: .date))
        case .daily:
            self = try .daily(time: container.decode(ScheduleTime.self, forKey: .time))
        case .weekly:
            self = try .weekly(
                time: container.decode(ScheduleTime.self, forKey: .time),
                days: container.decode(Set<ScheduleWeekday>.self, forKey: .days)
            )
        case .interval:
            self = try .interval(seconds: container.decode(TimeInterval.self, forKey: .seconds))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .once(date):
            try container.encode(TypeKey.once, forKey: .type)
            try container.encode(date, forKey: .date)
        case let .daily(time):
            try container.encode(TypeKey.daily, forKey: .type)
            try container.encode(time, forKey: .time)
        case let .weekly(time, days):
            try container.encode(TypeKey.weekly, forKey: .type)
            try container.encode(time, forKey: .time)
            try container.encode(days, forKey: .days)
        case let .interval(seconds):
            try container.encode(TypeKey.interval, forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        }
    }
}

struct ScheduleTime: Codable, Equatable {
    let hour: Int
    let minute: Int
}

enum ScheduleWeekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var displayName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    static func < (lhs: ScheduleWeekday, rhs: ScheduleWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WebhookTrigger {
    let token: String
    let name: String?

    init(token: String = UUID().uuidString, name: String? = nil) {
        self.token = token
        self.name = name
    }
}

struct WorkflowCallTrigger: Codable {
    let name: String?

    init(name: String? = nil) {
        self.name = name
    }
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
            self = try .equals(container.decode(AnyCodable.self, forKey: .value))
        case .notEquals:
            self = try .notEquals(container.decode(AnyCodable.self, forKey: .value))
        case .transitioned:
            self = try .transitioned(
                from: container.decodeIfPresent(AnyCodable.self, forKey: .from),
                to: container.decode(AnyCodable.self, forKey: .to)
            )
        case .greaterThan:
            self = try .greaterThan(container.decode(Double.self, forKey: .value))
        case .lessThan:
            self = try .lessThan(container.decode(Double.self, forKey: .value))
        case .greaterThanOrEqual:
            self = try .greaterThanOrEqual(container.decode(Double.self, forKey: .value))
        case .lessThanOrEqual:
            self = try .lessThanOrEqual(container.decode(Double.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .changed:
            try container.encode(ConditionType.changed, forKey: .type)
        case let .equals(value):
            try container.encode(ConditionType.equals, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .notEquals(value):
            try container.encode(ConditionType.notEquals, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .transitioned(from, to):
            try container.encode(ConditionType.transitioned, forKey: .type)
            try container.encodeIfPresent(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .greaterThan(value):
            try container.encode(ConditionType.greaterThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .lessThan(value):
            try container.encode(ConditionType.lessThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .greaterThanOrEqual(value):
            try container.encode(ConditionType.greaterThanOrEqual, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .lessThanOrEqual(value):
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
            self = try .deviceState(DeviceStateCondition(
                deviceId: container.decode(String.self, forKey: .deviceId),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicType: container.decode(String.self, forKey: .characteristicType),
                comparison: container.decode(ComparisonOperator.self, forKey: .comparison)
            ))
        case .and:
            self = try .and(container.decode([WorkflowCondition].self, forKey: .conditions))
        case .or:
            self = try .or(container.decode([WorkflowCondition].self, forKey: .conditions))
        case .not:
            self = try .not(container.decode(WorkflowCondition.self, forKey: .condition))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .deviceState(cond):
            try container.encode(ConditionType.deviceState, forKey: .type)
            try container.encode(cond.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(cond.serviceId, forKey: .serviceId)
            try container.encode(cond.characteristicType, forKey: .characteristicType)
            try container.encode(cond.comparison, forKey: .comparison)
        case let .and(conditions):
            try container.encode(ConditionType.and, forKey: .type)
            try container.encode(conditions, forKey: .conditions)
        case let .or(conditions):
            try container.encode(ConditionType.or, forKey: .type)
            try container.encode(conditions, forKey: .conditions)
        case let .not(condition):
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
            self = try .equals(container.decode(AnyCodable.self, forKey: .value))
        case .notEquals:
            self = try .notEquals(container.decode(AnyCodable.self, forKey: .value))
        case .greaterThan:
            self = try .greaterThan(container.decode(Double.self, forKey: .value))
        case .lessThan:
            self = try .lessThan(container.decode(Double.self, forKey: .value))
        case .greaterThanOrEqual:
            self = try .greaterThanOrEqual(container.decode(Double.self, forKey: .value))
        case .lessThanOrEqual:
            self = try .lessThanOrEqual(container.decode(Double.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .equals(value):
            try container.encode(OperatorType.equals, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .notEquals(value):
            try container.encode(OperatorType.notEquals, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .greaterThan(value):
            try container.encode(OperatorType.greaterThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .lessThan(value):
            try container.encode(OperatorType.lessThan, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .greaterThanOrEqual(value):
            try container.encode(OperatorType.greaterThanOrEqual, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .lessThanOrEqual(value):
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
    let deviceId: String?
    let deviceName: String?
    let serviceId: String?
    let characteristicType: String?
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
    let triggerDescription: String?
}

struct ConditionResult: Codable {
    let conditionDescription: String
    let passed: Bool
}

struct BlockResult: Identifiable, Codable {
    let id: UUID
    let blockIndex: Int
    let blockKind: String
    let blockType: String
    let blockName: String?
    var status: ExecutionStatus
    let startedAt: Date
    var completedAt: Date?
    var detail: String?
    var errorMessage: String?
    var nestedResults: [BlockResult]?

    init(
        id: UUID = UUID(),
        blockIndex: Int,
        blockKind: String,
        blockType: String,
        blockName: String? = nil,
        status: ExecutionStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        detail: String? = nil,
        errorMessage: String? = nil,
        nestedResults: [BlockResult]? = nil
    ) {
        self.id = id
        self.blockIndex = blockIndex
        self.blockKind = blockKind
        self.blockType = blockType
        self.blockName = blockName
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
    case cancelled
}
