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

    var symbol: String {
        switch self {
        case .changed: return "Changed"
        case .equals: return "="
        case .notEquals: return "≠"
        case .transitioned: return "Transitioned"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .greaterThanOrEqual: return "≥"
        case .lessThanOrEqual: return "≤"
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
    case isEmpty
    case isNotEmpty
    case contains

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
        case .isEmpty: return "Is Empty"
        case .isNotEmpty: return "Is Not Empty"
        case .contains: return "Contains"
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
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .contains: return "contains"
        }
    }

    /// Whether this comparison requires a value input from the user.
    var requiresValue: Bool {
        switch self {
        case .isEmpty, .isNotEmpty: return false
        default: return true
        }
    }

    /// Context-aware display name for a given variable type.
    func displayName(for type: StateVariableType?) -> String {
        guard type == .datetime else { return displayName }
        switch self {
        case .equals: return "Equals"
        case .notEquals: return "Not Equals"
        case .greaterThan: return "After"
        case .lessThan: return "Before"
        case .greaterThanOrEqual: return "At or After"
        case .lessThanOrEqual: return "At or Before"
        default: return displayName
        }
    }
}

enum TriggerDraftType: String, CaseIterable, Identifiable {
    case deviceStateChange
    case schedule
    case webhook
    case automation
    case sunEvent

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .deviceStateChange: return "Device State Change"
        case .schedule: return "Schedule"
        case .webhook: return "Webhook"
        case .automation: return "Automation"
        case .sunEvent: return "Sunrise/Sunset"
        }
    }

    var icon: String {
        switch self {
        case .deviceStateChange: return "bolt.fill"
        case .schedule: return "clock.fill"
        case .webhook: return "arrow.down.circle.fill"
        case .automation: return "arrow.triangle.turn.up.right.diamond"
        case .sunEvent: return "sunrise.fill"
        }
    }
}

// MARK: - LogicOperator UI Extensions

extension LogicOperator: CaseIterable, Identifiable {
    static var allCases: [LogicOperator] { [.and, .or] }
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .and: return "AND"
        case .or: return "OR"
        }
    }

    var symbol: String {
        switch self {
        case .and: return "&&"
        case .or: return "||"
        }
    }
}

// MARK: - Condition Group Draft (for compound conditions)

enum ConditionNodeDraft: Identifiable {
    case leaf(ConditionDraft)
    case group(ConditionGroupDraft)

    var id: UUID {
        switch self {
        case .leaf(let d): return d.id
        case .group(let d): return d.id
        }
    }
}

struct ConditionGroupDraft: Identifiable {
    let id: UUID
    var logicOperator: LogicOperator = .and
    var isNegated: Bool = false
    var children: [ConditionNodeDraft] = []

    static func empty(operator op: LogicOperator = .and) -> ConditionGroupDraft {
        ConditionGroupDraft(id: UUID(), logicOperator: op, isNegated: false, children: [])
    }

    /// Creates a group pre-populated with one empty device-state leaf condition.
    static func withOneLeaf(operator op: LogicOperator = .and) -> ConditionGroupDraft {
        ConditionGroupDraft(id: UUID(), logicOperator: op, isNegated: false, children: [.leaf(.empty())])
    }

    var leafCount: Int {
        children.reduce(0) { count, node in
            switch node {
            case .leaf: return count + 1
            case .group(let g): return count + g.leafCount
            }
        }
    }
}

// MARK: - Top-Level Automation Draft

struct AutomationDraft {
    var id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var continueOnError: Bool
    var retriggerPolicy: ConcurrentExecutionPolicy
    var triggers: [TriggerDraft]
    var conditionRoot: ConditionGroupDraft
    var blocks: [BlockDraft]

    static func empty() -> AutomationDraft {
        AutomationDraft(
            id: UUID(),
            name: "",
            description: "",
            isEnabled: true,
            continueOnError: false,
            retriggerPolicy: .ignoreNew,
            triggers: [],
            conditionRoot: .empty(),
            blocks: []
        )
    }
}

// MARK: - Trigger Draft

struct TriggerDraft: Identifiable {
    let id: UUID
    var name: String = ""
    var triggerType: TriggerDraftType = .deviceStateChange
    var retriggerPolicy: ConcurrentExecutionPolicy = .ignoreNew

    // Device state change fields
    var deviceId: String = ""
    var serviceId: String?
    var characteristicId: String = ""
    var conditionType: TriggerConditionType = .changed
    var conditionValue: String = ""
    var conditionFromValue: String = ""

    // Cached characteristic metadata for UI rendering when device isn't available
    var characteristicFormat: String?
    var characteristicMinValue: Double?
    var characteristicMaxValue: Double?
    var characteristicStepValue: Double?
    var characteristicValidValues: [Int]?

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

    /// Sun event fields
    var sunEventType: SunEventType = .sunrise
    var sunEventOffsetMinutes: Int = 0

    /// Per-trigger guard conditions
    var conditionRoot: ConditionGroupDraft = .empty()

    static func empty() -> TriggerDraft {
        TriggerDraft(id: UUID())
    }

