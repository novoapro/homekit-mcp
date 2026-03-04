import Foundation

// MARK: - Concurrent Execution Policy

enum ConcurrentExecutionPolicy: String, Codable, CaseIterable, Identifiable {
    /// Ignore the new trigger while the workflow is already running.
    case ignoreNew
    /// Cancel the running execution and start fresh from the new trigger.
    case cancelAndRestart
    /// Queue the new trigger; it will execute after the current run finishes.
    case queueAndExecute
    /// Cancel the running execution without restarting.
    case cancelOnly

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .ignoreNew: return "Ignore trigger"
        case .cancelAndRestart: return "Restart workflow"
        case .queueAndExecute: return "Queue new execution"
        case .cancelOnly: return "Cancel workflow"
        }
    }

    var description: String {
        switch self {
        case .ignoreNew: return "New triggers are ignored while the workflow is running."
        case .cancelAndRestart: return "The running execution is cancelled and restarted with the new trigger."
        case .queueAndExecute: return "New triggers are queued and executed once the current run completes."
        case .cancelOnly: return "The running execution is cancelled. No new execution starts."
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
        let decodedTriggers = try container.decode([WorkflowTrigger].self, forKey: .triggers)
        conditions = try container.decodeIfPresent([WorkflowCondition].self, forKey: .conditions)
        blocks = try container.decode([WorkflowBlock].self, forKey: .blocks)
        continueOnError = try container.decode(Bool.self, forKey: .continueOnError)
        retriggerPolicy = try container.decodeIfPresent(ConcurrentExecutionPolicy.self, forKey: .retriggerPolicy) ?? .ignoreNew
        metadata = try container.decode(WorkflowMetadata.self, forKey: .metadata)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Backward compat: migrate workflow-level retriggerPolicy to triggers that don't have one
        let workflowPolicy = retriggerPolicy
        triggers = decodedTriggers.map { trigger in
            if trigger.retriggerPolicy == nil {
                return trigger.withRetriggerPolicy(workflowPolicy)
            }
            return trigger
        }
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
    case action(WorkflowAction, blockId: UUID)
    case flowControl(FlowControlBlock, blockId: UUID)

    var blockId: UUID {
        switch self {
        case .action(_, let id), .flowControl(_, let id): return id
        }
    }

    private enum BlockKind: String, Codable {
        case action
        case flowControl
    }

    private enum CodingKeys: String, CodingKey {
        case block, blockId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(BlockKind.self, forKey: .block)
        let blockId = try container.decodeIfPresent(UUID.self, forKey: .blockId) ?? UUID()
        switch kind {
        case .action:
            self = try .action(WorkflowAction(from: decoder), blockId: blockId)
        case .flowControl:
            self = try .flowControl(FlowControlBlock(from: decoder), blockId: blockId)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .action(action, blockId):
            try container.encode(BlockKind.action, forKey: .block)
            try container.encode(blockId, forKey: .blockId)
            try action.encode(to: encoder)
        case let .flowControl(flowControl, blockId):
            try container.encode(BlockKind.flowControl, forKey: .block)
            try container.encode(blockId, forKey: .blockId)
            try flowControl.encode(to: encoder)
        }
    }
}

// MARK: - Actions (Atomic Leaf Nodes)

enum WorkflowAction: Codable {
    case controlDevice(ControlDeviceAction)
    case webhook(WebhookActionConfig)
    case log(LogAction)
    case runScene(RunSceneAction)

    private enum ActionType: String, Codable {
        case controlDevice
        case webhook
        case log
        case runScene
        case activateScene // legacy alias for decoding
    }

    private enum CodingKeys: String, CodingKey {
        case type, name
        case deviceId, deviceName, roomName, serviceId, characteristicId, characteristicType, value
        case url, method, headers, body
        case message
        case sceneId, sceneName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        switch type {
        case .controlDevice:
            let charId = try container.decodeIfPresent(String.self, forKey: .characteristicId)
                ?? container.decode(String.self, forKey: .characteristicType)
            self = try .controlDevice(ControlDeviceAction(
                deviceId: container.decode(String.self, forKey: .deviceId),
                deviceName: container.decodeIfPresent(String.self, forKey: .deviceName),
                roomName: container.decodeIfPresent(String.self, forKey: .roomName),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicId: charId,
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
        case .runScene, .activateScene:
            self = try .runScene(RunSceneAction(
                sceneId: container.decode(String.self, forKey: .sceneId),
                sceneName: container.decodeIfPresent(String.self, forKey: .sceneName),
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
            try container.encodeIfPresent(action.deviceName, forKey: .deviceName)
            try container.encodeIfPresent(action.roomName, forKey: .roomName)
            try container.encodeIfPresent(action.serviceId, forKey: .serviceId)
            try container.encode(action.characteristicId, forKey: .characteristicId)
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
        case let .runScene(action):
            try container.encode(ActionType.runScene, forKey: .type)
            try container.encodeIfPresent(action.name, forKey: .name)
            try container.encode(action.sceneId, forKey: .sceneId)
            try container.encodeIfPresent(action.sceneName, forKey: .sceneName)
        }
    }

    var displayType: String {
        switch self {
        case .controlDevice: return "controlDevice"
        case .webhook: return "webhook"
        case .log: return "log"
        case .runScene: return "runScene"
        }
    }
}

struct ControlDeviceAction {
    let deviceId: String
    let deviceName: String?
    let roomName: String?
    let serviceId: String?
    let characteristicId: String
    let value: AnyCodable
    let name: String?

    init(deviceId: String, deviceName: String? = nil, roomName: String? = nil, serviceId: String? = nil, characteristicId: String, value: AnyCodable, name: String? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.serviceId = serviceId
        self.characteristicId = characteristicId
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

struct RunSceneAction {
    let sceneId: String
    let sceneName: String?
    let name: String?

    init(sceneId: String, sceneName: String? = nil, name: String? = nil) {
        self.sceneId = sceneId
        self.sceneName = sceneName
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

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Accept both "stop" (legacy) and "return" (new) for backward compatibility
            if raw == "return" { self = .stop; return }
            guard let value = FlowControlType(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown FlowControlType: \(raw)")
            }
            self = value
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            // Serialize "stop" as "return" going forward
            try container.encode(self == .stop ? "return" : rawValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, name
        case seconds
        case deviceId, serviceId, characteristicId, characteristicType, condition, timeoutSeconds
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
            // New format: condition is a WorkflowCondition (AND/OR/NOT groups)
            // Old format: flat deviceId + characteristicId + ComparisonOperator → migrate to WorkflowCondition
            let condition: WorkflowCondition
            if let deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) {
                // Old flat format — convert to WorkflowCondition.deviceState
                let charId = try container.decodeIfPresent(String.self, forKey: .characteristicId)
                    ?? container.decode(String.self, forKey: .characteristicType)
                let comparison = try container.decode(ComparisonOperator.self, forKey: .condition)
                let serviceId = try container.decodeIfPresent(String.self, forKey: .serviceId)
                condition = .deviceState(DeviceStateCondition(
                    deviceId: deviceId,
                    serviceId: serviceId,
                    characteristicId: charId,
                    comparison: comparison
                ))
            } else {
                condition = try container.decode(WorkflowCondition.self, forKey: .condition)
            }
            self = try .waitForState(WaitForStateBlock(
                condition: condition,
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
        case .stop: return "return"
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
    let condition: WorkflowCondition
    let timeoutSeconds: Double
    let name: String?

    init(condition: WorkflowCondition, timeoutSeconds: Double, name: String? = nil) {
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

enum WorkflowTrigger: Codable {
    case deviceStateChange(DeviceStateTrigger)
    case schedule(ScheduleTrigger)
    case webhook(WebhookTrigger)
    case workflow(WorkflowCallTrigger)
    case sunEvent(SunEventTrigger)

    private enum TriggerType: String, Codable {
        case deviceStateChange
        case schedule
        case webhook
        case workflow
        case sunEvent
    }

    private enum CodingKeys: String, CodingKey {
        case type, name
        case deviceId, deviceName, roomName, serviceId, characteristicId, characteristicType, condition
        case scheduleType, token
        case event, offsetMinutes
        case retriggerPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TriggerType.self, forKey: .type)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let policy = try container.decodeIfPresent(ConcurrentExecutionPolicy.self, forKey: .retriggerPolicy)
        switch type {
        case .deviceStateChange:
            let charId = try container.decodeIfPresent(String.self, forKey: .characteristicId)
                ?? container.decode(String.self, forKey: .characteristicType)
            self = try .deviceStateChange(DeviceStateTrigger(
                deviceId: container.decode(String.self, forKey: .deviceId),
                deviceName: container.decodeIfPresent(String.self, forKey: .deviceName),
                roomName: container.decodeIfPresent(String.self, forKey: .roomName),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicId: charId,
                condition: container.decode(TriggerCondition.self, forKey: .condition),
                name: name,
                retriggerPolicy: policy
            ))
        case .schedule:
            self = try .schedule(ScheduleTrigger(
                scheduleType: container.decode(ScheduleType.self, forKey: .scheduleType),
                name: name,
                retriggerPolicy: policy
            ))
        case .webhook:
            self = try .webhook(WebhookTrigger(
                token: container.decodeIfPresent(String.self, forKey: .token) ?? UUID().uuidString,
                name: name,
                retriggerPolicy: policy
            ))
        case .workflow:
            self = .workflow(WorkflowCallTrigger(name: name, retriggerPolicy: policy))
        case .sunEvent:
            self = try .sunEvent(SunEventTrigger(
                event: container.decode(SunEventType.self, forKey: .event),
                offsetMinutes: container.decodeIfPresent(Int.self, forKey: .offsetMinutes) ?? 0,
                name: name,
                retriggerPolicy: policy
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .deviceStateChange(trigger):
            try container.encode(TriggerType.deviceStateChange, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.deviceId, forKey: .deviceId)
            try container.encodeIfPresent(trigger.deviceName, forKey: .deviceName)
            try container.encodeIfPresent(trigger.roomName, forKey: .roomName)
            try container.encodeIfPresent(trigger.serviceId, forKey: .serviceId)
            try container.encode(trigger.characteristicId, forKey: .characteristicId)
            try container.encode(trigger.condition, forKey: .condition)
            try container.encodeIfPresent(trigger.retriggerPolicy, forKey: .retriggerPolicy)
        case let .schedule(trigger):
            try container.encode(TriggerType.schedule, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.scheduleType, forKey: .scheduleType)
            try container.encodeIfPresent(trigger.retriggerPolicy, forKey: .retriggerPolicy)
        case let .webhook(trigger):
            try container.encode(TriggerType.webhook, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.token, forKey: .token)
            try container.encodeIfPresent(trigger.retriggerPolicy, forKey: .retriggerPolicy)
        case let .workflow(trigger):
            try container.encode(TriggerType.workflow, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encodeIfPresent(trigger.retriggerPolicy, forKey: .retriggerPolicy)
        case let .sunEvent(trigger):
            try container.encode(TriggerType.sunEvent, forKey: .type)
            try container.encodeIfPresent(trigger.name, forKey: .name)
            try container.encode(trigger.event, forKey: .event)
            try container.encode(trigger.offsetMinutes, forKey: .offsetMinutes)
            try container.encodeIfPresent(trigger.retriggerPolicy, forKey: .retriggerPolicy)
        }
    }
    /// The per-trigger retrigger policy, if set.
    var retriggerPolicy: ConcurrentExecutionPolicy? {
        switch self {
        case .deviceStateChange(let t): return t.retriggerPolicy
        case .schedule(let t): return t.retriggerPolicy
        case .webhook(let t): return t.retriggerPolicy
        case .workflow(let t): return t.retriggerPolicy
        case .sunEvent(let t): return t.retriggerPolicy
        }
    }

    /// Resolved policy: per-trigger if set, otherwise defaults to `.ignoreNew`.
    var resolvedRetriggerPolicy: ConcurrentExecutionPolicy {
        retriggerPolicy ?? .ignoreNew
    }

    /// Returns a copy of this trigger with the given retrigger policy applied.
    func withRetriggerPolicy(_ policy: ConcurrentExecutionPolicy) -> WorkflowTrigger {
        switch self {
        case .deviceStateChange(let t):
            return .deviceStateChange(DeviceStateTrigger(
                deviceId: t.deviceId, deviceName: t.deviceName, roomName: t.roomName,
                serviceId: t.serviceId,
                characteristicId: t.characteristicId, condition: t.condition,
                name: t.name, retriggerPolicy: policy
            ))
        case .schedule(let t):
            return .schedule(ScheduleTrigger(
                scheduleType: t.scheduleType, name: t.name, retriggerPolicy: policy
            ))
        case .webhook(let t):
            return .webhook(WebhookTrigger(
                token: t.token, name: t.name, retriggerPolicy: policy
            ))
        case .workflow(let t):
            return .workflow(WorkflowCallTrigger(
                name: t.name, retriggerPolicy: policy
            ))
        case .sunEvent(let t):
            return .sunEvent(SunEventTrigger(
                event: t.event, offsetMinutes: t.offsetMinutes,
                name: t.name, retriggerPolicy: policy
            ))
        }
    }
}

struct DeviceStateTrigger {
    let deviceId: String
    let deviceName: String?
    let roomName: String?
    let serviceId: String?
    let characteristicId: String
    let condition: TriggerCondition
    let name: String?
    let retriggerPolicy: ConcurrentExecutionPolicy?

    init(deviceId: String, deviceName: String? = nil, roomName: String? = nil, serviceId: String? = nil, characteristicId: String, condition: TriggerCondition, name: String? = nil, retriggerPolicy: ConcurrentExecutionPolicy? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.serviceId = serviceId
        self.characteristicId = characteristicId
        self.condition = condition
        self.name = name
        self.retriggerPolicy = retriggerPolicy
    }
}

struct ScheduleTrigger {
    let scheduleType: ScheduleType
    let name: String?
    let retriggerPolicy: ConcurrentExecutionPolicy?

    init(scheduleType: ScheduleType, name: String? = nil, retriggerPolicy: ConcurrentExecutionPolicy? = nil) {
        self.scheduleType = scheduleType
        self.name = name
        self.retriggerPolicy = retriggerPolicy
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
    let retriggerPolicy: ConcurrentExecutionPolicy?

    init(token: String = UUID().uuidString, name: String? = nil, retriggerPolicy: ConcurrentExecutionPolicy? = nil) {
        self.token = token
        self.name = name
        self.retriggerPolicy = retriggerPolicy
    }
}

struct WorkflowCallTrigger: Codable {
    let name: String?
    let retriggerPolicy: ConcurrentExecutionPolicy?

    init(name: String? = nil, retriggerPolicy: ConcurrentExecutionPolicy? = nil) {
        self.name = name
        self.retriggerPolicy = retriggerPolicy
    }
}

enum SunEventType: String, Codable, CaseIterable, Identifiable {
    case sunrise
    case sunset

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        }
    }
}

struct SunEventTrigger {
    let event: SunEventType
    let offsetMinutes: Int
    let name: String?
    let retriggerPolicy: ConcurrentExecutionPolicy?

    init(event: SunEventType, offsetMinutes: Int = 0, name: String? = nil, retriggerPolicy: ConcurrentExecutionPolicy? = nil) {
        self.event = event
        self.offsetMinutes = offsetMinutes
        self.name = name
        self.retriggerPolicy = retriggerPolicy
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
    case transitioned(from: AnyCodable?, to: AnyCodable?)
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
                to: container.decodeIfPresent(AnyCodable.self, forKey: .to)
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
            try container.encodeIfPresent(to, forKey: .to)
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

// MARK: - Block Result Condition

enum BlockResultScope: Codable {
    case specific(blockId: UUID)
    case all
    case any

    private enum ScopeType: String, Codable {
        case specific, all, any
    }

    private enum CodingKeys: String, CodingKey {
        case scope, blockId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scope = try container.decode(ScopeType.self, forKey: .scope)
        switch scope {
        case .specific:
            self = try .specific(blockId: container.decode(UUID.self, forKey: .blockId))
        case .all:
            self = .all
        case .any:
            self = .any
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .specific(blockId):
            try container.encode(ScopeType.specific, forKey: .scope)
            try container.encode(blockId, forKey: .blockId)
        case .all:
            try container.encode(ScopeType.all, forKey: .scope)
        case .any:
            try container.encode(ScopeType.any, forKey: .scope)
        }
    }
}

struct BlockResultCondition: Codable {
    let scope: BlockResultScope
    let expectedStatus: ExecutionStatus

    init(scope: BlockResultScope, expectedStatus: ExecutionStatus = .success) {
        self.scope = scope
        self.expectedStatus = expectedStatus
    }
}

// MARK: - Workflow Conditions (Guard Expressions)

indirect enum WorkflowCondition: Codable {
    case deviceState(DeviceStateCondition)
    case timeCondition(TimeCondition)
    case sceneActive(SceneActiveCondition)
    case blockResult(BlockResultCondition)
    case and([WorkflowCondition])
    case or([WorkflowCondition])
    case not(WorkflowCondition)

    private enum ConditionType: String, Codable {
        case deviceState
        case timeCondition
        case sunEvent // backward compat decode only
        case sceneActive
        case blockResult
        case and
        case or
        case not
    }

    private enum CodingKeys: String, CodingKey {
        case type, conditions, condition
        case deviceId, deviceName, roomName, serviceId, characteristicId, characteristicType, comparison
        // timeCondition fields
        case mode, startTime, endTime
        // legacy sunEvent fields (decode only)
        case event, sunComparison
        case sceneId, sceneName, isActive
        // blockResult fields
        case blockResultScope, expectedStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ConditionType.self, forKey: .type)
        switch type {
        case .deviceState:
            let charId = try container.decodeIfPresent(String.self, forKey: .characteristicId)
                ?? container.decode(String.self, forKey: .characteristicType)
            self = try .deviceState(DeviceStateCondition(
                deviceId: container.decode(String.self, forKey: .deviceId),
                deviceName: container.decodeIfPresent(String.self, forKey: .deviceName),
                roomName: container.decodeIfPresent(String.self, forKey: .roomName),
                serviceId: container.decodeIfPresent(String.self, forKey: .serviceId),
                characteristicId: charId,
                comparison: container.decode(ComparisonOperator.self, forKey: .comparison)
            ))
        case .timeCondition:
            self = try .timeCondition(TimeCondition(
                mode: container.decode(TimeConditionMode.self, forKey: .mode),
                startTime: container.decodeIfPresent(TimeOfDay.self, forKey: .startTime),
                endTime: container.decodeIfPresent(TimeOfDay.self, forKey: .endTime)
            ))
        case .sunEvent:
            // Backward compat: map old sunEvent → timeCondition
            let event = try container.decode(SunEventType.self, forKey: .event)
            let comp = try container.decode(String.self, forKey: .sunComparison)
            let mode: TimeConditionMode
            switch (event, comp) {
            case (.sunrise, "before"): mode = .beforeSunrise
            case (.sunrise, _):       mode = .afterSunrise
            case (.sunset, "before"): mode = .beforeSunset
            case (.sunset, _):        mode = .afterSunset
            }
            self = .timeCondition(TimeCondition(mode: mode))
        case .sceneActive:
            self = try .sceneActive(SceneActiveCondition(
                sceneId: container.decode(String.self, forKey: .sceneId),
                sceneName: container.decodeIfPresent(String.self, forKey: .sceneName),
                isActive: container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
            ))
        case .blockResult:
            self = try .blockResult(BlockResultCondition(
                scope: container.decode(BlockResultScope.self, forKey: .blockResultScope),
                expectedStatus: container.decode(ExecutionStatus.self, forKey: .expectedStatus)
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
            try container.encodeIfPresent(cond.deviceName, forKey: .deviceName)
            try container.encodeIfPresent(cond.roomName, forKey: .roomName)
            try container.encodeIfPresent(cond.serviceId, forKey: .serviceId)
            try container.encode(cond.characteristicId, forKey: .characteristicId)
            try container.encode(cond.comparison, forKey: .comparison)
        case let .timeCondition(cond):
            try container.encode(ConditionType.timeCondition, forKey: .type)
            try container.encode(cond.mode, forKey: .mode)
            try container.encodeIfPresent(cond.startTime, forKey: .startTime)
            try container.encodeIfPresent(cond.endTime, forKey: .endTime)
        case let .sceneActive(cond):
            try container.encode(ConditionType.sceneActive, forKey: .type)
            try container.encodeIfPresent(cond.sceneName, forKey: .sceneName)
            try container.encode(cond.sceneId, forKey: .sceneId)
            try container.encode(cond.isActive, forKey: .isActive)
        case let .blockResult(cond):
            try container.encode(ConditionType.blockResult, forKey: .type)
            try container.encode(cond.scope, forKey: .blockResultScope)
            try container.encode(cond.expectedStatus, forKey: .expectedStatus)
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
    let deviceName: String?
    let roomName: String?
    let serviceId: String?
    let characteristicId: String
    let comparison: ComparisonOperator

    init(deviceId: String, deviceName: String? = nil, roomName: String? = nil, serviceId: String? = nil, characteristicId: String, comparison: ComparisonOperator) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.serviceId = serviceId
        self.characteristicId = characteristicId
        self.comparison = comparison
    }
}

// MARK: - Time Condition Types

enum TimeConditionMode: String, Codable, CaseIterable, Identifiable {
    case beforeSunrise
    case afterSunrise
    case beforeSunset
    case afterSunset
    case daytime      // between sunrise and sunset
    case nighttime    // between sunset and next sunrise
    case timeRange    // between specific times (cross-midnight aware)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beforeSunrise: return "Before Sunrise"
        case .afterSunrise: return "After Sunrise"
        case .beforeSunset: return "Before Sunset"
        case .afterSunset: return "After Sunset"
        case .daytime: return "Daytime"
        case .nighttime: return "Nighttime"
        case .timeRange: return "Time Range"
        }
    }

    var icon: String {
        switch self {
        case .beforeSunrise, .afterSunrise: return "sunrise.fill"
        case .beforeSunset, .afterSunset: return "sunset.fill"
        case .daytime: return "sun.max.fill"
        case .nighttime: return "moon.stars.fill"
        case .timeRange: return "clock.fill"
        }
    }

    /// Whether this mode requires lat/lon for solar calculation
    var requiresLocation: Bool {
        switch self {
        case .timeRange: return false
        default: return true
        }
    }
}

struct TimeOfDay: Codable, Equatable, Hashable {
    let hour: Int    // 0-23
    let minute: Int  // 0-59

    /// Minutes since midnight
    var totalMinutes: Int { hour * 60 + minute }

    /// Formatted as "HH:mm"
    var formatted: String {
        String(format: "%d:%02d %@", hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour), minute, hour < 12 ? "AM" : "PM")
    }

    static let midnight = TimeOfDay(hour: 0, minute: 0)
    static let noon = TimeOfDay(hour: 12, minute: 0)
}

struct TimeCondition: Codable {
    let mode: TimeConditionMode
    let startTime: TimeOfDay?  // Only for .timeRange
    let endTime: TimeOfDay?    // Only for .timeRange

    init(mode: TimeConditionMode, startTime: TimeOfDay? = nil, endTime: TimeOfDay? = nil) {
        self.mode = mode
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct SceneActiveCondition: Codable {
    let sceneId: String
    let sceneName: String?
    let isActive: Bool

    init(sceneId: String, sceneName: String? = nil, isActive: Bool = true) {
        self.sceneId = sceneId
        self.sceneName = sceneName
        self.isActive = isActive
    }
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

    /// Converts to a `StateChangeLog` for the unified `/logs` API response.
    /// The full `WorkflowExecutionLog` is embedded in the payload so clients receive the complete
    /// block execution tree without a second request.
    func toStateChangeLog() -> StateChangeLog {
        let category: LogCategory = (status == .failure) ? .workflowError : .workflowExecution
        return StateChangeLog(
            id: id,
            timestamp: triggeredAt,
            category: category,
            payload: category == .workflowError ? .workflowError(self) : .workflowExecution(self)
        )
    }
}

struct TriggerEvent: Codable {
    let deviceId: String?
    let deviceName: String?
    let serviceName: String?
    let characteristicName: String?
    let roomName: String?
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
    let triggerDescription: String?
}

struct ConditionResult: Codable {
    let conditionDescription: String
    let passed: Bool
    var subResults: [ConditionResult]?
    var logicOperator: String?
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

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .success: return "Success"
        case .failure: return "Failure"
        case .skipped: return "Skipped"
        case .conditionNotMet: return "Skipped"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Trigger Result (Fire-and-Forget)

/// Immediate result of a trigger request. Describes what happened when the trigger
/// was submitted, not the outcome of the workflow execution itself.
enum TriggerResult: Codable {
    case scheduled(workflowId: UUID, workflowName: String)
    case replaced(workflowId: UUID, workflowName: String)
    case queued(workflowId: UUID, workflowName: String)
    case ignored(workflowId: UUID, workflowName: String)
    case cancelled(workflowId: UUID, workflowName: String)
    case notFound
    case disabled
    case workflowDisabled(workflowId: UUID, workflowName: String)

    var message: String {
        switch self {
        case .scheduled(_, let name):
            return "Workflow '\(name)' execution scheduled."
        case .replaced(_, let name):
            return "Previous execution of '\(name)' was cancelled; new execution scheduled."
        case .queued(_, let name):
            return "Workflow '\(name)' has been queued for execution."
        case .ignored(_, let name):
            return "Trigger ignored: '\(name)' is already running."
        case .cancelled(_, let name):
            return "Running execution of '\(name)' was cancelled. No new execution started."
        case .notFound:
            return "Workflow not found."
        case .disabled:
            return "Workflows are disabled."
        case .workflowDisabled(_, let name):
            return "Workflow '\(name)' is disabled."
        }
    }

    var isAccepted: Bool {
        switch self {
        case .scheduled, .replaced, .queued, .cancelled: return true
        case .ignored, .notFound, .disabled, .workflowDisabled: return false
        }
    }

    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }

    var httpStatusCode: UInt {
        switch self {
        case .scheduled, .replaced, .queued, .cancelled: return 202
        case .ignored: return 409
        case .notFound: return 404
        case .disabled, .workflowDisabled: return 503
        }
    }

    // MARK: Codable — flat JSON

    private enum CodingKeys: String, CodingKey {
        case status, workflowId, workflowName, message
    }

    private var statusString: String {
        switch self {
        case .scheduled: return "scheduled"
        case .replaced: return "replaced"
        case .queued: return "queued"
        case .ignored: return "ignored"
        case .cancelled: return "cancelled"
        case .notFound: return "not_found"
        case .disabled: return "disabled"
        case .workflowDisabled: return "workflow_disabled"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusString, forKey: .status)
        try container.encode(message, forKey: .message)

        switch self {
        case .scheduled(let id, let name),
             .replaced(let id, let name),
             .queued(let id, let name),
             .ignored(let id, let name),
             .cancelled(let id, let name),
             .workflowDisabled(let id, let name):
            try container.encode(id, forKey: .workflowId)
            try container.encode(name, forKey: .workflowName)
        case .notFound, .disabled:
            break
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "scheduled":
            let id = try container.decode(UUID.self, forKey: .workflowId)
            let name = try container.decode(String.self, forKey: .workflowName)
            self = .scheduled(workflowId: id, workflowName: name)
        case "replaced":
            let id = try container.decode(UUID.self, forKey: .workflowId)
            let name = try container.decode(String.self, forKey: .workflowName)
            self = .replaced(workflowId: id, workflowName: name)
        case "queued":
            let id = try container.decode(UUID.self, forKey: .workflowId)
            let name = try container.decode(String.self, forKey: .workflowName)
            self = .queued(workflowId: id, workflowName: name)
        case "ignored":
            let id = try container.decode(UUID.self, forKey: .workflowId)
            let name = try container.decode(String.self, forKey: .workflowName)
            self = .ignored(workflowId: id, workflowName: name)
        case "cancelled":
            let id = try container.decode(UUID.self, forKey: .workflowId)
            let name = try container.decode(String.self, forKey: .workflowName)
            self = .cancelled(workflowId: id, workflowName: name)
        case "not_found":
            self = .notFound
        case "disabled":
            self = .disabled
        case "workflow_disabled":
            let id = try container.decode(UUID.self, forKey: .workflowId)
            let name = try container.decode(String.self, forKey: .workflowName)
            self = .workflowDisabled(workflowId: id, workflowName: name)
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown trigger result status: \(status)")
        }
    }
}
