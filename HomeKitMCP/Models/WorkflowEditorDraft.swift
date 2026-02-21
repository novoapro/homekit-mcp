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

    var id: String {
        rawValue
    }

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

    var id: String {
        rawValue
    }

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

    var symbol: String {
        switch self {
        case .equals: return "="
        case .notEquals: return "≠"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .greaterThanOrEqual: return "≥"
        case .lessThanOrEqual: return "≤"
        }
    }
}

enum TriggerDraftType: String, CaseIterable, Identifiable {
    case deviceStateChange
    case schedule
    case webhook
    case workflow

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .deviceStateChange: return "Device State Change"
        case .schedule: return "Schedule"
        case .webhook: return "Webhook"
        case .workflow: return "Workflow"
        }
    }

    var icon: String {
        switch self {
        case .deviceStateChange: return "bolt.fill"
        case .schedule: return "clock.fill"
        case .webhook: return "arrow.down.circle.fill"
        case .workflow: return "arrow.triangle.turn.up.right.diamond"
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
    var retriggerPolicy: ConcurrentExecutionPolicy
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
            retriggerPolicy: .ignoreNew,
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
    var triggerType: TriggerDraftType = .deviceStateChange

    // Device state change fields
    var deviceId: String = ""
    var serviceId: String?
    var characteristicType: String = ""
    var conditionType: TriggerConditionType = .changed
    var conditionValue: String = ""
    var conditionFromValue: String = ""

    // Schedule fields
    var scheduleType: ScheduleDraftType = .daily
    var scheduleHour: Int = 8
    var scheduleMinute: Int = 0
    var scheduleDays: Set<ScheduleWeekday> = []
    var scheduleDate: Date = .init()
    var scheduleIntervalAmount: Int = 1
    var scheduleIntervalUnit: ScheduleIntervalUnit = .hours

    /// Webhook fields
    var webhookToken: String = UUID().uuidString

    static func empty() -> TriggerDraft {
        TriggerDraft(id: UUID())
    }

    static func emptySchedule() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .schedule)
    }

    static func emptyWebhook() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .webhook)
    }

    static func emptyWorkflow() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .workflow)
    }
}

enum ScheduleDraftType: String, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    case interval

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .interval: return "Interval"
        }
    }
}

enum ScheduleIntervalUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        }
    }
}

// MARK: - Auto-Name Generation

extension TriggerDraft {
    func autoName(devices: [DeviceModel]) -> String {
        switch triggerType {
        case .deviceStateChange:
            guard !deviceId.isEmpty else { return "New Trigger" }
            let device = devices.first(where: { $0.id == deviceId })
            let room = device?.roomName ?? ""
            let devName = device?.name ?? "Unknown"
            let charName = characteristicType.isEmpty ? "" : CharacteristicTypes.displayName(for: characteristicType)
            let condDesc = conditionType == .changed ? "Changed" : "\(conditionType.displayName) \(conditionValue)"
            let parts = [room, devName, charName, condDesc].filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        case .schedule:
            return scheduleAutoName
        case .webhook:
            return "Webhook Trigger"
        case .workflow:
            return "Workflow Trigger"
        }
    }

    private var scheduleAutoName: String {
        let hour12 = scheduleHour % 12 == 0 ? 12 : scheduleHour % 12
        let period = scheduleHour >= 12 ? "PM" : "AM"
        let timeStr = String(format: "%d:%02d %@", hour12, scheduleMinute, period)
        switch scheduleType {
        case .once:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Once at \(formatter.string(from: scheduleDate))"
        case .daily:
            return "Daily at \(timeStr)"
        case .weekly:
            if scheduleDays.isEmpty {
                return "Weekly at \(timeStr)"
            }
            let dayNames = scheduleDays.sorted().map(\.displayName).joined(separator: ", ")
            return "\(dayNames) at \(timeStr)"
        case .interval:
            return "Every \(scheduleIntervalAmount) \(scheduleIntervalUnit.displayName.lowercased())"
        }
    }
}