    static func emptySchedule() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .schedule)
    }

    static func emptyWebhook() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .webhook)
    }

    static func emptyAutomation() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .automation)
    }

    static func emptySunEvent() -> TriggerDraft {
        TriggerDraft(id: UUID(), triggerType: .sunEvent)
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
            let devName = device?.nameIncludingService(serviceId: serviceId) ?? "Unknown"
            let charName = characteristicId.isEmpty ? "" : devices.resolvedCharacteristicName(deviceId: deviceId, characteristicId: characteristicId)
            let resolvedCharType = devices.resolvedCharacteristicType(deviceId: deviceId, characteristicId: characteristicId)
            let condDesc: String = {
                if conditionType == .changed { return "Changed" }
                let displayVal = CharacteristicInputConfig.displayValueForName(characteristicType: resolvedCharType, rawValue: conditionValue)
                return "\(conditionType.symbol) \(displayVal)"
            }()
            let parts = [room, devName, charName, condDesc].filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        case .schedule:
            return scheduleAutoName
        case .webhook:
            return "Webhook Trigger"
        case .automation:
            return "Automation Trigger"
        case .sunEvent:
            return sunEventAutoName
        }
    }

    private var sunEventAutoName: String {
        let eventName = sunEventType.displayName
        if sunEventOffsetMinutes == 0 {
            return "At \(eventName)"
        } else if sunEventOffsetMinutes > 0 {
            return "\(sunEventOffsetMinutes)min after \(eventName)"
        } else {
            return "\(abs(sunEventOffsetMinutes))min before \(eventName)"
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
    func autoName(devices: [DeviceModel], scenes: [SceneModel] = [], allBlocks: [BlockDraft] = [], blockOrdinals: [UUID: Int] = [:], controllerStates: [StateVariable] = []) -> String {
        switch conditionDraftType {
        case .deviceState:
            guard !deviceId.isEmpty else { return "New Condition" }
            let device = devices.first(where: { $0.id == deviceId })
            let room = device?.roomName ?? ""
            let devName = device?.nameIncludingService(serviceId: serviceId) ?? "Unknown"
            let charName = characteristicId.isEmpty ? "" : devices.resolvedCharacteristicName(deviceId: deviceId, characteristicId: characteristicId)
            let resolvedCharType = devices.resolvedCharacteristicType(deviceId: deviceId, characteristicId: characteristicId)
            let displayVal = CharacteristicInputConfig.displayValueForName(characteristicType: resolvedCharType, rawValue: comparisonValue)
            let comp = "\(comparisonType.symbol) \(displayVal)"
            let parts = [room, devName, charName, comp].filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        case .timeCondition:
            if timeConditionMode == .timeRange {
                return "\(timeRangeStart.formatted)–\(timeRangeEnd.formatted)"
            }
            return timeConditionMode.displayName
        case .sceneActive:
            guard !sceneId.isEmpty else { return "Scene Active" }
            let scene = scenes.first(where: { $0.id == sceneId })
            let sceneName = scene?.name ?? sceneId
            return sceneIsActive ? "Scene \"\(sceneName)\" active" : "Scene \"\(sceneName)\" not active"
        case .engineState:
            let varLabel = stateVariableName.isEmpty
                ? "unknown"
                : (controllerStates.first(where: { $0.name == stateVariableName })?.label ?? stateVariableName)
            let displayVal = Self.formatDisplayValue(comparisonValue)
            // Use semantic labels for datetime conditions
            if StateVariable.isDatetimeSentinel(comparisonValue) || datetimeCompareMode != .specific {
                let verb = comparisonType.displayName(for: .datetime).lowercased()
                return "'\(varLabel)' \(verb) \(displayVal)"
            }
            return "'\(varLabel)' \(comparisonType.symbol) \(displayVal)"
        case .blockResult:
            let statusName = blockResultExpectedStatus.displayName
            switch blockResultScope {
            case .specific:
                if let blockId = blockResultBlockId,
                   let block = allBlocks.first(where: { $0.id == blockId }) {
                    let ordPrefix = blockOrdinals[blockId].map { "#\($0) " } ?? ""
                    let blockName = block.displayName(devices: devices, scenes: scenes)
                    return "\(ordPrefix)\"\(blockName)\" is \(statusName)"
                }
                return "Block is \(statusName)"
            case .all:
                return "All blocks \(statusName)"
            case .any:
                return "Any block \(statusName)"
            }
        }
    }

    /// Formats a comparison value for human-readable display.
    /// Handles "__now__" and ISO 8601 datetime strings.
    static func formatDisplayValue(_ value: String) -> String {
        if let desc = StateVariable.describeSentinel(value) { return desc }
        if let date = StateVariable.parseDate(value) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return value
    }
}

extension ConditionGroupDraft {
    func autoDescription(devices: [DeviceModel], scenes: [SceneModel] = [], controllerStates: [StateVariable] = []) -> String {
        let parts: [String] = children.compactMap { node in
            switch node {
            case .leaf(let draft):
                return draft.autoName(devices: devices, scenes: scenes, controllerStates: controllerStates)
            case .group(let subGroup):
                let sub = subGroup.autoDescription(devices: devices, scenes: scenes, controllerStates: controllerStates)
                return sub.isEmpty ? nil : "(\(sub))"
            }
        }
        guard !parts.isEmpty else { return "" }
        let joined = parts.joined(separator: " \(logicOperator.displayName) ")
        return isNegated ? "NOT (\(joined))" : joined
    }
}

extension BlockDraft {
    func autoName(devices: [DeviceModel], scenes: [SceneModel] = [], controllerStates: [StateVariable] = []) -> String {
        let stateLabel: (String) -> String = { name in
            controllerStates.first(where: { $0.name == name })?.label ?? name
        }
        switch blockType {
        case let .controlDevice(d):
            return d.autoName(devices: devices, stateLabel: stateLabel)
        case let .webhook(d):
            return d.autoName()
        case let .log(d):
            return d.autoName()
        case let .runScene(d):
            return d.autoName(scenes: scenes)
        case let .stateVariable(d):
            return d.autoName(stateLabel: stateLabel)
        case let .delay(d):
            return d.autoName(stateLabel: stateLabel)
        case let .waitForState(d):
            return d.autoName(devices: devices, scenes: scenes)
        case let .conditional(d):
            return d.autoName(devices: devices, scenes: scenes)
        case let .repeatBlock(d):
            return d.autoName()
        case let .repeatWhile(d):
            return d.autoName(devices: devices, scenes: scenes)
        case let .group(d):
            return d.autoName()
        case let .stop(d):
            return d.autoName()
        case let .executeAutomation(d):
            return d.autoName()
        }
    }

    /// Returns the user-set name or the auto-generated name
    func displayName(devices: [DeviceModel], scenes: [SceneModel] = [], controllerStates: [StateVariable] = []) -> String {
        let explicitName: String = {
            switch blockType {
            case let .controlDevice(d): return d.name
            case let .webhook(d): return d.name
            case let .log(d): return d.name
            case let .runScene(d): return d.name
            case let .stateVariable(d): return d.name
            case let .delay(d): return d.name
            case let .waitForState(d): return d.name
            case let .conditional(d): return d.name
            case let .repeatBlock(d): return d.name
            case let .repeatWhile(d): return d.name
            case let .group(d): return d.name
            case let .stop(d): return d.name
            case let .executeAutomation(d): return d.name
            }
        }()
        return explicitName.isEmpty ? autoName(devices: devices, scenes: scenes, controllerStates: controllerStates) : explicitName
    }
}

private extension ControlDeviceDraft {
    func autoName(devices: [DeviceModel], stateLabel: (String) -> String = { $0 }) -> String {
        guard !deviceId.isEmpty else { return "Control Device" }
        let devName = devices.resolvedName(deviceId: deviceId, serviceId: serviceId)
        let charName = characteristicId.isEmpty ? "" : devices.resolvedCharacteristicName(deviceId: deviceId, characteristicId: characteristicId)
        if charName.isEmpty { return "Set \(devName)" }
        if valueSource == .global && !valueRefName.isEmpty {
            return "Set \(devName) \(charName) = \(stateLabel(valueRefName)) (Global)"
        }
        let resolvedCharType = devices.resolvedCharacteristicType(deviceId: deviceId, characteristicId: characteristicId)
        let displayVal = CharacteristicInputConfig.displayValueForName(characteristicType: resolvedCharType, rawValue: value)
        let valStr = displayVal.isEmpty ? "" : "= \(displayVal)"
        return "Set \(devName) \(charName) \(valStr)".trimmingCharacters(in: .whitespaces)
    }
}

extension BlockDraft {
    /// Returns `true` when this block (or any nested child block) references a
    /// device or scene that is not present in the provided arrays.
    func hasOrphanedReference(devices: [DeviceModel], scenes: [SceneModel]) -> Bool {
        let deviceIds = Set(devices.map(\.id))
        let sceneIds = Set(scenes.map(\.id))
        return _hasOrphan(deviceIds: deviceIds, sceneIds: sceneIds)
    }

    fileprivate func _hasOrphan(deviceIds: Set<String>, sceneIds: Set<String>) -> Bool {
        switch blockType {
        case let .controlDevice(d):
            return !d.deviceId.isEmpty && !deviceIds.contains(d.deviceId)
        case let .runScene(d):
            return !d.sceneId.isEmpty && !sceneIds.contains(d.sceneId)
        case let .waitForState(d):
            return d.conditionRoot.hasOrphanedDeviceRef(deviceIds: deviceIds, sceneIds: sceneIds)
        case let .conditional(d):
            if d.conditionRoot.hasOrphanedDeviceRef(deviceIds: deviceIds, sceneIds: sceneIds) { return true }
            if d.thenBlocks.contains(where: { $0._hasOrphan(deviceIds: deviceIds, sceneIds: sceneIds) }) { return true }
            if d.elseBlocks.contains(where: { $0._hasOrphan(deviceIds: deviceIds, sceneIds: sceneIds) }) { return true }
            return false
        case let .repeatWhile(d):
            if d.conditionRoot.hasOrphanedDeviceRef(deviceIds: deviceIds, sceneIds: sceneIds) { return true }
            return d.blocks.contains { $0._hasOrphan(deviceIds: deviceIds, sceneIds: sceneIds) }
        case let .repeatBlock(d):
            return d.blocks.contains { $0._hasOrphan(deviceIds: deviceIds, sceneIds: sceneIds) }
        case let .group(d):
            return d.blocks.contains { $0._hasOrphan(deviceIds: deviceIds, sceneIds: sceneIds) }
        case .webhook, .log, .stateVariable, .delay, .stop, .executeAutomation:
            return false
        }
    }
}

extension ConditionGroupDraft {
    /// Returns `true` when any leaf condition in this group references an unknown device or scene.
    func hasOrphanedDeviceRef(deviceIds: Set<String>, sceneIds: Set<String>) -> Bool {
        for child in children {
            switch child {
            case let .leaf(c):
                switch c.conditionDraftType {
                case .deviceState:
                    if !c.deviceId.isEmpty && !deviceIds.contains(c.deviceId) { return true }
                case .sceneActive:
                    if !c.sceneId.isEmpty && !sceneIds.contains(c.sceneId) { return true }
                case .timeCondition, .blockResult, .engineState:
                    break
                }
            case let .group(g):
                if g.hasOrphanedDeviceRef(deviceIds: deviceIds, sceneIds: sceneIds) { return true }
            }
        }
        return false
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

private extension RunSceneDraft {
    func autoName(scenes: [SceneModel] = []) -> String {
        guard !sceneId.isEmpty else { return "Run Scene" }
        let scene = scenes.first(where: { $0.id == sceneId })
        return "Run \"\(scene?.name ?? sceneId)\""
    }
}

private extension DelayDraft {
    func autoName(stateLabel: (String) -> String = { $0 }) -> String {
        if valueSource == .global && !secondsRefName.isEmpty {
            return "Delay \(stateLabel(secondsRefName)) (Global)"
        }
        return "Delay \(seconds)s"
    }
}

private extension WaitForStateDraft {
    func autoName(devices: [DeviceModel], scenes: [SceneModel] = []) -> String {
        let desc = conditionRoot.autoDescription(devices: devices, scenes: scenes)
        return desc.isEmpty ? "Wait for State" : "Wait \(desc)"
    }
}

private extension ConditionalDraft {
    func autoName(devices: [DeviceModel], scenes: [SceneModel] = []) -> String {
        let desc = conditionRoot.autoDescription(devices: devices, scenes: scenes)
        return desc.isEmpty ? "If/Else" : "If \(desc)"
    }
}

private extension RepeatDraft {
    func autoName() -> String {
        return "Repeat \(count)×"
    }
}

private extension RepeatWhileDraft {
    func autoName(devices: [DeviceModel], scenes: [SceneModel] = []) -> String {
        let desc = conditionRoot.autoDescription(devices: devices, scenes: scenes)
        return desc.isEmpty ? "Repeat While" : "While \(desc)"
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
        case .success: "Return (Success)"
        case .error: "Return (Error)"
        case .cancelled: "Return (Cancelled)"
        }
        return message.isEmpty ? label : "\(label): \(message)"
    }
}

private extension ExecuteAutomationDraft {
    func autoName() -> String {
        let modeStr = switch executionMode {
        case .inline: "Inline"
        case .parallel: "Parallel"
        case .delegate: "Delegate"
        }
        return "Execute Automation (\(modeStr))"
    }
}

// MARK: - Condition Draft

enum ConditionDraftType: String, CaseIterable, Identifiable {
    case deviceState
    case timeCondition
    case sceneActive
    case blockResult
    case engineState

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deviceState: return "Device State"
        case .timeCondition: return "Time Condition"
        case .sceneActive: return "Scene Active"
        case .blockResult: return "Block Result"
        case .engineState: return "Global Value"
        }
    }

    var icon: String {
        switch self {
        case .deviceState: return "shield.fill"
        case .timeCondition: return "clock.fill"
        case .sceneActive: return "play.rectangle.fill"
        case .blockResult: return "checkmark.rectangle.stack"
        case .engineState: return "cylinder.split.1x2"
        }
    }
}

enum BlockResultScopeDraft: String, CaseIterable, Identifiable {
    case specific
    case all
    case any

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .specific: return "Specific Block"
        case .all: return "All Blocks"
        case .any: return "Any Block"
        }
    }
}

struct ConditionDraft: Identifiable {
    let id: UUID
    var name: String = ""
    var conditionDraftType: ConditionDraftType = .deviceState

    // Device State fields
    var deviceId: String
    var serviceId: String?
    var characteristicId: String
    var comparisonType: ComparisonType
    var comparisonValue: String

    // Cached characteristic metadata for UI rendering when device isn't available
    var characteristicFormat: String?
    var characteristicMinValue: Double?
    var characteristicMaxValue: Double?
    var characteristicStepValue: Double?
    var characteristicValidValues: [Int]?

    // Time Condition fields
    var timeConditionMode: TimeConditionMode = .afterSunset
    var timeRangeStart: TimePoint = .fixed(TimeOfDay(hour: 22, minute: 0))
    var timeRangeEnd: TimePoint = .fixed(TimeOfDay(hour: 6, minute: 0))

    // Scene Active fields
    var sceneId: String = ""
    var sceneIsActive: Bool = true

    // Block Result fields
    var blockResultScope: BlockResultScopeDraft = .all
    var blockResultBlockId: UUID? = nil
    var blockResultExpectedStatus: ExecutionStatus = .success

    // Engine State fields
    var stateVariableName: String = ""
    var stateVariableId: String = ""
    var stateCompareToVariableName: String = ""
    var stateCompareMode: StateCompareMode = .literal
    // Datetime comparison fields
    var datetimeCompareMode: DatetimeCompareMode = .now
    var datetimeRelativeAmount: Double = 24
    var datetimeRelativeUnit: StateVariableOperation.TimeUnit = .hours
    var datetimeRelativeDirection: DatetimeRelativeDirection = .ago

    enum StateCompareMode: String, CaseIterable, Identifiable {
        case literal
        case stateRef
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .literal: return "Value"
            case .stateRef: return "State Variable"
            }
        }
    }

    enum DatetimeCompareMode: String, CaseIterable, Identifiable {
        case now
        case relative
        case specific
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .now: return "Now"
            case .relative: return "Relative to now"
            case .specific: return "Specific date"
            }
        }
    }

    enum DatetimeRelativeDirection: String, CaseIterable, Identifiable {
        case ago
        case fromNow
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .ago: return "ago"
            case .fromNow: return "from now"
            }
        }
    }

    static func empty() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            name: "",
            conditionDraftType: .deviceState,
            deviceId: "",
            serviceId: nil,
            characteristicId: "",
            comparisonType: .equals,
            comparisonValue: ""
        )
    }

    static func emptyTimeCondition() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            name: "",
            conditionDraftType: .timeCondition,
            deviceId: "",
            serviceId: nil,
            characteristicId: "",
            comparisonType: .equals,
            comparisonValue: ""
        )
    }

    static func emptySceneActive() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            name: "",
            conditionDraftType: .sceneActive,
            deviceId: "",
            serviceId: nil,
            characteristicId: "",
            comparisonType: .equals,
            comparisonValue: ""
        )
    }

    static func emptyBlockResult() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            name: "",
            conditionDraftType: .blockResult,
            deviceId: "",
            serviceId: nil,
            characteristicId: "",
            comparisonType: .equals,
            comparisonValue: ""
        )
    }

    static func emptyEngineState() -> ConditionDraft {
        ConditionDraft(
            id: UUID(),
            name: "",
            conditionDraftType: .engineState,
            deviceId: "",
            serviceId: nil,
            characteristicId: "",
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

    static func newRunScene() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .runScene(RunSceneDraft()))
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

    static func newExecuteAutomation() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .executeAutomation(ExecuteAutomationDraft()))
    }

    static func newStateVariable() -> BlockDraft {
        BlockDraft(id: UUID(), blockType: .stateVariable(StateVariableDraft()))
    }
}

enum BlockDraftType {
    case controlDevice(ControlDeviceDraft)
    case webhook(WebhookDraft)
    case log(LogDraft)
    case runScene(RunSceneDraft)
    case stateVariable(StateVariableDraft)
    case delay(DelayDraft)
    case waitForState(WaitForStateDraft)
    case conditional(ConditionalDraft)
    case repeatBlock(RepeatDraft)
    case repeatWhile(RepeatWhileDraft)
    case group(GroupDraft)
    case stop(StopDraft)
    case executeAutomation(ExecuteAutomationDraft)

    var displayName: String {
        switch self {
        case .controlDevice: return "Control Device"
        case .webhook: return "Webhook"
        case .log: return "Log Message"
        case .runScene: return "Run Scene"
        case .stateVariable: return "Global Value"
        case .delay: return "Delay"
        case .waitForState: return "Wait for State"
        case .conditional: return "If/Else"
        case .repeatBlock: return "Repeat"
        case .repeatWhile: return "Repeat While"
        case .group: return "Group"
        case .stop: return "Return"
        case .executeAutomation: return "Execute Automation"
        }
    }