extension ConditionDraft {
    func autoName(devices: [DeviceModel]) -> String {
        guard !deviceId.isEmpty else { return "New Condition" }
        let device = devices.first(where: { $0.id == deviceId })
        let room = device?.roomName ?? ""
        let devName = device?.name ?? "Unknown"
        let charName = characteristicType.isEmpty ? "" : CharacteristicTypes.displayName(for: characteristicType)
        let comp = "\(comparisonType.displayName) \(comparisonValue)"
        let parts = [room, devName, charName, comp].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

extension BlockDraft {
    func autoName(devices: [DeviceModel]) -> String {
        switch blockType {
        case let .controlDevice(d):
            return d.autoName(devices: devices)
        case let .webhook(d):
            return d.autoName()
        case let .log(d):
            return d.autoName()
        case let .delay(d):
            return d.autoName()
        case let .waitForState(d):
            return d.autoName(devices: devices)
        case let .conditional(d):
            return d.autoName(devices: devices)
        case let .repeatBlock(d):
            return d.autoName()
        case let .repeatWhile(d):
            return d.autoName(devices: devices)
        case let .group(d):
            return d.autoName()
        case let .stop(d):
            return d.autoName()
        case let .executeWorkflow(d):
            return d.autoName()
        }
    }

    /// Returns the user-set name or the auto-generated name
    func displayName(devices: [DeviceModel]) -> String {
        let explicitName: String = {
            switch blockType {
            case let .controlDevice(d): return d.name
            case let .webhook(d): return d.name
            case let .log(d): return d.name
            case let .delay(d): return d.name
            case let .waitForState(d): return d.name
            case let .conditional(d): return d.name
            case let .repeatBlock(d): return d.name
            case let .repeatWhile(d): return d.name
            case let .group(d): return d.name
            case let .stop(d): return d.name
            case let .executeWorkflow(d): return d.name
            }
        }()
        return explicitName.isEmpty ? autoName(devices: devices) : explicitName
    }
}

private extension ControlDeviceDraft {
    func autoName(devices: [DeviceModel]) -> String {
        guard !deviceId.isEmpty else { return "Control Device" }
        let device = devices.first(where: { $0.id == deviceId })
        let devName = device?.name ?? "Unknown"
        let charName = characteristicType.isEmpty ? "" : CharacteristicTypes.displayName(for: characteristicType)
        if charName.isEmpty { return "Set \(devName)" }
        let valStr = value.isEmpty ? "" : "= \(value)"
        return "Set \(devName) \(charName) \(valStr)".trimmingCharacters(in: .whitespaces)
    }
}

private extension WebhookDraft {
    func autoName() -> String {
        guard !url.isEmpty else { return "Webhook" }
        if let urlObj = URL(string: url), let host = urlObj.host {
            return "\(method) \(host)"
        }
        return "\(method) \(url.prefix(30))"
    }
}

private extension LogDraft {
    func autoName() -> String {
        guard !message.isEmpty else { return "Log Message" }
        return "Log: \(String(message.prefix(30)))"
    }
}

private extension DelayDraft {
    func autoName() -> String {
        return "Delay \(seconds)s"
    }
}

private extension WaitForStateDraft {
    func autoName(devices: [DeviceModel]) -> String {
        guard !deviceId.isEmpty else { return "Wait for State" }
        let device = devices.first(where: { $0.id == deviceId })
        let devName = device?.name ?? "Unknown"
        let charName = characteristicType.isEmpty ? "" : CharacteristicTypes.displayName(for: characteristicType)
        return "Wait \(devName) \(charName) \(comparisonType.displayName) \(comparisonValue)".trimmingCharacters(in: .whitespaces)
    }
}

private extension ConditionalDraft {
    func autoName(devices: [DeviceModel]) -> String {
        guard !conditionDeviceId.isEmpty else { return "If/Else" }
        let device = devices.first(where: { $0.id == conditionDeviceId })
        let devName = device?.name ?? "Unknown"
        let charName = conditionCharacteristicType.isEmpty ? "" : CharacteristicTypes.displayName(for: conditionCharacteristicType)
        return "If \(devName) \(charName) \(comparisonType.displayName) \(comparisonValue)".trimmingCharacters(in: .whitespaces)
    }
}

private extension RepeatDraft {
    func autoName() -> String {
        return "Repeat \(count)×"
    }
}

private extension RepeatWhileDraft {
    func autoName(devices: [DeviceModel]) -> String {
        guard !conditionDeviceId.isEmpty else { return "Repeat While" }
        let device = devices.first(where: { $0.id == conditionDeviceId })
        let devName = device?.name ?? "Unknown"
        let charName = conditionCharacteristicType.isEmpty ? "" : CharacteristicTypes.displayName(for: conditionCharacteristicType)
        return "While \(devName) \(charName) \(comparisonType.displayName) \(comparisonValue)".trimmingCharacters(in: .whitespaces)
    }
}

private extension GroupDraft {
    func autoName() -> String {
        return label.isEmpty ? "Group" : label
    }
}

private extension StopDraft {
    func autoName() -> String {
        let label = switch outcome {
        case .success: "Stop (Success)"
        case .error: "Stop (Error)"
        case .cancelled: "Stop (Cancelled)"
        }
        return message.isEmpty ? label : "\(label): \(message)"
    }
}

private extension ExecuteWorkflowDraft {
    func autoName() -> String {
        let modeStr = switch executionMode {
        case .inline: "Inline"
        case .parallel: "Parallel"
        case .delegate: "Delegate"
        }
        return "Execute Workflow (\(modeStr))"
    }
}

// MARK: - Condition Draft

struct ConditionDraft: Identifiable {
    let id: UUID
    var name: String = ""
    var deviceId: String
    var serviceId: String?
    var characteristicType: String
    var comparisonType: ComparisonType
    var comparisonValue: String

    static func empty() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            name: "",
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

    static func newStop() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .stop(StopDraft()))
    }

    static func newExecuteWorkflow() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .executeWorkflow(ExecuteWorkflowDraft()))
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
    case stop(StopDraft)
    case executeWorkflow(ExecuteWorkflowDraft)

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
        case .stop: return "Stop"
        case .executeWorkflow: return "Execute Workflow"
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
        case .stop: return "stop.circle.fill"
        case .executeWorkflow: return "arrow.triangle.turn.up.right.diamond.fill"
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

struct StopDraft {
    var name: String = ""
    var outcome: StopOutcome = .success
    var message: String = ""
}

struct ExecuteWorkflowDraft {
    var name: String = ""
    var targetWorkflowId: UUID?
    var executionMode: ExecutionMode = .inline
}

// MARK: - Deep Copy

extension BlockDraft {
    /// Creates a deep copy with new UUIDs for this block and all nested blocks.
    func deepCopy() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: blockType.deepCopy())
    }
}

extension BlockDraftType {
    func deepCopy() -> BlockDraftType {
        switch self {
        case .controlDevice, .webhook, .log, .delay, .waitForState, .stop, .executeWorkflow:
            return self // value types with no nested blocks
        case .conditional(var d):
            d.thenBlocks = d.thenBlocks.map { $0.deepCopy() }
            d.elseBlocks = d.elseBlocks.map { $0.deepCopy() }
            return .conditional(d)
        case .repeatBlock(var d):
            d.blocks = d.blocks.map { $0.deepCopy() }
            return .repeatBlock(d)
        case .repeatWhile(var d):
            d.blocks = d.blocks.map { $0.deepCopy() }
            return .repeatWhile(d)
        case .group(var d):
            d.blocks = d.blocks.map { $0.deepCopy() }
            return .group(d)
        }
    }
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
            switch trigger.triggerType {
            case .deviceStateChange:
                if trigger.deviceId.isEmpty {
                    errors.append("Trigger \(i + 1): select a device")
                }
                if trigger.characteristicType.isEmpty {
                    errors.append("Trigger \(i + 1): select a characteristic")
                }
            case .schedule:
                if trigger.scheduleType == .weekly && trigger.scheduleDays.isEmpty {
                    errors.append("Trigger \(i + 1): select at least one day")
                }
            case .webhook:
                break // Token is auto-generated
            case .workflow:
                break // No configuration needed
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
        id = workflow.id
        name = workflow.name
        description = workflow.description ?? ""
        isEnabled = workflow.isEnabled
        continueOnError = workflow.continueOnError
        retriggerPolicy = workflow.retriggerPolicy
        triggers = workflow.triggers.compactMap { Self.convertTrigger($0) }
        conditions = (workflow.conditions ?? []).compactMap { Self.convertCondition($0) }
        blocks = workflow.blocks.map { Self.convertBlock($0) }
    }