    var icon: String {
        switch self {
        case .controlDevice: return "house.fill"
        case .webhook: return "globe"
        case .log: return "text.bubble"
        case .runScene: return "play.rectangle.fill"
        case .stateVariable: return "cylinder.split.1x2"
        case .delay: return "clock"
        case .waitForState: return "hourglass"
        case .conditional: return "arrow.triangle.branch"
        case .repeatBlock: return "repeat"
        case .repeatWhile: return "repeat.circle"
        case .group: return "folder"
        case .stop: return "arrow.uturn.backward.circle.fill"
        case .executeAutomation: return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }

    var isFlowControl: Bool {
        switch self {
        case .controlDevice, .webhook, .log, .runScene, .stateVariable: return false
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
    var characteristicId: String = ""
    var value: String = ""

    /// Whether the value comes from a local (hardcoded) or global (Global Value reference) source.
    var valueSource: ValueSource = .local
    /// Name of the referenced Global Value (only used when valueSource == .global).
    var valueRefName: String = ""
    /// Display name of the referenced Global Value (for human-readable auto-names).
    var valueRefDisplayName: String = ""

    enum ValueSource: String {
        case local       // hardcoded in workflow
        case global      // from a Global Value
    }

    // Cached characteristic metadata for UI rendering when device isn't available
    var characteristicFormat: String?
    var characteristicMinValue: Double?
    var characteristicMaxValue: Double?
    var characteristicStepValue: Double?
    var characteristicValidValues: [Int]?
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

struct RunSceneDraft {
    var name: String = ""
    var sceneId: String = ""
}

// MARK: - State Variable Draft

enum StateVariableOperationType: String, CaseIterable, Identifiable {
    case create, remove, set, setFromCharacteristic
    case increment, decrement, multiply, addState, subtractState
    case toggle, andState, orState, notState
    case setToNow, addTime, subtractTime

    var id: String { rawValue }

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

    /// The variable types this operation applies to. Empty means applicable to all types.
    var applicableTypes: [StateVariableType] {
        switch self {
        case .create, .remove, .set, .setFromCharacteristic: return []
        case .increment, .decrement, .multiply, .addState, .subtractState: return [.number]
        case .toggle, .andState, .orState, .notState: return [.boolean]
        case .setToNow, .addTime, .subtractTime: return [.datetime]
        }
    }

    /// Whether this operation requires a secondary state variable reference.
    var requiresOtherRef: Bool {
        switch self {
        case .addState, .subtractState, .andState, .orState: return true
        default: return false
        }
    }

    /// Whether this operation requires a numeric amount.
    var requiresAmount: Bool {
        switch self {
        case .increment, .decrement, .multiply: return true
        default: return false
        }
    }

    /// Whether this operation requires device/characteristic selection.
    var requiresDevice: Bool {
        switch self {
        case .setFromCharacteristic: return true
        default: return false
        }
    }

    /// Whether this operation requires a time amount and unit (for datetime arithmetic).
    var requiresTimeAmount: Bool {
        switch self {
        case .addTime, .subtractTime: return true
        default: return false
        }
    }

    /// Whether this operation requires a value input.
    var requiresValue: Bool {
        switch self {
        case .create, .set: return true
        default: return false
        }
    }
}

struct StateVariableDraft {
    var name: String = ""
    var operationType: StateVariableOperationType = .set
    var variableName: String = ""
    /// Display name of the selected Global Value (for human-readable auto-names).
    var variableDisplayName: String = ""
    var variableId: String = ""
    var variableType: StateVariableType = .number
    var value: String = ""
    var otherVariableName: String = ""
    var amountValue: Double = 1.0
    // datetime arithmetic fields
    var timeAmount: Double = 1.0
    var timeUnit: StateVariableOperation.TimeUnit = .minutes
    // setFromCharacteristic fields
    var sourceDeviceId: String = ""
    var sourceServiceId: String?
    var sourceCharacteristicId: String = ""

    func autoName(stateLabel: (String) -> String = { $0 }) -> String {
        let displayLabel = variableName.isEmpty ? "" : stateLabel(variableName)
        let varLabel = displayLabel.isEmpty ? "" : " '\(displayLabel)'"
        switch operationType {
        case .set:
            let displayVal = ConditionDraft.formatDisplayValue(value)
            return "Set\(varLabel) = \(displayVal)"
        case .setToNow:
            return "Set\(varLabel) to Now"
        case .addTime:
            return "Add \(formatTimeAmount(timeAmount, timeUnit)) to\(varLabel)"
        case .subtractTime:
            return "Subtract \(formatTimeAmount(timeAmount, timeUnit)) from\(varLabel)"
        case .increment:
            return "Increment\(varLabel) by \(amountValue)"
        case .decrement:
            return "Decrement\(varLabel) by \(amountValue)"
        case .multiply:
            return "Multiply\(varLabel) by \(amountValue)"
        default:
            return operationType.displayName + varLabel
        }
    }

    private func formatTimeAmount(_ amount: Double, _ unit: StateVariableOperation.TimeUnit) -> String {
        let amountStr = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(amount)
        return "\(amountStr) \(unit.displayName.lowercased())"
    }

    /// Convert from a `StateVariableAction` model to a draft.
    static func from(_ action: StateVariableAction) -> StateVariableDraft {
        var draft = StateVariableDraft()
        draft.name = action.name ?? ""
        switch action.operation {
        case let .create(varName, varType, initialValue):
            draft.operationType = .create
            draft.variableName = varName
            draft.variableType = varType
            draft.value = stringFromAny(initialValue.value)
        case let .remove(ref):
            draft.operationType = .remove
            applyRef(ref, to: &draft)
        case let .set(ref, val):
            draft.operationType = .set
            applyRef(ref, to: &draft)
            draft.value = stringFromAny(val.value)
        case let .increment(ref, by):
            draft.operationType = .increment
            applyRef(ref, to: &draft)
            draft.amountValue = by
        case let .decrement(ref, by):
            draft.operationType = .decrement
            applyRef(ref, to: &draft)
            draft.amountValue = by
        case let .multiply(ref, by):
            draft.operationType = .multiply
            applyRef(ref, to: &draft)
            draft.amountValue = by
        case let .addState(ref, otherRef):
            draft.operationType = .addState
            applyRef(ref, to: &draft)
            applyOtherRef(otherRef, to: &draft)
        case let .subtractState(ref, otherRef):
            draft.operationType = .subtractState
            applyRef(ref, to: &draft)
            applyOtherRef(otherRef, to: &draft)
        case let .toggle(ref):
            draft.operationType = .toggle
            applyRef(ref, to: &draft)
        case let .andState(ref, otherRef):
            draft.operationType = .andState
            applyRef(ref, to: &draft)
            applyOtherRef(otherRef, to: &draft)
        case let .orState(ref, otherRef):
            draft.operationType = .orState
            applyRef(ref, to: &draft)
            applyOtherRef(otherRef, to: &draft)
        case let .notState(ref):
            draft.operationType = .notState
            applyRef(ref, to: &draft)
        case let .setToNow(ref):
            draft.operationType = .setToNow
            applyRef(ref, to: &draft)
        case let .addTime(ref, amount, unit):
            draft.operationType = .addTime
            applyRef(ref, to: &draft)
            draft.timeAmount = amount
            draft.timeUnit = unit
        case let .subtractTime(ref, amount, unit):
            draft.operationType = .subtractTime
            applyRef(ref, to: &draft)
            draft.timeAmount = amount
            draft.timeUnit = unit
        case let .setFromCharacteristic(ref, deviceId, characteristicId, serviceId):
            draft.operationType = .setFromCharacteristic
            applyRef(ref, to: &draft)
            draft.sourceDeviceId = deviceId
            draft.sourceCharacteristicId = characteristicId
            draft.sourceServiceId = serviceId
        }
        return draft
    }

    private static func applyRef(_ ref: StateVariableRef, to draft: inout StateVariableDraft) {
        switch ref {
        case let .byName(name): draft.variableName = name
        case let .byId(id): draft.variableId = id.uuidString
        }
    }

    private static func applyOtherRef(_ ref: StateVariableRef, to draft: inout StateVariableDraft) {
        if case let .byName(name) = ref {
            draft.otherVariableName = name
        }
    }

    /// Convert this draft back to a `StateVariableOperation` model.
    func toOperation() -> StateVariableOperation {
        let ref: StateVariableRef = variableName.isEmpty
            ? .byId(UUID(uuidString: variableId) ?? UUID())
            : .byName(variableName)
        let otherRef: StateVariableRef = .byName(otherVariableName)

        switch operationType {
        case .create:
            return .create(name: variableName, variableType: variableType, initialValue: parseValue(value))
        case .remove:
            return .remove(variableRef: ref)
        case .set:
            return .set(variableRef: ref, value: parseValue(value))
        case .increment:
            return .increment(variableRef: ref, by: amountValue)
        case .decrement:
            return .decrement(variableRef: ref, by: amountValue)
        case .multiply:
            return .multiply(variableRef: ref, by: amountValue)
        case .addState:
            return .addState(variableRef: ref, otherRef: otherRef)
        case .subtractState:
            return .subtractState(variableRef: ref, otherRef: otherRef)
        case .toggle:
            return .toggle(variableRef: ref)
        case .andState:
            return .andState(variableRef: ref, otherRef: otherRef)
        case .orState:
            return .orState(variableRef: ref, otherRef: otherRef)
        case .notState:
            return .notState(variableRef: ref)
        case .setToNow:
            return .setToNow(variableRef: ref)
        case .addTime:
            return .addTime(variableRef: ref, amount: timeAmount, unit: timeUnit)
        case .subtractTime:
            return .subtractTime(variableRef: ref, amount: timeAmount, unit: timeUnit)
        case .setFromCharacteristic:
            return .setFromCharacteristic(
                variableRef: ref,
                deviceId: sourceDeviceId,
                characteristicId: sourceCharacteristicId,
                serviceId: sourceServiceId
            )
        }
    }
}

struct DelayDraft {
    var name: String = ""
    var seconds: Double = 1.0
    var valueSource: ControlDeviceDraft.ValueSource = .local
    var secondsRefName: String = ""
}

struct WaitForStateDraft {
    var name: String = ""
    var conditionRoot: ConditionGroupDraft = .withOneLeaf()
    var timeoutSeconds: Double = 30.0
}

struct ConditionalDraft {
    var name: String = ""
    var conditionRoot: ConditionGroupDraft = .withOneLeaf()
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
    var conditionRoot: ConditionGroupDraft = .withOneLeaf()
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

struct ExecuteAutomationDraft {
    var name: String = ""
    var targetAutomationId: UUID?
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
        case .controlDevice, .webhook, .log, .runScene, .stateVariable, .delay, .waitForState, .stop, .executeAutomation:
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

struct AutomationValidation {
    let isValid: Bool
    let errors: [String]
    var warnings: [String] = []
}

extension AutomationDraft {
    func validate() -> AutomationValidation {
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
                if trigger.characteristicId.isEmpty {
                    errors.append("Trigger \(i + 1): select a characteristic")
                }
            case .schedule:
                if trigger.scheduleType == .weekly && trigger.scheduleDays.isEmpty {
                    errors.append("Trigger \(i + 1): select at least one day")
                }
            case .webhook:
                break // Token is auto-generated
            case .automation:
                break // No configuration needed
            case .sunEvent:
                break // No additional validation needed
            }
        }
        if blocks.isEmpty {
            errors.append("At least one block is required")
        }
        // Block result conditions require continueOnError
        if !continueOnError && hasBlockResultConditions() {
            errors.append("Cannot use Block Result conditions without Continue on Error enabled")
        }
        // Block result conditions must not appear in automation-level guard conditions
        if Self.conditionGroupHasBlockResult(conditionRoot) {
            errors.append("Block Result conditions cannot be used in automation-level guard conditions (no blocks have executed yet)")
        }
        // Check for orphaned block references (safety net for iCloud sync / manual editing)
        let validIds = allBlockIds()
        let orphaned = blockIdsReferencedByConditions().filter { !validIds.contains($0) }
        if !orphaned.isEmpty {
            errors.append("Block Result condition references a deleted block")
        }
        // Warn about block result conditions referencing blocks that haven't executed yet
        var warnings: [String] = []
        let ordinals = blockOrdinals()
        Self.validateBlockResultOrdering(blocks, ordinals: ordinals, warnings: &warnings)
        return AutomationValidation(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }

    // MARK: - Block Result Utilities

    /// Recursively collect all block IDs in the automation (including nested).
    func allBlockIds() -> Set<UUID> {
        var ids = Set<UUID>()
        Self.collectBlockIds(from: blocks, into: &ids)
        return ids
    }

    /// Recursively collect all blocks as a flat list (including nested) in execution order.
    func allBlockDrafts() -> [BlockDraft] {
        var result: [BlockDraft] = []
        Self.collectAllBlocks(from: blocks, into: &result)
        return result
    }

    /// Returns a mapping of block ID → 1-based ordinal in execution order.
    /// The ordinal reflects depth-first traversal order and updates automatically
    /// when blocks are reordered.
    func blockOrdinals() -> [UUID: Int] {
        let all = allBlockDrafts()
        var ordinals: [UUID: Int] = [:]
        for (i, block) in all.enumerated() {
            ordinals[block.id] = i + 1  // 1-based
        }
        return ordinals
    }

    /// Check if any condition in the automation references a block result.
    func hasBlockResultConditions() -> Bool {
        if Self.conditionGroupHasBlockResult(conditionRoot) { return true }
        return Self.blocksHaveBlockResultConditions(blocks)
    }

    /// Collect all block IDs that are specifically referenced by block result conditions.
    func blockIdsReferencedByConditions() -> Set<UUID> {
        var ids = Set<UUID>()
        Self.collectReferencedBlockIds(from: conditionRoot, into: &ids)
        Self.collectReferencedBlockIdsFromBlocks(blocks, into: &ids)
        return ids
    }

    private static func collectBlockIds(from blocks: [BlockDraft], into ids: inout Set<UUID>) {
        for block in blocks {
            ids.insert(block.id)
            switch block.blockType {
            case .conditional(let d):
                collectBlockIds(from: d.thenBlocks, into: &ids)
                collectBlockIds(from: d.elseBlocks, into: &ids)
            case .repeatBlock(let d):
                collectBlockIds(from: d.blocks, into: &ids)
            case .repeatWhile(let d):
                collectBlockIds(from: d.blocks, into: &ids)
            case .group(let d):
                collectBlockIds(from: d.blocks, into: &ids)
            default: break
            }
        }
    }

    private static func collectAllBlocks(from blocks: [BlockDraft], into result: inout [BlockDraft]) {
        for block in blocks {
            result.append(block)
            switch block.blockType {
            case .conditional(let d):
                collectAllBlocks(from: d.thenBlocks, into: &result)
                collectAllBlocks(from: d.elseBlocks, into: &result)
            case .repeatBlock(let d):
                collectAllBlocks(from: d.blocks, into: &result)
            case .repeatWhile(let d):
                collectAllBlocks(from: d.blocks, into: &result)
            case .group(let d):
                collectAllBlocks(from: d.blocks, into: &result)
            default: break
            }
        }
    }

    private static func conditionGroupHasBlockResult(_ group: ConditionGroupDraft) -> Bool {
        for child in group.children {
            switch child {
            case .leaf(let draft):
                if draft.conditionDraftType == .blockResult { return true }
            case .group(let subGroup):
                if conditionGroupHasBlockResult(subGroup) { return true }
            }
        }
        return false
    }

    private static func blocksHaveBlockResultConditions(_ blocks: [BlockDraft]) -> Bool {
        for block in blocks {
            switch block.blockType {
            case .conditional(let d):
                if conditionGroupHasBlockResult(d.conditionRoot) { return true }
                if blocksHaveBlockResultConditions(d.thenBlocks) { return true }
                if blocksHaveBlockResultConditions(d.elseBlocks) { return true }
            case .repeatWhile(let d):
                if conditionGroupHasBlockResult(d.conditionRoot) { return true }
                if blocksHaveBlockResultConditions(d.blocks) { return true }
            case .repeatBlock(let d):
                if blocksHaveBlockResultConditions(d.blocks) { return true }
            case .group(let d):
                if blocksHaveBlockResultConditions(d.blocks) { return true }
            default: break
            }
        }
        return false
    }

    private static func collectReferencedBlockIds(from group: ConditionGroupDraft, into ids: inout Set<UUID>) {
        for child in group.children {
            switch child {
            case .leaf(let draft):
                if draft.conditionDraftType == .blockResult,
                   draft.blockResultScope == .specific,
                   let blockId = draft.blockResultBlockId {
                    ids.insert(blockId)
                }
            case .group(let subGroup):
                collectReferencedBlockIds(from: subGroup, into: &ids)
            }
        }
    }

    private static func collectReferencedBlockIdsFromBlocks(_ blocks: [BlockDraft], into ids: inout Set<UUID>) {
        for block in blocks {
            switch block.blockType {
            case .conditional(let d):
                collectReferencedBlockIds(from: d.conditionRoot, into: &ids)
                collectReferencedBlockIdsFromBlocks(d.thenBlocks, into: &ids)
                collectReferencedBlockIdsFromBlocks(d.elseBlocks, into: &ids)
            case .repeatWhile(let d):
                collectReferencedBlockIds(from: d.conditionRoot, into: &ids)
                collectReferencedBlockIdsFromBlocks(d.blocks, into: &ids)
            case .repeatBlock(let d):
                collectReferencedBlockIdsFromBlocks(d.blocks, into: &ids)
            case .group(let d):
                collectReferencedBlockIdsFromBlocks(d.blocks, into: &ids)
            default: break
            }
        }
    }

    /// Walk blocks and warn when a block result condition references a block with a
    /// higher ordinal (i.e., one that hasn't executed yet at that point in the flow).
    private static func validateBlockResultOrdering(
        _ blocks: [BlockDraft],
        ordinals: [UUID: Int],
        warnings: inout [String]
    ) {
        for block in blocks {
            let blockOrd = ordinals[block.id] ?? Int.max
            switch block.blockType {
            case .conditional(let d):
                checkGroupForOrderingWarnings(d.conditionRoot, blockOrdinal: blockOrd, ordinals: ordinals, blockName: block.displayName(devices: [], scenes: []), warnings: &warnings)
                validateBlockResultOrdering(d.thenBlocks, ordinals: ordinals, warnings: &warnings)
                validateBlockResultOrdering(d.elseBlocks, ordinals: ordinals, warnings: &warnings)
            case .repeatWhile(let d):
                checkGroupForOrderingWarnings(d.conditionRoot, blockOrdinal: blockOrd, ordinals: ordinals, blockName: block.displayName(devices: [], scenes: []), warnings: &warnings)
                validateBlockResultOrdering(d.blocks, ordinals: ordinals, warnings: &warnings)
            case .repeatBlock(let d):
                validateBlockResultOrdering(d.blocks, ordinals: ordinals, warnings: &warnings)
            case .group(let d):
                validateBlockResultOrdering(d.blocks, ordinals: ordinals, warnings: &warnings)
            default:
                break
            }
        }
    }

    private static func checkGroupForOrderingWarnings(
        _ group: ConditionGroupDraft,
        blockOrdinal: Int,
        ordinals: [UUID: Int],
        blockName: String,
        warnings: inout [String]
    ) {
        for child in group.children {
            switch child {
            case .leaf(let draft):
                if draft.conditionDraftType == .blockResult,
                   draft.blockResultScope == .specific,
                   let refId = draft.blockResultBlockId {
                    let refOrd = ordinals[refId] ?? Int.max
                    if refOrd >= blockOrdinal {
                        let refLabel = ordinals[refId].map { "#\($0)" } ?? "unknown"
                        warnings.append("Block #\(blockOrdinal) \"\(blockName)\" references block \(refLabel) which may not have executed yet")
                    }
                }
            case .group(let sub):
                checkGroupForOrderingWarnings(sub, blockOrdinal: blockOrdinal, ordinals: ordinals, blockName: blockName, warnings: &warnings)
            }
        }
    }
}

// MARK: - Conversion: Automation → AutomationDraft

/// Look up characteristic metadata from a devices list for UI rendering fallback.
private func lookupCharacteristicMeta(
    deviceId: String, characteristicId: String, in devices: [DeviceModel]
) -> (format: String?, minValue: Double?, maxValue: Double?, stepValue: Double?, validValues: [Int]?) {
    guard let device = devices.first(where: { $0.id == deviceId }) else {
        return (nil, nil, nil, nil, nil)
    }
    // Match by characteristic ID (stable or HomeKit UUID depending on whether devices have been transformed)
    guard let char = device.services.flatMap(\.characteristics)
        .first(where: { $0.id == characteristicId }) else {
        return (nil, nil, nil, nil, nil)
    }
    return (char.format, char.minValue, char.maxValue, char.stepValue, char.validValues)
}

extension AutomationDraft {
    init(from automation: Automation, devices: [DeviceModel] = []) {
        id = automation.id
        name = automation.name
        description = automation.description ?? ""
        isEnabled = automation.isEnabled
        continueOnError = automation.continueOnError
        retriggerPolicy = automation.retriggerPolicy
        triggers = automation.triggers.compactMap { Self.convertTrigger($0, devices: devices) }
        conditionRoot = Self.convertConditionTree(automation.conditions ?? [], devices: devices)
        blocks = automation.blocks.map { Self.convertBlock($0, devices: devices) }
    }

    private static func convertTrigger(_ trigger: AutomationTrigger, devices: [DeviceModel] = []) -> TriggerDraft? {
        let policy = trigger.resolvedRetriggerPolicy
        let triggerCondRoot = convertConditionTree(trigger.conditions ?? [], devices: devices)
        switch trigger {
        case let .deviceStateChange(t):
            let (condType, condValue, condFrom) = convertTriggerCondition(t.matchOperator)
            let meta = lookupCharacteristicMeta(deviceId: t.deviceId, characteristicId: t.characteristicId, in: devices)
            var draft = TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .deviceStateChange,
                retriggerPolicy: policy,
                deviceId: t.deviceId,
                serviceId: t.serviceId,
                characteristicId: t.characteristicId,
                conditionType: condType,
                conditionValue: condValue,
                conditionFromValue: condFrom,
                characteristicFormat: meta.format,
                characteristicMinValue: meta.minValue,
                characteristicMaxValue: meta.maxValue,
                characteristicStepValue: meta.stepValue,
                characteristicValidValues: meta.validValues
            )
            draft.conditionRoot = triggerCondRoot
            return draft
        case let .schedule(t):
            var draft = TriggerDraft(id: UUID(), name: t.name ?? "", triggerType: .schedule, retriggerPolicy: policy)
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
            draft.conditionRoot = triggerCondRoot
            return draft
        case let .webhook(t):
            var draft = TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .webhook,
                retriggerPolicy: policy,
                webhookToken: t.token
            )
            draft.conditionRoot = triggerCondRoot
            return draft
        case let .automation(t):
            var draft = TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .automation,
                retriggerPolicy: policy
            )
            draft.conditionRoot = triggerCondRoot
            return draft
        case let .sunEvent(t):
            var draft = TriggerDraft(
                id: UUID(),
                name: t.name ?? "",
                triggerType: .sunEvent,
                retriggerPolicy: policy,
                sunEventType: t.event,
                sunEventOffsetMinutes: t.offsetMinutes
            )
            draft.conditionRoot = triggerCondRoot
            return draft
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
            return (.transitioned, to.map { stringFromAny($0.value) } ?? "", from.map { stringFromAny($0.value) } ?? "")
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

    /// Convert a flat list of `AutomationCondition` into a `ConditionGroupDraft` tree.
    /// Handles backward-compatible flat lists (implicit AND) and compound conditions.
    static func convertConditionTree(_ conditions: [AutomationCondition], devices: [DeviceModel] = []) -> ConditionGroupDraft {
        guard !conditions.isEmpty else { return .empty() }

        // If the automation stored a single compound condition, use it as the root
        if conditions.count == 1 {
            switch conditions[0] {
            case .and(let children):
                var root = ConditionGroupDraft(id: UUID(), logicOperator: .and)
                root.children = children.map { convertConditionNode($0, devices: devices) }
                return root
            case .or(let children):
                var root = ConditionGroupDraft(id: UUID(), logicOperator: .or)
                root.children = children.map { convertConditionNode($0, devices: devices) }
                return root
            case .not(let inner):
                var root = convertConditionTree([inner], devices: devices)
                root.isNegated = true
                return root
            default:
                // Single leaf condition
                var root = ConditionGroupDraft.empty()
                root.children = [convertConditionNode(conditions[0], devices: devices)]
                return root
            }
        }

        // Multiple conditions at root level = implicit AND (backward compatible)
        var root = ConditionGroupDraft(id: UUID(), logicOperator: .and)
        root.children = conditions.map { convertConditionNode($0, devices: devices) }
        return root
    }

    /// Convert a single `AutomationCondition` into a `ConditionNodeDraft`.
    static func convertConditionNode(_ condition: AutomationCondition, devices: [DeviceModel] = []) -> ConditionNodeDraft {
        switch condition {
        case let .deviceState(c):
            let (compType, compValue) = convertComparison(c.comparison)
            let meta = lookupCharacteristicMeta(deviceId: c.deviceId, characteristicId: c.characteristicId, in: devices)
            return .leaf(ConditionDraft(
                id: UUID(),
                conditionDraftType: .deviceState,
                deviceId: c.deviceId,
                serviceId: c.serviceId,
                characteristicId: c.characteristicId,
                comparisonType: compType,
                comparisonValue: compValue,
                characteristicFormat: meta.format,
                characteristicMinValue: meta.minValue,
                characteristicMaxValue: meta.maxValue,
                characteristicStepValue: meta.stepValue,
                characteristicValidValues: meta.validValues
            ))
        case let .timeCondition(c):
            return .leaf(ConditionDraft(
                id: UUID(),
                conditionDraftType: .timeCondition,
                deviceId: "",
                serviceId: nil,
                characteristicId: "",
                comparisonType: .equals,
                comparisonValue: "",
                timeConditionMode: c.mode,
                timeRangeStart: c.startTime ?? .fixed(TimeOfDay(hour: 22, minute: 0)),
                timeRangeEnd: c.endTime ?? .fixed(TimeOfDay(hour: 6, minute: 0))
            ))
        case let .sceneActive(c):
            return .leaf(ConditionDraft(
                id: UUID(),
                conditionDraftType: .sceneActive,
                deviceId: "",
                serviceId: nil,
                characteristicId: "",
                comparisonType: .equals,
                comparisonValue: "",
                sceneId: c.sceneId,
                sceneIsActive: c.isActive
            ))
        case let .blockResult(c):
            var draft = ConditionDraft(
                id: UUID(),
                conditionDraftType: .blockResult,
                deviceId: "",
                serviceId: nil,
                characteristicId: "",
                comparisonType: .equals,
                comparisonValue: ""
            )
            draft.blockResultExpectedStatus = c.expectedStatus
            switch c.scope {
            case let .specific(blockId):
                draft.blockResultScope = .specific
                draft.blockResultBlockId = blockId
            case .all:
                draft.blockResultScope = .all
            case .any:
                draft.blockResultScope = .any
            }
            return .leaf(draft)
        case let .engineState(c):
            let (compType, compValue) = convertComparison(c.comparison)
            var draft = ConditionDraft(
                id: UUID(),
                conditionDraftType: .engineState,
                deviceId: "",
                serviceId: nil,
                characteristicId: "",
                comparisonType: compType,
                comparisonValue: compValue
            )
            switch c.variableRef {
            case let .byName(name): draft.stateVariableName = name
            case let .byId(id): draft.stateVariableId = id.uuidString
            }
            if let otherRef = c.compareToStateRef {
                draft.stateCompareMode = .stateRef
                if case let .byName(name) = otherRef {
                    draft.stateCompareToVariableName = name
                }
            }
            // Restore datetime comparison mode from dynamicDateValue
            if let sentinel = c.dynamicDateValue {
                if sentinel == "__now__" {
                    draft.datetimeCompareMode = .now
                    draft.comparisonValue = "__now__"
                } else if sentinel.hasPrefix("__now") && sentinel.hasSuffix("__") {
                    draft.datetimeCompareMode = .relative
                    draft.comparisonValue = sentinel
                    // Parse the offset: e.g. "-24h" or "+7d"
                    let inner = String(sentinel.dropFirst(5).dropLast(2))
                    if let unitChar = inner.last {
                        switch unitChar {
                        case "s": draft.datetimeRelativeUnit = .seconds
                        case "m": draft.datetimeRelativeUnit = .minutes
                        case "h": draft.datetimeRelativeUnit = .hours
                        case "d": draft.datetimeRelativeUnit = .days
                        default: break
                        }
                        if let amount = Double(inner.dropLast()) {
                            draft.datetimeRelativeAmount = abs(amount)
                            draft.datetimeRelativeDirection = amount < 0 ? .ago : .fromNow
                        }
                    }
                }
            } else if StateVariable.isDatetimeSentinel(compValue) {
                // Legacy: comparisonValue itself is the sentinel
                draft.datetimeCompareMode = compValue == "__now__" ? .now : .relative
            }
            return .leaf(draft)
        case .not(let inner):
            // NOT always maps to a group with isNegated = true
            var subGroup = convertConditionTree([inner], devices: devices)
            subGroup.isNegated = true
            return .group(subGroup)
        case .and(let children):
            var group = ConditionGroupDraft(id: UUID(), logicOperator: .and)
            group.children = children.map { convertConditionNode($0, devices: devices) }
            return .group(group)
        case .or(let children):
            var group = ConditionGroupDraft(id: UUID(), logicOperator: .or)
            group.children = children.map { convertConditionNode($0, devices: devices) }
            return .group(group)
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
        case .isEmpty: return (.isEmpty, "")
        case .isNotEmpty: return (.isNotEmpty, "")
        case let .contains(v): return (.contains, v)
        }
    }

    static func convertBlock(_ block: AutomationBlock, devices: [DeviceModel] = []) -> BlockDraft {
        switch block {
        case let .action(action, blockId):
            return convertAction(action, blockId: blockId, devices: devices)
        case let .flowControl(fc, blockId):
            return convertFlowControl(fc, blockId: blockId, devices: devices)
        }
    }

    private static func convertAction(_ action: AutomationAction, blockId: UUID, devices: [DeviceModel] = []) -> BlockDraft {
        switch action {
        case let .controlDevice(a):
            let meta = lookupCharacteristicMeta(deviceId: a.deviceId, characteristicId: a.characteristicId, in: devices)
            var draft = ControlDeviceDraft(
                name: a.name ?? "",
                deviceId: a.deviceId,
                serviceId: a.serviceId,
                characteristicId: a.characteristicId,
                value: stringFromAny(a.value.value),
                characteristicFormat: meta.format,
                characteristicMinValue: meta.minValue,
                characteristicMaxValue: meta.maxValue,
                characteristicStepValue: meta.stepValue,
                characteristicValidValues: meta.validValues
            )
            if let ref = a.valueRef {
                draft.valueSource = .global
                if case let .byName(name) = ref { draft.valueRefName = name }
            }
            return BlockDraft(id: blockId, blockType: .controlDevice(draft))
        case let .webhook(a):
            return BlockDraft(id: blockId, blockType: .webhook(WebhookDraft(
                name: a.name ?? "",
                url: a.url,
                method: a.method,
                body: a.body.map { stringFromAny($0.value) } ?? ""
            )))
        case let .log(a):
            return BlockDraft(id: blockId, blockType: .log(LogDraft(name: a.name ?? "", message: a.message)))
        case let .runScene(a):
            return BlockDraft(id: blockId, blockType: .runScene(RunSceneDraft(
                name: a.name ?? "",
                sceneId: a.sceneId
            )))
        case let .stateVariable(a):
            return BlockDraft(id: blockId, blockType: .stateVariable(StateVariableDraft.from(a)))
        }
    }

    private static func convertFlowControl(_ fc: FlowControlBlock, blockId: UUID, devices: [DeviceModel] = []) -> BlockDraft {
        switch fc {
        case let .delay(b):
            var draft = DelayDraft(name: b.name ?? "", seconds: b.seconds)
            if let ref = b.secondsRef {
                draft.valueSource = .global
                if case let .byName(name) = ref { draft.secondsRefName = name }
            }
            return BlockDraft(id: blockId, blockType: .delay(draft))
        case let .waitForState(b):
            var draft = WaitForStateDraft(name: b.name ?? "")
            draft.conditionRoot = convertConditionTree([b.condition], devices: devices)
            draft.timeoutSeconds = b.timeoutSeconds
            return BlockDraft(id: blockId, blockType: .waitForState(draft))
        case let .conditional(b):
            var draft = ConditionalDraft(name: b.name ?? "")
            draft.conditionRoot = convertConditionTree([b.condition], devices: devices)
            draft.thenBlocks = b.thenBlocks.map { convertBlock($0, devices: devices) }
            draft.elseBlocks = (b.elseBlocks ?? []).map { convertBlock($0, devices: devices) }
            return BlockDraft(id: blockId, blockType: .conditional(draft))
        case let .repeat(b):
            return BlockDraft(id: blockId, blockType: .repeatBlock(RepeatDraft(
                name: b.name ?? "",
                count: b.count,
                delayBetweenSeconds: b.delayBetweenSeconds ?? 0,
                blocks: b.blocks.map { convertBlock($0, devices: devices) }
            )))
        case let .repeatWhile(b):
            var draft = RepeatWhileDraft(name: b.name ?? "")
            draft.conditionRoot = convertConditionTree([b.condition], devices: devices)
            draft.maxIterations = b.maxIterations
            draft.delayBetweenSeconds = b.delayBetweenSeconds ?? 0
            draft.blocks = b.blocks.map { convertBlock($0, devices: devices) }
            return BlockDraft(id: blockId, blockType: .repeatWhile(draft))
        case let .group(b):
            return BlockDraft(id: blockId, blockType: .group(GroupDraft(
                name: b.name ?? "",
                label: b.label ?? "",
                blocks: b.blocks.map { convertBlock($0, devices: devices) }
            )))
        case let .stop(b):
            return BlockDraft(id: blockId, blockType: .stop(StopDraft(
                name: b.name ?? "",
                outcome: b.outcome,
                message: b.message ?? ""
            )))
        case let .executeAutomation(b):
            return BlockDraft(id: blockId, blockType: .executeAutomation(ExecuteAutomationDraft(
                name: b.name ?? "",
                targetAutomationId: b.targetAutomationId,
                executionMode: b.executionMode
            )))
        }
    }

}

// MARK: - Device Lookup Helper

private func lookupDevice(_ deviceId: String, in devices: [DeviceModel]) -> (name: String?, room: String?) {
    guard !deviceId.isEmpty, let device = devices.first(where: { $0.id == deviceId }) else {
        return (nil, nil)
    }
    return (device.name, device.roomName)
}

// MARK: - Conversion: AutomationDraft → Automation

extension AutomationDraft {
    func toAutomation(devices: [DeviceModel], existingMetadata: AutomationMetadata?, createdAt: Date?) -> Automation {
        Automation(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            isEnabled: isEnabled,
            triggers: triggers.map { $0.toTrigger(devices: devices) },
            conditions: conditionRoot.toConditions(devices: devices),
            blocks: blocks.map { $0.toBlock(devices: devices) },
            continueOnError: continueOnError,
            retriggerPolicy: triggers.first?.retriggerPolicy ?? .ignoreNew,
            metadata: existingMetadata ?? .empty,
            createdAt: createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}

extension TriggerDraft {
    func toTrigger(devices: [DeviceModel]) -> AutomationTrigger {
        let triggerConds = conditionRoot.toConditions(devices: devices)
        switch triggerType {
        case .deviceStateChange:
            return .deviceStateChange(DeviceStateTrigger(
                deviceId: deviceId,
                serviceId: serviceId,
                characteristicId: characteristicId,
                matchOperator: toTriggerCondition(),
                name: name.isEmpty ? nil : name,
                retriggerPolicy: retriggerPolicy,
                conditions: triggerConds
            ))
        case .schedule:
            return .schedule(ScheduleTrigger(
                scheduleType: toScheduleType(),
                name: name.isEmpty ? nil : name,
                retriggerPolicy: retriggerPolicy,
                conditions: triggerConds
            ))
        case .webhook:
            return .webhook(WebhookTrigger(
                token: webhookToken,
                name: name.isEmpty ? nil : name,
                retriggerPolicy: retriggerPolicy,
                conditions: triggerConds
            ))
        case .automation:
            return .automation(AutomationCallTrigger(
                name: name.isEmpty ? nil : name,
                retriggerPolicy: retriggerPolicy,
                conditions: triggerConds
            ))
        case .sunEvent:
            return .sunEvent(SunEventTrigger(
                event: sunEventType,
                offsetMinutes: sunEventOffsetMinutes,
                name: name.isEmpty ? nil : name,
                retriggerPolicy: retriggerPolicy,
                conditions: triggerConds
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
            let to = conditionValue.isEmpty ? nil : parseValue(conditionValue)
            return .transitioned(from: from, to: to)
        case .greaterThan: return .greaterThan(Double(conditionValue) ?? 0)
        case .lessThan: return .lessThan(Double(conditionValue) ?? 0)
        case .greaterThanOrEqual: return .greaterThanOrEqual(Double(conditionValue) ?? 0)
        case .lessThanOrEqual: return .lessThanOrEqual(Double(conditionValue) ?? 0)
        }
    }
}

extension ConditionDraft {
    func toCondition(devices: [DeviceModel]) -> AutomationCondition {
        let base: AutomationCondition
        switch conditionDraftType {
        case .deviceState:
            base = .deviceState(DeviceStateCondition(
                deviceId: deviceId,
                serviceId: serviceId,
                characteristicId: characteristicId,
                comparison: toComparison()
            ))
        case .timeCondition:
            base = .timeCondition(TimeCondition(
                mode: timeConditionMode,
                startTime: timeConditionMode == .timeRange ? timeRangeStart : nil,
                endTime: timeConditionMode == .timeRange ? timeRangeEnd : nil
            ))
        case .sceneActive:
            base = .sceneActive(SceneActiveCondition(
                sceneId: sceneId,
                isActive: sceneIsActive
            ))
        case .blockResult:
            let scope: BlockResultScope
            switch blockResultScope {
            case .specific:
                scope = .specific(blockId: blockResultBlockId ?? UUID())
            case .all:
                scope = .all
            case .any:
                scope = .any
            }
            base = .blockResult(BlockResultCondition(
                scope: scope,
                expectedStatus: blockResultExpectedStatus
            ))
        case .engineState:
            let ref: StateVariableRef = stateVariableName.isEmpty
                ? .byId(UUID(uuidString: stateVariableId) ?? UUID())
                : .byName(stateVariableName)
            let compareToRef: StateVariableRef? = stateCompareMode == .stateRef && !stateCompareToVariableName.isEmpty
                ? .byName(stateCompareToVariableName)
                : nil
            base = .engineState(EngineStateCondition(
                variableRef: ref,
                comparison: toComparison(),
                compareToStateRef: compareToRef,
                dynamicDateValue: buildDatetimeSentinel()
            ))
        }
        return base
    }

    func toComparison() -> ComparisonOperator {
        comparisonType.toOperator(value: comparisonValue)
    }

    /// Builds the datetime sentinel string for dynamic resolution at evaluation time.
    /// Returns nil for non-datetime conditions or when compare mode is stateRef.
    func buildDatetimeSentinel() -> String? {
        guard stateCompareMode == .literal else { return nil }
        // Build the sentinel from the datetime compare mode fields
        switch datetimeCompareMode {
        case .now:
            return "__now__"
        case .relative:
            let sign = datetimeRelativeDirection == .ago ? "-" : "+"
            let unitChar: String
            switch datetimeRelativeUnit {
            case .seconds: unitChar = "s"
            case .minutes: unitChar = "m"
            case .hours: unitChar = "h"
            case .days: unitChar = "d"
            }
            let amountStr = datetimeRelativeAmount.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(datetimeRelativeAmount)) : String(datetimeRelativeAmount)
            return "__now\(sign)\(amountStr)\(unitChar)__"
        case .specific:
            return nil // Specific dates use the static comparison value
        }
    }
}

extension ConditionGroupDraft {
    /// Convert to a single `AutomationCondition`, or nil if the group is empty.
    func toCondition(devices: [DeviceModel]) -> AutomationCondition? {
        let childConditions: [AutomationCondition] = children.compactMap { node in
            switch node {
            case .leaf(let draft):
                return draft.toCondition(devices: devices)
            case .group(let subGroup):
                return subGroup.toCondition(devices: devices)
            }
        }

        guard !childConditions.isEmpty else { return nil }

        let result: AutomationCondition
        if childConditions.count == 1 {
            result = childConditions[0]
        } else {
            result = logicOperator == .and ? .and(childConditions) : .or(childConditions)
        }

        return isNegated ? .not(result) : result
    }

    /// Convert to the `[AutomationCondition]?` format used by `Automation.conditions`.
    func toConditions(devices: [DeviceModel]) -> [AutomationCondition]? {
        guard let condition = toCondition(devices: devices) else { return nil }
        return [condition]
    }
}

extension ComparisonType {
    func toOperator(value: String) -> ComparisonOperator {
        switch self {
        case .equals: return .equals(parseValue(value))
        case .notEquals: return .notEquals(parseValue(value))
        case .greaterThan: return .greaterThan(Self.toNumericOrEpoch(value))
        case .lessThan: return .lessThan(Self.toNumericOrEpoch(value))
        case .greaterThanOrEqual: return .greaterThanOrEqual(Self.toNumericOrEpoch(value))
        case .lessThanOrEqual: return .lessThanOrEqual(Self.toNumericOrEpoch(value))
        case .isEmpty: return .isEmpty
        case .isNotEmpty: return .isNotEmpty
        case .contains: return .contains(value)
        }
    }

    /// Converts a string to Double. For datetime values ("__now__" or ISO 8601), converts to epoch timestamp.
    private static func toNumericOrEpoch(_ value: String) -> Double {
        if let d = Double(value) { return d }
        if let date = StateVariable.parseDate(value) { return date.timeIntervalSince1970 }
        return 0
    }
}

extension BlockDraft {
    func toBlock(devices: [DeviceModel]) -> AutomationBlock {
        switch blockType {
        case let .controlDevice(d):
            let valueRef: StateVariableRef? = d.valueSource == .global && !d.valueRefName.isEmpty
                ? .byName(d.valueRefName) : nil
            return .action(.controlDevice(ControlDeviceAction(
                deviceId: d.deviceId,
                serviceId: d.serviceId,
                characteristicId: d.characteristicId,
                value: parseValue(d.value),
                valueRef: valueRef,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .webhook(d):
            return .action(.webhook(WebhookActionConfig(
                url: d.url,
                method: d.method,
                headers: nil,
                body: d.body.isEmpty ? nil : AnyCodable(d.body),
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .log(d):
            return .action(.log(LogAction(message: d.message, name: d.name.isEmpty ? nil : d.name)), blockId: id)
        case let .runScene(d):
            return .action(.runScene(RunSceneAction(
                sceneId: d.sceneId,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .stateVariable(d):
            return .action(.stateVariable(StateVariableAction(
                operation: d.toOperation(),
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .delay(d):
            let secondsRef: StateVariableRef? = d.valueSource == .global && !d.secondsRefName.isEmpty
                ? .byName(d.secondsRefName) : nil
            return .flowControl(.delay(DelayBlock(seconds: d.seconds, secondsRef: secondsRef, name: d.name.isEmpty ? nil : d.name)), blockId: id)
        case let .waitForState(d):
            let condition = d.conditionRoot.toCondition(devices: devices) ?? .deviceState(DeviceStateCondition(
                deviceId: "", characteristicId: "", comparison: .equals(AnyCodable(true))
            ))
            return .flowControl(.waitForState(WaitForStateBlock(
                condition: condition,
                timeoutSeconds: d.timeoutSeconds,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .conditional(d):
            let condition = d.conditionRoot.toCondition(devices: devices) ?? .deviceState(DeviceStateCondition(
                deviceId: "", characteristicId: "", comparison: .equals(AnyCodable(true))
            ))
            return .flowControl(.conditional(ConditionalBlock(
                condition: condition,
                thenBlocks: d.thenBlocks.map { $0.toBlock(devices: devices) },
                elseBlocks: d.elseBlocks.isEmpty ? nil : d.elseBlocks.map { $0.toBlock(devices: devices) },
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .repeatBlock(d):
            return .flowControl(.repeat(RepeatBlock(
                count: d.count,
                blocks: d.blocks.map { $0.toBlock(devices: devices) },
                delayBetweenSeconds: d.delayBetweenSeconds > 0 ? d.delayBetweenSeconds : nil,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .repeatWhile(d):
            let condition = d.conditionRoot.toCondition(devices: devices) ?? .deviceState(DeviceStateCondition(
                deviceId: "", characteristicId: "", comparison: .equals(AnyCodable(true))
            ))
            return .flowControl(.repeatWhile(RepeatWhileBlock(
                condition: condition,
                blocks: d.blocks.map { $0.toBlock(devices: devices) },
                maxIterations: d.maxIterations,
                delayBetweenSeconds: d.delayBetweenSeconds > 0 ? d.delayBetweenSeconds : nil,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .group(d):
            return .flowControl(.group(GroupBlock(
                label: d.label.isEmpty ? nil : d.label,
                blocks: d.blocks.map { $0.toBlock(devices: devices) },
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .stop(d):
            return .flowControl(.stop(StopBlock(
                outcome: d.outcome,
                message: d.message.isEmpty ? nil : d.message,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
        case let .executeAutomation(d):
            return .flowControl(.executeAutomation(ExecuteAutomationBlock(
                targetAutomationId: d.targetAutomationId ?? UUID(),
                executionMode: d.executionMode,
                name: d.name.isEmpty ? nil : d.name
            )), blockId: id)
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