    private static func convertTrigger(_ trigger: WorkflowTrigger) -> TriggerDraft? {
        switch trigger {
        case let .deviceStateChange(t):
            let (condType, condValue, condFrom) = convertTriggerCondition(t.condition)
            return TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .deviceStateChange,
                deviceId: t.deviceId,
                serviceId: t.serviceId,
                characteristicType: t.characteristicType,
                conditionType: condType,
                conditionValue: condValue,
                conditionFromValue: condFrom
            )
        case let .schedule(t):
            var draft = TriggerDraft(id: UUID(), name: t.name ?? "", triggerType: .schedule)
            switch t.scheduleType {
            case let .once(date):
                draft.scheduleType = .once
                draft.scheduleDate = date
            case let .daily(time):
                draft.scheduleType = .daily
                draft.scheduleHour = time.hour
                draft.scheduleMinute = time.minute
            case let .weekly(time, days):
                draft.scheduleType = .weekly
                draft.scheduleHour = time.hour
                draft.scheduleMinute = time.minute
                draft.scheduleDays = days
            case let .interval(seconds):
                draft.scheduleType = .interval
                if seconds >= 3600, seconds.truncatingRemainder(dividingBy: 3600) == 0 {
                    draft.scheduleIntervalAmount = Int(seconds / 3600)
                    draft.scheduleIntervalUnit = .hours
                } else {
                    draft.scheduleIntervalAmount = Int(seconds / 60)
                    draft.scheduleIntervalUnit = .minutes
                }
            }
            return draft
        case let .webhook(t):
            return TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .webhook,
                webhookToken: t.token
            )
        case let .workflow(t):
            return TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .workflow
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
        case let .equals(v):
            return (.equals, stringFromAny(v.value), "")
        case let .notEquals(v):
            return (.notEquals, stringFromAny(v.value), "")
        case let .transitioned(from, to):
            return (.transitioned, stringFromAny(to.value), from.map { stringFromAny($0.value) } ?? "")
        case let .greaterThan(v):
            return (.greaterThan, String(v), "")
        case let .lessThan(v):
            return (.lessThan, String(v), "")
        case let .greaterThanOrEqual(v):
            return (.greaterThanOrEqual, String(v), "")
        case let .lessThanOrEqual(v):
            return (.lessThanOrEqual, String(v), "")
        }
    }

    private static func convertCondition(_ condition: WorkflowCondition) -> ConditionDraft? {
        switch condition {
        case let .deviceState(c):
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
        case let .equals(v): return (.equals, stringFromAny(v.value))
        case let .notEquals(v): return (.notEquals, stringFromAny(v.value))
        case let .greaterThan(v): return (.greaterThan, String(v))
        case let .lessThan(v): return (.lessThan, String(v))
        case let .greaterThanOrEqual(v): return (.greaterThanOrEqual, String(v))
        case let .lessThanOrEqual(v): return (.lessThanOrEqual, String(v))
        }
    }

    static func convertBlock(_ block: WorkflowBlock) -> BlockDraft {
        switch block {
        case let .action(action):
            return convertAction(action)
        case let .flowControl(fc):
            return convertFlowControl(fc)
        }
    }

    private static func convertAction(_ action: WorkflowAction) -> BlockDraft {
        switch action {
        case let .controlDevice(a):
            return BlockDraft(id: UUID(), blockType: .controlDevice(ControlDeviceDraft(
                name: a.name ?? "",
                deviceId: a.deviceId,
                serviceId: a.serviceId,
                characteristicType: a.characteristicType,
                value: stringFromAny(a.value.value)
            )))
        case let .webhook(a):
            return BlockDraft(id: UUID(), blockType: .webhook(WebhookDraft(
                name: a.name ?? "",
                url: a.url,
                method: a.method,
                body: a.body.map { stringFromAny($0.value) } ?? ""
            )))
        case let .log(a):
            return BlockDraft(id: UUID(), blockType: .log(LogDraft(name: a.name ?? "", message: a.message)))
        }
    }

    private static func convertFlowControl(_ fc: FlowControlBlock) -> BlockDraft {
        switch fc {
        case let .delay(b):
            return BlockDraft(id: UUID(), blockType: .delay(DelayDraft(name: b.name ?? "", seconds: b.seconds)))
        case let .waitForState(b):
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
        case let .conditional(b):
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
        case let .repeat(b):
            return BlockDraft(id: UUID(), blockType: .repeatBlock(RepeatDraft(
                name: b.name ?? "",
                count: b.count,
                delayBetweenSeconds: b.delayBetweenSeconds ?? 0,
                blocks: b.blocks.map { convertBlock($0) }
            )))
        case let .repeatWhile(b):
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
        case let .group(b):
            return BlockDraft(id: UUID(), blockType: .group(GroupDraft(
                name: b.name ?? "",
                label: b.label ?? "",
                blocks: b.blocks.map { convertBlock($0) }
            )))
        case let .stop(b):
            return BlockDraft(id: UUID(), blockType: .stop(StopDraft(
                name: b.name ?? "",
                outcome: b.outcome,
                message: b.message ?? ""
            )))
        case let .executeWorkflow(b):
            return BlockDraft(id: UUID(), blockType: .executeWorkflow(ExecuteWorkflowDraft(
                name: b.name ?? "",
                targetWorkflowId: b.targetWorkflowId,
                executionMode: b.executionMode
            )))
        }
    }

    private static func extractDeviceCondition(_ condition: WorkflowCondition) -> (String, String?, String, ComparisonType, String) {
        switch condition {
        case let .deviceState(c):
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
            retriggerPolicy: retriggerPolicy,
            metadata: existingMetadata ?? .empty,
            createdAt: createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}

extension TriggerDraft {
    func toTrigger() -> WorkflowTrigger {
        switch triggerType {
        case .deviceStateChange:
            return .deviceStateChange(DeviceStateTrigger(
                deviceId: deviceId,
                serviceId: serviceId,
                characteristicType: characteristicType,
                condition: toTriggerCondition(),
                name: name.isEmpty ? nil : name
            ))
        case .schedule:
            return .schedule(ScheduleTrigger(
                scheduleType: toScheduleType(),
                name: name.isEmpty ? nil : name
            ))
        case .webhook:
            return .webhook(WebhookTrigger(
                token: webhookToken,
                name: name.isEmpty ? nil : name
            ))
        case .workflow:
            return .workflow(WorkflowCallTrigger(
                name: name.isEmpty ? nil : name
            ))
        }
    }

    private func toScheduleType() -> ScheduleType {
        switch scheduleType {
        case .once:
            return .once(date: scheduleDate)
        case .daily:
            return .daily(time: ScheduleTime(hour: scheduleHour, minute: scheduleMinute))
        case .weekly:
            return .weekly(
                time: ScheduleTime(hour: scheduleHour, minute: scheduleMinute),
                days: scheduleDays
            )
        case .interval:
            let seconds = switch scheduleIntervalUnit {
            case .minutes: TimeInterval(scheduleIntervalAmount * 60)
            case .hours: TimeInterval(scheduleIntervalAmount * 3600)
            }
            return .interval(seconds: seconds)
        }
    }

    private func toTriggerCondition() -> TriggerCondition {
        switch conditionType {
        case .changed: return .changed
        case .equals: return .equals(parseValue(conditionValue))
        case .notEquals: return .notEquals(parseValue(conditionValue))
        case .transitioned:
            let from = conditionFromValue.isEmpty ? nil : parseValue(conditionFromValue)
            return .transitioned(from: from, to: parseValue(conditionValue))
        case .greaterThan: return .greaterThan(Double(conditionValue) ?? 0)
        case .lessThan: return .lessThan(Double(conditionValue) ?? 0)
        case .greaterThanOrEqual: return .greaterThanOrEqual(Double(conditionValue) ?? 0)
        case .lessThanOrEqual: return .lessThanOrEqual(Double(conditionValue) ?? 0)
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
        case let .controlDevice(d):
            return .action(.controlDevice(ControlDeviceAction(
                deviceId: d.deviceId,
                serviceId: d.serviceId,
                characteristicType: d.characteristicType,
                value: parseValue(d.value),
                name: d.name.isEmpty ? nil : d.name
            )))
        case let .webhook(d):
            return .action(.webhook(WebhookActionConfig(
                url: d.url,
                method: d.method,
                headers: nil,
                body: d.body.isEmpty ? nil : AnyCodable(d.body),
                name: d.name.isEmpty ? nil : d.name
            )))
        case let .log(d):
            return .action(.log(LogAction(message: d.message, name: d.name.isEmpty ? nil : d.name)))
        case let .delay(d):
            return .flowControl(.delay(DelayBlock(seconds: d.seconds, name: d.name.isEmpty ? nil : d.name)))
        case let .waitForState(d):
            return .flowControl(.waitForState(WaitForStateBlock(
                deviceId: d.deviceId,
                serviceId: d.serviceId,
                characteristicType: d.characteristicType,
                condition: d.comparisonType.toOperator(value: d.comparisonValue),
                timeoutSeconds: d.timeoutSeconds,
                name: d.name.isEmpty ? nil : d.name
            )))
        case let .conditional(d):
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
        case let .repeatBlock(d):
            return .flowControl(.repeat(RepeatBlock(
                count: d.count,
                blocks: d.blocks.map { $0.toBlock() },
                delayBetweenSeconds: d.delayBetweenSeconds > 0 ? d.delayBetweenSeconds : nil,
                name: d.name.isEmpty ? nil : d.name
            )))
        case let .repeatWhile(d):
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
        case let .group(d):
            return .flowControl(.group(GroupBlock(
                label: d.label.isEmpty ? nil : d.label,
                blocks: d.blocks.map { $0.toBlock() },
                name: d.name.isEmpty ? nil : d.name
            )))
        case let .stop(d):
            return .flowControl(.stop(StopBlock(
                outcome: d.outcome,
                message: d.message.isEmpty ? nil : d.message,
                name: d.name.isEmpty ? nil : d.name
            )))
        case let .executeWorkflow(d):
            return .flowControl(.executeWorkflow(ExecuteWorkflowBlock(
                targetWorkflowId: d.targetWorkflowId ?? UUID(),
                executionMode: d.executionMode,
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
