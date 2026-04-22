import Foundation
import Combine

/// Core automation engine that evaluates triggers, checks conditions, and executes blocks.
actor AutomationEngine: AutomationEngineProtocol {
    private let automationStorageService: AutomationStorageService
    private let stateVariableStorage: StateVariableStorageService
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let executionLogService: LoggingService
    private let storage: StorageService
    private let registry: DeviceRegistryService?
    private var conditionEvaluator: ConditionEvaluator
    private var evaluators: [TriggerEvaluator] = []

    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    /// Maps execution log ID → automation ID so we can cancel by execution ID.
    private var executionToAutomation: [UUID: UUID] = [:]
    /// Tracks parent → children automation IDs for inline executions,
    /// so cancelling a parent also cancels its inline children.
    private var inlineChildren: [UUID: Set<UUID>] = [:]
    /// Stores the reason a automation was cancelled (set before calling cancelAutomationTree).
    private var cancellationReasons: [UUID: String] = [:]
    /// Maximum number of automations executing concurrently. When the limit is reached,
    /// additional triggered automations are evaluated and then queued (not dropped).
    private let maxConcurrentExecutions = 20
    private let blockTimeout: TimeInterval = 30

    // MARK: - Pending Queue

    /// A queued automation waiting for a free execution slot.
    private struct PendingEntry {
        let automation: Automation
        let change: StateChange?
        let triggerEvent: TriggerEvent?
        let queuedAt: Date
    }

    /// FIFO queue of automations that have triggered but cannot run yet because
    /// all `maxConcurrentExecutions` slots are occupied.
    private var pendingQueue: [PendingEntry] = []

    /// Maximum number of entries that can wait in the pending queue.
    /// Entries beyond this limit are logged and discarded.
    private let maxPendingQueueSize = 50

    /// Maximum time (seconds) a automation may wait in the pending queue.
    /// Stale entries are logged and discarded when the queue is drained.
    private let pendingQueueStalenessTimeout: TimeInterval = 60

    /// Waiters for `waitForState` blocks — keyed by device+characteristic.
    private var stateWaiters: [String: [StateWaiter]] = [:]

    /// Set of device IDs that have at least one enabled `deviceStateChange` trigger.
    /// Used to skip processing state changes for devices with no matching triggers.
    private var triggerDeviceIds: Set<String> = []

    /// Retains the Combine subscription to HomeKitManager's stateChangePublisher.
    /// Stored as AnyCancellable so it lives as long as the engine.
    nonisolated private let cancellableBag = CancellableBag()

    init(
        storageService: AutomationStorageService,
        homeKitManager: HomeKitManager,
        loggingService: LoggingService,
        executionLogService: LoggingService,
        storage: StorageService,
        registry: DeviceRegistryService? = nil,
        conditionEvaluator: ConditionEvaluator? = nil,
        stateVariableStorage: StateVariableStorageService = StateVariableStorageService()
    ) {
        automationStorageService = storageService
        self.stateVariableStorage = stateVariableStorage
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.executionLogService = executionLogService
        self.storage = storage
        self.registry = registry
        self.conditionEvaluator = conditionEvaluator ?? ConditionEvaluator(homeKitManager: homeKitManager, storage: storage, loggingService: loggingService, registry: registry)
        self.conditionEvaluator.stateVariableStorage = stateVariableStorage
    }

    /// Wire up the one-directional subscription to HomeKitManager's state changes.
    /// Called once by ServiceContainer after both objects are created.
    /// HomeKitManager publishes → AutomationEngine.processStateChange() is called.
    /// No reference to AutomationEngine is stored in HomeKitManager.
    nonisolated func subscribeToStateChanges(from publisher: PassthroughSubject<StateChange, Never>) {
        // Subscribe to state changes, but only spawn a Task when the device has a known trigger
        let stateChangeCancellable = publisher
            .sink { [weak self] change in
                guard let self else { return }
                Task { await self.processStateChangeIfTriggered(change) }
            }
        cancellableBag.store(stateChangeCancellable)

        // Rebuild trigger device index whenever automations change
        let automationsCancellable = automationStorageService.automationsSubject
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.rebuildTriggerDeviceIndex() }
            }
        cancellableBag.store(automationsCancellable)

        // Build initial index
        Task { await rebuildTriggerDeviceIndex() }
    }

    /// Rebuilds the set of device IDs that have at least one enabled deviceStateChange trigger.
    private func rebuildTriggerDeviceIndex() async {
        let automations = await automationStorageService.getEnabledAutomations()
        var deviceIds = Set<String>()
        for automation in automations {
            for trigger in automation.triggers {
                if case .deviceStateChange(let t) = trigger {
                    deviceIds.insert(t.deviceId)
                }
            }
        }
        triggerDeviceIds = deviceIds
    }

    /// Notifies waitForState waiters for every state change, but only runs
    /// full trigger evaluation when the device has a known automation trigger.
    private func processStateChangeIfTriggered(_ change: StateChange) async {
        // Always notify waitForState waiters — they may be waiting on any device
        await notifyStateWaiters(change)

        // Only run full automation evaluation if this device has triggers
        guard triggerDeviceIds.contains(change.deviceId) else { return }
        await processStateChange(change)
    }

    func registerEvaluator(_ evaluator: TriggerEvaluator) {
        evaluators.append(evaluator)
    }

    /// Evaluate a single condition using the engine's condition evaluator.
    /// Used by the automation editor's real-time test button.
    func evaluateCondition(_ condition: AutomationCondition) async -> ConditionResult {
        await conditionEvaluator.evaluate(condition)
    }

    // MARK: - Logging Policy Helpers

    /// Whether any log entry should be written for `automation`. Consults the
    /// per-automation `loggingOverride` first, falling back to global settings.
    private nonisolated func shouldLogAutomation(_ automation: Automation) -> Bool {
        guard storage.readLoggingEnabled() else { return false }
        switch automation.loggingOverride {
        case .off: return false
        case .executed, .all: return true
        case .none: return storage.readAutomationLoggingEnabled()
        }
    }

    /// Whether to log skipped executions (trigger guard or execution guard failures)
    /// for `automation`. Consults the per-automation override first, falling back to globals.
    private nonisolated func shouldLogSkippedAutomation(_ automation: Automation) -> Bool {
        guard storage.readLoggingEnabled() else { return false }
        switch automation.loggingOverride {
        case .off, .executed: return false
        case .all: return true
        case .none: return storage.readAutomationLoggingEnabled() && storage.readLogSkippedAutomations()
        }
    }

    private nonisolated func updateBlockResult(_ updated: BlockResult, in results: inout [BlockResult]) -> Bool {
        for i in 0 ..< results.count {
            if results[i].id == updated.id {
                results[i] = updated
                return true
            }
            if var nested = results[i].nestedResults {
                if updateBlockResult(updated, in: &nested) {
                    results[i].nestedResults = nested
                    return true
                }
            }
        }
        return false
    }

    // MARK: - State Change Processing

    /// Main entry — called whenever HomeKitManager publishes a state change.
    /// Note: notifyStateWaiters is called by processStateChangeIfTriggered before this.
    func processStateChange(_ change: StateChange) async {
        guard storage.readAutomationsEnabled() else { return }

        let automations = await automationStorageService.getEnabledAutomations()
        let context = TriggerContext.stateChange(change)

        for automation in automations {
            // Evaluate ALL automations regardless of slot availability —
            // previously used `break` which silently skipped unevaluated automations.
            let triggerResult = await checkTriggers(automation.triggers, context: context)

            switch triggerResult {
            case .noMatch:
                continue

            case .guardFailed(let condResults):
                // Log trigger guard failure using the same mechanism as execution guards
                if shouldLogSkippedAutomation(automation) {
                    let charName = CharacteristicTypes.displayName(for: change.characteristicType)
                    let triggerDesc = "\(change.deviceName) \(charName) changed"
                    var execLog = AutomationExecutionLog(
                        automationId: automation.id,
                        automationName: automation.name,
                        triggerEvent: TriggerEvent(
                            deviceId: change.deviceId,
                            deviceName: change.deviceName,
                            serviceName: change.serviceName,
                            characteristicName: charName,
                            roomName: change.roomName,
                            oldValue: change.oldValue.map { AnyCodable($0) },
                            newValue: change.newValue.map { AnyCodable($0) },
                            triggerDescription: triggerDesc
                        )
                    )
                    execLog.status = .conditionNotMet
                    execLog.conditionResults = condResults
                    let failedDescriptions = condResults.filter { !$0.passed }.map { $0.conditionDescription }
                    execLog.errorMessage = "Trigger guard not met: \(failedDescriptions.joined(separator: "; "))"
                    execLog.completedAt = Date()
                    await executionLogService.logEntry(execLog.toStateChangeLog())
                    await automationStorageService.updateMetadata(
                        id: automation.id,
                        lastTriggered: execLog.triggeredAt,
                        incrementExecutions: false,
                        resetFailures: false
                    )
                }
                continue

            case .matched(let matchedPolicy):
                // Already running?
                if runningTasks[automation.id] != nil {
                    switch matchedPolicy {
                    case .ignoreNew:
                        AppLogger.automation.debug("[\(automation.name)] Ignoring new trigger — automation already running (ignoreNew policy)")
                        continue
                    case .cancelAndRestart:
                        AppLogger.automation.debug("[\(automation.name)] Cancelling running execution — restarting (cancelAndRestart policy)")
                        cancellationReasons[automation.id] = "Cancelled and restarted — new device state trigger fired while running (cancelAndRestart policy)"
                        cancelAutomationTree(automation.id)
                        runningTasks.removeValue(forKey: automation.id)
                    case .queueAndExecute:
                        enqueueAutomation(automation, change: change)
                        continue
                    case .cancelOnly:
                        AppLogger.automation.debug("[\(automation.name)] Cancelling running execution — no restart (cancelOnly policy)")
                        cancellationReasons[automation.id] = "Cancelled — new device state trigger fired while running (cancelOnly policy)"
                        cancelAutomationTree(automation.id)
                        runningTasks.removeValue(forKey: automation.id)
                        continue
                    }
                }

                startExecution(automation, change: change)
            }
        }
    }

    /// Manual trigger for testing.
    func triggerAutomation(id: UUID) async -> AutomationExecutionLog? {
        guard storage.readAutomationsEnabled() else { return nil }
        guard let automation = await automationStorageService.getAutomation(id: id) else { return nil }

        // Handle retrigger policy for manual trigger (use automation-level fallback)
        if runningTasks[id] != nil {
            switch automation.retriggerPolicy {
            case .ignoreNew:
                return nil
            case .cancelAndRestart:
                cancellationReasons[id] = "Cancelled and restarted — manual trigger while running (cancelAndRestart policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
            case .queueAndExecute:
                enqueueAutomation(automation, change: nil)
                return nil
            case .cancelOnly:
                cancellationReasons[id] = "Cancelled — manual trigger while running (cancelOnly policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                return nil
            }
        }

        let manualEvent = Self.manualTriggerEvent()
        let task = Task { [weak self] () -> AutomationExecutionLog in
            let result = await self?.executeAutomation(automation, change: nil, triggerEvent: manualEvent) ?? AutomationExecutionLog(automationId: id, automationName: automation.name, triggerEvent: manualEvent)
            if !Task.isCancelled {
                await self?.removeRunning(id)
            }
            return result
        }
        runningTasks[id] = Task {
            await withTaskCancellationHandler {
                _ = await task.value
            } onCancel: {
                task.cancel()
            }
        }
        return await task.value
    }

    /// Trigger a automation from a schedule or webhook with a custom trigger event.
    func triggerAutomation(id: UUID, triggerEvent: TriggerEvent) async -> AutomationExecutionLog? {
        return await triggerAutomation(id: id, triggerEvent: triggerEvent, policy: nil)
    }

    /// Trigger a automation with an explicit retrigger policy from the matched trigger.
    func triggerAutomation(id: UUID, triggerEvent: TriggerEvent, policy: ConcurrentExecutionPolicy?) async -> AutomationExecutionLog? {
        guard storage.readAutomationsEnabled() else { return nil }
        guard let automation = await automationStorageService.getAutomation(id: id) else { return nil }
        guard automation.isEnabled else { return nil }

        let effectivePolicy = policy ?? automation.retriggerPolicy

        if runningTasks[id] != nil {
            switch effectivePolicy {
            case .ignoreNew:
                return nil
            case .cancelAndRestart:
                cancellationReasons[id] = "Cancelled and restarted — new trigger fired while running (cancelAndRestart policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
            case .queueAndExecute:
                enqueueAutomation(automation, change: nil)
                return nil
            case .cancelOnly:
                cancellationReasons[id] = "Cancelled — new trigger fired while running (cancelOnly policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                return nil
            }
        }

        let task = Task { [weak self] () -> AutomationExecutionLog in
            let result = await self?.executeAutomation(automation, change: nil, triggerEvent: triggerEvent) ?? AutomationExecutionLog(automationId: id, automationName: automation.name, triggerEvent: triggerEvent)
            if !Task.isCancelled {
                await self?.removeRunning(id)
            }
            return result
        }
        runningTasks[id] = Task {
            await withTaskCancellationHandler {
                _ = await task.value
            } onCancel: {
                task.cancel()
            }
        }
        return await task.value
    }

    // MARK: - Fire-and-Forget Triggers

    /// Fire-and-forget manual trigger — returns immediately with the scheduling outcome.
    func scheduleTrigger(id: UUID) async -> TriggerResult {
        guard storage.readAutomationsEnabled() else { return .disabled }
        guard let automation = await automationStorageService.getAutomation(id: id) else { return .notFound }

        let manualEvent = Self.manualTriggerEvent()

        if runningTasks[id] != nil {
            switch automation.retriggerPolicy {
            case .ignoreNew:
                return .ignored(automationId: id, automationName: automation.name)
            case .cancelAndRestart:
                cancellationReasons[id] = "Cancelled and restarted — manual schedule trigger while running (cancelAndRestart policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                startExecution(automation, change: nil, triggerEvent: manualEvent)
                return .replaced(automationId: id, automationName: automation.name)
            case .queueAndExecute:
                enqueueAutomation(automation, change: nil, triggerEvent: manualEvent)
                return .queued(automationId: id, automationName: automation.name)
            case .cancelOnly:
                cancellationReasons[id] = "Cancelled — manual schedule trigger while running (cancelOnly policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                return .cancelled(automationId: id, automationName: automation.name)
            }
        }

        startExecution(automation, change: nil, triggerEvent: manualEvent)
        return .scheduled(automationId: id, automationName: automation.name)
    }

    private static func manualTriggerEvent() -> TriggerEvent {
        TriggerEvent(
            deviceId: nil,
            deviceName: nil,
            serviceName: nil,
            characteristicName: nil,
            roomName: nil,
            oldValue: nil,
            newValue: nil,
            triggerDescription: "Manually triggered"
        )
    }

    /// Fire-and-forget trigger with a custom event — returns immediately with the scheduling outcome.
    func scheduleTrigger(id: UUID, triggerEvent: TriggerEvent) async -> TriggerResult {
        return await scheduleTrigger(id: id, triggerEvent: triggerEvent, policy: nil, triggerConditions: nil)
    }

    /// Fire-and-forget trigger with a custom event and explicit policy (no trigger guards).
    func scheduleTrigger(id: UUID, triggerEvent: TriggerEvent, policy: ConcurrentExecutionPolicy?) async -> TriggerResult {
        return await scheduleTrigger(id: id, triggerEvent: triggerEvent, policy: policy, triggerConditions: nil)
    }

    /// Fire-and-forget trigger with a custom event, explicit policy, and optional per-trigger guard conditions.
    func scheduleTrigger(id: UUID, triggerEvent: TriggerEvent, policy: ConcurrentExecutionPolicy?, triggerConditions: [AutomationCondition]?) async -> TriggerResult {
        guard storage.readAutomationsEnabled() else { return .disabled }
        guard let automation = await automationStorageService.getAutomation(id: id) else { return .notFound }
        guard automation.isEnabled else { return .automationDisabled(automationId: id, automationName: automation.name) }

        // Evaluate per-trigger guard conditions
        if let conditions = triggerConditions, !conditions.isEmpty {
            let (allPassed, condResults) = await conditionEvaluator.evaluateAll(conditions)
            if !allPassed {
                if shouldLogSkippedAutomation(automation) {
                    var execLog = AutomationExecutionLog(
                        automationId: automation.id,
                        automationName: automation.name,
                        triggerEvent: triggerEvent
                    )
                    execLog.status = .conditionNotMet
                    execLog.conditionResults = condResults
                    let failedDescriptions = condResults.filter { !$0.passed }.map { $0.conditionDescription }
                    execLog.errorMessage = "Trigger guard not met: \(failedDescriptions.joined(separator: "; "))"
                    execLog.completedAt = Date()
                    await executionLogService.logEntry(execLog.toStateChangeLog())
                    await automationStorageService.updateMetadata(
                        id: automation.id,
                        lastTriggered: execLog.triggeredAt,
                        incrementExecutions: true,
                        resetFailures: false
                    )
                }
                return .guardNotMet(automationId: id, automationName: automation.name)
            }
        }

        let effectivePolicy = policy ?? automation.retriggerPolicy

        if runningTasks[id] != nil {
            switch effectivePolicy {
            case .ignoreNew:
                return .ignored(automationId: id, automationName: automation.name)
            case .cancelAndRestart:
                cancellationReasons[id] = "Cancelled and restarted — new trigger fired while running (cancelAndRestart policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                startExecution(automation, change: nil, triggerEvent: triggerEvent)
                return .replaced(automationId: id, automationName: automation.name)
            case .queueAndExecute:
                enqueueAutomation(automation, change: nil, triggerEvent: triggerEvent)
                return .queued(automationId: id, automationName: automation.name)
            case .cancelOnly:
                cancellationReasons[id] = "Cancelled — new trigger fired while running (cancelOnly policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                return .cancelled(automationId: id, automationName: automation.name)
            }
        }

        startExecution(automation, change: nil, triggerEvent: triggerEvent)
        return .scheduled(automationId: id, automationName: automation.name)
    }

    /// Internal trigger used by the Execute Automation block — carries caller context for circular call detection.
    private func triggerAutomation(id: UUID, triggerEvent: TriggerEvent, callerContext: ExecutionContext) async -> AutomationExecutionLog? {
        guard let automation = await automationStorageService.getAutomation(id: id) else { return nil }
        guard automation.isEnabled else { return nil }

        // Check circular call before anything else
        if callerContext.callingAutomationIds.contains(id) {
            AppLogger.automation.warning("[\(automation.name)] Circular automation call detected — aborting")
            return nil
        }

        // Use the target automation's .automation trigger policy if available, else automation-level fallback
        let automationTriggerPolicy = automation.triggers.first(where: {
            if case .automation = $0 { return true }
            return false
        })?.resolvedRetriggerPolicy ?? automation.retriggerPolicy

        if runningTasks[id] != nil {
            switch automationTriggerPolicy {
            case .ignoreNew:
                return nil
            case .cancelAndRestart:
                cancellationReasons[id] = "Cancelled and restarted — called by executeAutomation block while running (cancelAndRestart policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
            case .queueAndExecute:
                enqueueAutomation(automation, change: nil)
                return nil
            case .cancelOnly:
                cancellationReasons[id] = "Cancelled — called by executeAutomation block while running (cancelOnly policy)"
                cancelAutomationTree(id)
                runningTasks.removeValue(forKey: id)
                return nil
            }
        }

        var context = ExecutionContext(automation: automation, callingAutomationIds: callerContext.callingAutomationIds)
        context.callingAutomationIds.insert(callerContext.automation.id)

        let task = Task { [weak self] () -> AutomationExecutionLog in
            let result = await self?.executeAutomation(automation, change: nil, triggerEvent: triggerEvent, callerContext: context) ?? AutomationExecutionLog(automationId: id, automationName: automation.name, triggerEvent: triggerEvent)
            if !Task.isCancelled {
                await self?.removeRunning(id)
            }
            return result
        }
        runningTasks[id] = Task {
            await withTaskCancellationHandler {
                _ = await task.value
            } onCancel: {
                task.cancel()
            }
        }
        return await task.value
    }

    // MARK: - Cancellation

    /// Cancel a specific running execution by its execution log ID.
    func cancelExecution(executionId: UUID) {
        guard let automationId = executionToAutomation[executionId] else { return }
        AppLogger.automation.info("Cancelling execution \(executionId) for automation \(automationId)")
        cancellationReasons[automationId] = "Cancelled by user request"
        cancelAutomationTree(automationId)
        runningTasks.removeValue(forKey: automationId)
    }

    /// Cancel all running executions for a specific automation.
    func cancelRunningExecutions(forAutomation automationId: UUID) {
        AppLogger.automation.info("Cancelling running execution for automation \(automationId)")
        cancellationReasons[automationId] = "Cancelled by user request"
        cancelAutomationTree(automationId)
        runningTasks.removeValue(forKey: automationId)
        // Also remove any pending queue entries for this automation
        pendingQueue.removeAll { $0.automation.id == automationId }
    }

    /// Recursively cancel a automation and all its inline children.
    private func cancelAutomationTree(_ automationId: UUID) {
        // Cancel inline children first (depth-first)
        if let children = inlineChildren[automationId] {
            for childId in children {
                cancelAutomationTree(childId)
            }
            inlineChildren.removeValue(forKey: automationId)
        }
        // Cancel this automation's task
        runningTasks[automationId]?.cancel()
    }

    /// Retrieve and remove the cancellation reason for a automation.
    private func consumeCancellationReason(for automationId: UUID) -> String? {
        cancellationReasons.removeValue(forKey: automationId)
    }

    // MARK: - Execution Slot Management

    /// Attempt to immediately start a automation, or queue it if no slots are available.
    private func startExecution(_ automation: Automation, change: StateChange?, triggerEvent: TriggerEvent? = nil) {
        guard runningTasks.count < maxConcurrentExecutions else {
            enqueueAutomation(automation, change: change, triggerEvent: triggerEvent)
            return
        }
        let automationId = automation.id
        let task = Task { [weak self] in
            await self?.executeAutomation(automation, change: change, triggerEvent: triggerEvent)
            // Only clean up if not cancelled — cancelled tasks have their entry removed
            // by the canceller, so calling removeRunning here would remove the replacement task.
            if !Task.isCancelled {
                await self?.removeRunning(automationId)
            }
        }
        runningTasks[automationId] = task
    }

    /// Add a automation to the pending FIFO queue, respecting the max queue size.
    /// Only one pending entry per automation — duplicate triggers are ignored.
    private func enqueueAutomation(_ automation: Automation, change: StateChange?, triggerEvent: TriggerEvent? = nil) {
        if pendingQueue.contains(where: { $0.automation.id == automation.id }) {
            AppLogger.automation.debug("[\(automation.name)] Already queued, skipping duplicate trigger")
            return
        }
        let maxSize = maxPendingQueueSize
        guard pendingQueue.count < maxSize else {
            AppLogger.automation.warning("[\(automation.name)] Pending queue full (\(maxSize)). Discarding trigger.")
            return
        }
        let slots = runningTasks.count
        let maxSlots = maxConcurrentExecutions
        let pending = pendingQueue.count + 1
        AppLogger.automation.info("[\(automation.name)] Queued (slots: \(slots)/\(maxSlots), pending: \(pending))")
        pendingQueue.append(PendingEntry(automation: automation, change: change, triggerEvent: triggerEvent, queuedAt: Date()))
    }

    /// Called when a automation completes. Frees the slot and drains the pending queue.
    private func removeRunning(_ id: UUID) {
        runningTasks.removeValue(forKey: id)
        drainPendingQueue()
    }

    /// Drain queued automations into available execution slots.
    /// Discards entries that have been waiting longer than `pendingQueueStalenessTimeout`.
    private func drainPendingQueue() {
        let now = Date()
        let maxSlots = maxConcurrentExecutions
        let stalenessLimit = pendingQueueStalenessTimeout
        while runningTasks.count < maxSlots, !pendingQueue.isEmpty {
            let entry = pendingQueue.removeFirst()

            let waitTime = now.timeIntervalSince(entry.queuedAt)
            if waitTime > stalenessLimit {
                let waited = Int(waitTime)
                let limit = Int(stalenessLimit)
                AppLogger.automation.warning("[\(entry.automation.name)] Discarding stale queued trigger (waited \(waited)s > \(limit)s limit)")
                continue
            }

            let waitStr = String(format: "%.1f", waitTime)
            AppLogger.automation.info("[\(entry.automation.name)] Dequeued after \(waitStr)s — starting execution")
            startExecution(entry.automation, change: entry.change, triggerEvent: entry.triggerEvent)
        }
    }

    // MARK: - Trigger Evaluation

    private enum TriggerCheckResult {
        case matched(ConcurrentExecutionPolicy)
        case guardFailed(conditionResults: [ConditionResult])
        case noMatch
    }

    /// Evaluates triggers and returns the result: matched (with policy), guard failed, or no match.
    /// When a trigger matches but its guard fails, returns `.guardFailed` with condition results for logging.
    /// If multiple triggers match but all have failing guards, the last guard failure is returned.
    private func checkTriggers(_ triggers: [AutomationTrigger], context: TriggerContext) async -> TriggerCheckResult {
        var lastGuardFailure: [ConditionResult]?

        for trigger in triggers {
            var matched = false
            for evaluator in evaluators {
                if evaluator.canEvaluate(trigger) {
                    if await evaluator.evaluate(trigger, context: context) {
                        matched = true
                    }
                    break
                }
            }
            guard matched else { continue }

            // Evaluate per-trigger guards
            if let conditions = trigger.conditions, !conditions.isEmpty {
                let (allPassed, condResults) = await conditionEvaluator.evaluateAll(conditions)
                if !allPassed {
                    lastGuardFailure = condResults
                    continue
                }
            }

            return .matched(trigger.resolvedRetriggerPolicy)
        }

        if let condResults = lastGuardFailure {
            return .guardFailed(conditionResults: condResults)
        }
        return .noMatch
    }

    // MARK: - Automation Execution

    @discardableResult
    private func executeAutomation(_ automation: Automation, change: StateChange?, triggerEvent: TriggerEvent? = nil, callerContext: ExecutionContext? = nil) async -> AutomationExecutionLog {
        let event = triggerEvent ?? change.map { c -> TriggerEvent in
            let charName = CharacteristicTypes.displayName(for: c.characteristicType)
            let desc = "\(c.deviceName) \(charName) changed"
            return TriggerEvent(
                deviceId: c.deviceId,
                deviceName: c.deviceName,
                serviceName: c.serviceName,
                characteristicName: charName,
                roomName: c.roomName,
                oldValue: c.oldValue.map { AnyCodable($0) },
                newValue: c.newValue.map { AnyCodable($0) },
                triggerDescription: desc
            )
        }
        var execLog = AutomationExecutionLog(
            automationId: automation.id,
            automationName: automation.name,
            triggerEvent: event
        )

        // Set automation context for orphan logging and reset block results
        conditionEvaluator.automationId = automation.id
        conditionEvaluator.automationName = automation.name
        conditionEvaluator.blockResults = [:]

        // Evaluate execution guards BEFORE logging — a triggered automation is not yet "running"
        if let conditions = automation.conditions, !conditions.isEmpty {
            let (allPassed, condResults) = await conditionEvaluator.evaluateAll(conditions)
            execLog.conditionResults = condResults

            if !allPassed {
                execLog.status = .conditionNotMet
                let failedDescriptions = condResults.filter { !$0.passed }.map { $0.conditionDescription }
                execLog.errorMessage = "Execution guard not met: \(failedDescriptions.joined(separator: "; "))"
                execLog.completedAt = Date()
                if shouldLogSkippedAutomation(automation) {
                    // Log the skipped execution as a completed entry (never "running")
                    await executionLogService.logEntry(execLog.toStateChangeLog())
                    await automationStorageService.updateMetadata(
                        id: automation.id,
                        lastTriggered: execLog.triggeredAt,
                        incrementExecutions: false,
                        resetFailures: false
                    )
                }
                return execLog
            }
        }

        // Execution guards passed (or none) — now the automation is truly running
        executionToAutomation[execLog.id] = automation.id
        if shouldLogAutomation(automation) {
            await executionLogService.logEntry(execLog.toStateChangeLog())
        }

        // Create a reference box so the @Sendable closure can mutate the log
        class LogBox {
            var execLog: AutomationExecutionLog
            init(_ log: AutomationExecutionLog) {
                execLog = log
            }
        }
        let logBox = LogBox(execLog)

        // Execute blocks in order, updating log after each step
        var context = ExecutionContext(automation: automation, callingAutomationIds: callerContext?.callingAutomationIds ?? [])
        var failed = false

        let onUpdate: @Sendable (BlockResult) async -> Void = { [weak self] updated in
            guard let self = self else { return }
            // Try to update an existing block in the results tree
            if !self.updateBlockResult(updated, in: &logBox.execLog.blockResults) {
                // Block not yet in the array — append it so the UI can show it immediately
                logBox.execLog.blockResults.append(updated)
            }
            if self.shouldLogAutomation(automation) {
                await self.executionLogService.updateEntry(logBox.execLog.toStateChangeLog())
            }
        }

        do {
            for (index, block) in automation.blocks.enumerated() {
                if Task.isCancelled {
                    logBox.execLog.status = .cancelled
                    logBox.execLog.errorMessage = consumeCancellationReason(for: automation.id) ?? "Cancelled"
                    logBox.execLog.completedAt = Date()
                    await finalizeExecution(logBox.execLog, automation: automation, succeeded: false)
                    return logBox.execLog
                }

                let result = try await executeBlock(block, index: index, context: context, onUpdate: onUpdate)

                // Record block result for blockResult conditions
                conditionEvaluator.blockResults[block.blockId] = result.status

                // Note: executeBlock already calls onUpdate for progress and completion,
                // but we append it here if it wasn't already in the top-level list.
                if !logBox.execLog.blockResults.contains(where: { $0.id == result.id }) {
                    logBox.execLog.blockResults.append(result)
                    if shouldLogAutomation(automation) {
                        await executionLogService.updateEntry(logBox.execLog.toStateChangeLog())
                    }
                }

                // Cancellation always stops immediately, regardless of continueOnError
                if result.status == .cancelled || Task.isCancelled {
                    logBox.execLog.status = .cancelled
                    logBox.execLog.errorMessage = consumeCancellationReason(for: automation.id) ?? "Cancelled"
                    logBox.execLog.completedAt = Date()
                    await finalizeExecution(logBox.execLog, automation: automation, succeeded: false)
                    return logBox.execLog
                }

                if result.status == .failure {
                    failed = true
                    if !automation.continueOnError {
                        break
                    }
                }
            }
        } catch let error as AutomationEngineError {
            if case let .stopped(outcome, message) = error {
                logBox.execLog.status = switch outcome {
                case .success: .success
                case .error: .failure
                case .cancelled: .cancelled
                }
                logBox.execLog.errorMessage = message
                logBox.execLog.completedAt = Date()
                await finalizeExecution(logBox.execLog, automation: automation, succeeded: outcome == .success)
                return logBox.execLog
            }
        } catch {}

        // Check for cancellation after the loop — don't overwrite with failure/success
        if Task.isCancelled {
            logBox.execLog.status = .cancelled
            logBox.execLog.errorMessage = consumeCancellationReason(for: automation.id) ?? "Cancelled"
            logBox.execLog.completedAt = Date()
            await finalizeExecution(logBox.execLog, automation: automation, succeeded: false)
            return logBox.execLog
        }

        logBox.execLog.status = failed ? .failure : .success
        logBox.execLog.completedAt = Date()
        logBox.execLog.errorMessage = failed ? logBox.execLog.blockResults.first(where: { $0.status == .failure })?.errorMessage : nil

        await finalizeExecution(logBox.execLog, automation: automation, succeeded: !failed)
        return logBox.execLog
    }

    private func finalizeExecution(_ execLog: AutomationExecutionLog, automation: Automation, succeeded: Bool) async {
        // Clean up execution → automation mapping
        executionToAutomation.removeValue(forKey: execLog.id)

        // Update the existing running log entry with the final result
        if shouldLogAutomation(automation) {
            await executionLogService.updateEntry(execLog.toStateChangeLog())
        }

        // Update automation metadata
        await automationStorageService.updateMetadata(
            id: automation.id,
            lastTriggered: execLog.triggeredAt,
            incrementExecutions: true,
            resetFailures: succeeded
        )

        if !succeeded, execLog.status != .conditionNotMet, execLog.status != .cancelled {
            await automationStorageService.incrementFailures(id: automation.id)
        }

        // Automation execution details are tracked by ExecutionLogService;
        // no duplicate entry needed in the main StateChangeLog stream.
    }

    // MARK: - Block Execution (Recursive)

    /// Executes a single block. May throw `AutomationEngineError.stopped` to halt the entire automation.
    private func executeBlock(_ block: AutomationBlock, index: Int, context: ExecutionContext, onUpdate: @escaping (BlockResult) async -> Void) async throws -> BlockResult {
        switch block {
        case let .action(action, _):
            return await executeAction(action, index: index, context: context, onUpdate: onUpdate)
        case let .flowControl(flowControl, _):
            return try await executeFlowControl(flowControl, index: index, context: context, onUpdate: onUpdate)
        }
    }

    // MARK: - Action Execution

    private func executeAction(_ action: AutomationAction, index: Int, context: ExecutionContext, onUpdate: @escaping (BlockResult) async -> Void) async -> BlockResult {
        let actionName: String? = {
            switch action {
            case let .controlDevice(a): return a.name
            case let .timedControl(a): return a.name
            case let .webhook(a): return a.name
            case let .log(a): return a.name
            case let .runScene(a): return a.name
            case let .stateVariable(a): return a.name
            }
        }()
        var result = BlockResult(blockIndex: index, blockKind: "action", blockType: action.displayType, blockName: actionName)

        // Notify that we are starting
        await onUpdate(result)

        do {
            // Timed control manages its own duration + cancellation + rollback. It can run
            // for many minutes (e.g. a sprinkler held on for 10 minutes), so it must NOT be
            // bound by the per-block withTimeout cap — that would cut the hold short and
            // interrupt the rollback. Every other action type stays inside the 30s cap.
            if case let .timedControl(a) = action {
                let (finalDetail, nested) = try await self.executeTimedControl(
                    a,
                    automationId: context.automation.id,
                    automationName: context.automation.name,
                    reportProgress: { progressDetail, partialNested in
                        var interim = result
                        interim.detail = progressDetail
                        interim.nestedResults = partialNested
                        await onUpdate(interim)
                    }
                )
                result.detail = finalDetail
                result.nestedResults = nested
                result.status = .success
                result.completedAt = Date()
                await onUpdate(result)
                return result
            }

            try await withTimeout(seconds: blockTimeout) {
                switch action {
                case let .controlDevice(a):
                    try await self.executeControlDevice(a, automationId: context.automation.id, automationName: context.automation.name)
                    let deviceName = await self.resolveDeviceName(a.deviceId)
                    let resolvedCharType = self.registry?.readCharacteristicType(forStableId: a.characteristicId) ?? a.characteristicId
                    let svcName = await self.resolveServiceDisplayName(deviceId: a.deviceId, serviceId: a.serviceId)
                    let fullDeviceName = svcName.map { "\(deviceName) (\($0))" } ?? deviceName
                    // Resolve effective value (global ref with fallback) for display
                    let effectiveValue: Any
                    var globalNote: String = ""
                    if let ref = a.valueRef {
                        if let variable = await self.stateVariableStorage.resolve(ref) {
                            effectiveValue = variable.value.value
                            globalNote = " (from global value '\(variable.name)')"
                        } else {
                            effectiveValue = a.value.value
                            globalNote = " (global value \(ref.displayDescription) not found, used default)"
                        }
                    } else {
                        effectiveValue = a.value.value
                    }
                    let humanized = BlockHumanizer.describeControlDeviceChange(
                        deviceName: fullDeviceName,
                        characteristicType: resolvedCharType,
                        value: effectiveValue
                    )
                    result.detail = humanized + globalNote
                    // Override auto-title with humanized sentence when the user didn't set a custom name.
                    if result.blockName == nil {
                        result.blockName = humanized
                    }
                case .timedControl:
                    // Handled above the withTimeout block; unreachable here.
                    break
                case let .webhook(a):
                    try await self.executeWebhook(a)
                    result.detail = "\(a.method) \(a.url)"
                case let .log(a):
                    AppLogger.automation.info("Automation log: \(a.message)")
                    result.detail = a.message
                case let .runScene(a):
                    try await self.homeKitManager.executeScene(id: a.sceneId)
                    let sceneName = await MainActor.run { self.homeKitManager.getScene(id: a.sceneId)?.name } ?? a.sceneId
                    result.detail = "Ran scene '\(sceneName)'"
                case let .stateVariable(a):
                    result.detail = try await self.executeStateVariableAction(a)
                }
            }
            result.status = .success
            result.completedAt = Date()
        } catch is CancellationError {
            result.status = .cancelled
            result.completedAt = Date()
        } catch {
            result.status = .failure
            result.errorMessage = error.localizedDescription
            result.completedAt = Date()
        }

        await onUpdate(result)
        return result
    }

    private func executeControlDevice(_ action: ControlDeviceAction, automationId: UUID, automationName: String) async throws {
        let resolvedType = registry?.readCharacteristicType(forStableId: action.characteristicId)
            ?? CharacteristicTypes.characteristicType(forName: action.characteristicId)
            ?? action.characteristicId

        // Resolve value — from Global Value ref (with fallback) or Local value
        let resolvedValue: Any
        if let ref = action.valueRef {
            if let variable = await stateVariableStorage.resolve(ref) {
                resolvedValue = variable.value.value
            } else {
                // Global Value was deleted or unavailable — use the configured default
                resolvedValue = action.value.value
            }
        } else {
            resolvedValue = action.value.value
        }

        // Validate value against characteristic metadata
        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: action.deviceId) }
        if let device {
            let resolvedServiceId = action.serviceId.map { registry?.readHomeKitServiceId($0) ?? $0 }
            let targetServices = resolvedServiceId != nil ? device.services.filter({ $0.id == resolvedServiceId }) : device.services
            if let characteristic = targetServices.flatMap(\.characteristics).first(where: { $0.type == resolvedType }) {
                try CharacteristicValidator.validate(value: resolvedValue, against: characteristic)
            }
        } else {
            await logOrphan(
                automationId: automationId,
                automationName: automationName,
                location: "controlDevice block '\(action.name ?? "unnamed")'"
            )
        }

        // Convert temperature from user's preferred unit back to Celsius for HomeKit
        var effectiveValue: Any = resolvedValue
        if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(resolvedType) {
            if let doubleVal = resolvedValue as? Double {
                effectiveValue = TemperatureConversion.fahrenheitToCelsius(doubleVal)
            } else if let intVal = resolvedValue as? Int {
                effectiveValue = TemperatureConversion.fahrenheitToCelsius(Double(intVal))
            }
        }

        try await homeKitManager.updateDevice(
            id: action.deviceId,
            characteristicType: resolvedType,
            value: effectiveValue,
            serviceId: action.serviceId
        )
    }

    /// Applies a list of characteristic changes, holds them for the configured duration, then reverts each
    /// change to the value it had immediately before the block ran (in the same forward order).
    /// Rollback runs even if the hold is cancelled or throws. Returns a human-readable result detail
    /// plus a list of per-change nested BlockResults for display in the log tree.
    private func executeTimedControl(
        _ action: TimedControlAction,
        automationId: UUID,
        automationName: String,
        reportProgress: @escaping (String, [BlockResult]) async -> Void
    ) async throws -> (String, [BlockResult]) {
        let totalCount = action.changes.count
        guard totalCount > 0 else {
            return ("Timed control has no changes configured", [])
        }

        // Resolve hold duration (prefer global ref, fall back to local durationSeconds)
        var duration: Double = action.durationSeconds
        if let ref = action.durationRef, let variable = await stateVariableStorage.resolve(ref) {
            if let d = variable.value.value as? Double {
                duration = d
            } else if let i = variable.value.value as? Int {
                duration = Double(i)
            }
        }
        let durationStr = BlockHumanizer.formatDurationLong(duration)

        struct AppliedChange {
            let change: TimedDeviceChange
            let resolvedType: String
            let originalValue: Any
            let nestedIndex: Int
        }

        var nested: [BlockResult] = []
        var applied: [AppliedChange] = []

        // Phase 1 — capture originals and apply forward; build one nested BlockResult per change
        for (i, change) in action.changes.enumerated() {
            let resolvedType = registry?.readCharacteristicType(forStableId: change.characteristicId)
                ?? CharacteristicTypes.characteristicType(forName: change.characteristicId)
                ?? change.characteristicId

            let deviceName = await resolveDeviceName(change.deviceId)
            let svcName = await resolveServiceDisplayName(deviceId: change.deviceId, serviceId: change.serviceId)
            let fullDeviceName = svcName.map { "\(deviceName) (\($0))" } ?? deviceName
            let startedAt = Date()

            let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: change.deviceId) }
            guard let device else {
                await logOrphan(automationId: automationId, automationName: automationName, location: "timedControl change for device \(change.deviceId)")
                nested.append(BlockResult(
                    blockIndex: i, blockKind: "action", blockType: "controlDevice",
                    blockName: "Unknown device",
                    status: .failure, startedAt: startedAt, completedAt: Date(),
                    errorMessage: "Device not found: \(change.deviceId)"
                ))
                await reportProgress("Applying \(i + 1)/\(totalCount)…", nested)
                continue
            }

            let resolvedServiceId = change.serviceId.map { registry?.readHomeKitServiceId($0) ?? $0 }
            let targetServices = resolvedServiceId != nil ? device.services.filter({ $0.id == resolvedServiceId }) : device.services
            guard let characteristic = targetServices.flatMap(\.characteristics).first(where: { $0.type == resolvedType }),
                  let currentValue = characteristic.value else {
                AppLogger.automation.warning("[\(automationName)] timedControl: could not read current value for \(change.deviceId):\(resolvedType), skipping")
                nested.append(BlockResult(
                    blockIndex: i, blockKind: "action", blockType: "controlDevice",
                    blockName: "\(fullDeviceName) — \(CharacteristicTypes.displayName(for: resolvedType))",
                    status: .failure, startedAt: startedAt, completedAt: Date(),
                    errorMessage: "Characteristic unavailable"
                ))
                await reportProgress("Applying \(i + 1)/\(totalCount)…", nested)
                continue
            }

            // Resolve new value (global ref with fallback)
            let resolvedValue: Any
            if let ref = change.valueRef, let variable = await stateVariableStorage.resolve(ref) {
                resolvedValue = variable.value.value
            } else {
                resolvedValue = change.value.value
            }

            let humanizedName = BlockHumanizer.describeControlDeviceChange(
                deviceName: fullDeviceName,
                characteristicType: resolvedType,
                value: resolvedValue
            )
            let wasStr = CharacteristicTypes.formatValue(currentValue.value, characteristicType: resolvedType)

            // Validate against characteristic metadata
            do {
                try CharacteristicValidator.validate(value: resolvedValue, against: characteristic)
            } catch {
                AppLogger.automation.warning("[\(automationName)] timedControl: validation failed for \(change.deviceId):\(resolvedType) — \(error.localizedDescription)")
                nested.append(BlockResult(
                    blockIndex: i, blockKind: "action", blockType: "controlDevice",
                    blockName: humanizedName,
                    status: .failure, startedAt: startedAt, completedAt: Date(),
                    detail: "was \(wasStr)", errorMessage: "Validation failed: \(error.localizedDescription)"
                ))
                await reportProgress("Applying \(i + 1)/\(totalCount)…", nested)
                continue
            }

            // Temperature conversion
            var effectiveValue: Any = resolvedValue
            if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(resolvedType) {
                if let doubleVal = resolvedValue as? Double {
                    effectiveValue = TemperatureConversion.fahrenheitToCelsius(doubleVal)
                } else if let intVal = resolvedValue as? Int {
                    effectiveValue = TemperatureConversion.fahrenheitToCelsius(Double(intVal))
                }
            }

            do {
                try await homeKitManager.updateDevice(
                    id: change.deviceId,
                    characteristicType: resolvedType,
                    value: effectiveValue,
                    serviceId: change.serviceId
                )
                let idx = nested.count
                nested.append(BlockResult(
                    blockIndex: i, blockKind: "action", blockType: "controlDevice",
                    blockName: humanizedName,
                    status: .running, startedAt: startedAt, completedAt: nil,
                    detail: "was \(wasStr) · holding \(durationStr)"
                ))
                applied.append(AppliedChange(change: change, resolvedType: resolvedType, originalValue: currentValue.value, nestedIndex: idx))
            } catch {
                AppLogger.automation.warning("[\(automationName)] timedControl: apply failed for \(change.deviceId):\(resolvedType) — \(error.localizedDescription)")
                nested.append(BlockResult(
                    blockIndex: i, blockKind: "action", blockType: "controlDevice",
                    blockName: humanizedName,
                    status: .failure, startedAt: startedAt, completedAt: Date(),
                    detail: "was \(wasStr)", errorMessage: error.localizedDescription
                ))
            }
            await reportProgress("Applying \(i + 1)/\(totalCount)…", nested)
        }

        if applied.isEmpty {
            throw AutomationEngineError.stateVariableError("timedControl: all \(totalCount) change(s) failed to apply")
        }

        await reportProgress("Holding \(applied.count) change(s) for \(durationStr)…", nested)

        // Phase 2 — sleep; capture cancellation so rollback still runs
        var sleepError: Error?
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
        } catch {
            sleepError = error
        }

        // Phase 3 — rollback in forward order; amend each nested result with revert outcome
        var rollbackFailures = 0
        for item in applied {
            let revertTarget = BlockHumanizer.describeRevertTarget(characteristicType: item.resolvedType, originalValue: item.originalValue)
            let idx = item.nestedIndex
            var r = nested[idx]
            let wasStr = (r.detail?.components(separatedBy: " · ").first ?? "")
            do {
                try await homeKitManager.updateDevice(
                    id: item.change.deviceId,
                    characteristicType: item.resolvedType,
                    value: item.originalValue,
                    serviceId: item.change.serviceId
                )
                r.status = .success
                r.detail = "\(wasStr) · held \(durationStr) · reverted to \(revertTarget)"
                r.completedAt = Date()
            } catch {
                rollbackFailures += 1
                r.status = .failure
                r.errorMessage = "Rollback failed: \(error.localizedDescription)"
                r.detail = "\(wasStr) · held \(durationStr) · rollback to \(revertTarget) failed"
                r.completedAt = Date()
                AppLogger.automation.warning("[\(automationName)] timedControl: rollback failed for \(item.change.deviceId):\(item.resolvedType) — \(error.localizedDescription)")
            }
            nested[idx] = r
        }

        if let error = sleepError { throw error }

        var detail: String
        if applied.count == totalCount {
            detail = "Held \(applied.count) change(s) for \(durationStr), reverted"
        } else {
            detail = "Held \(applied.count)/\(totalCount) change(s) for \(durationStr), reverted"
        }
        if rollbackFailures > 0 {
            detail += " (rollback issues: \(rollbackFailures))"
        }
        return (detail, nested)
    }

    /// Validates that a URL does not point to a private/internal IP address (SSRF protection).
    private static func validateURLNotPrivate(_ url: URL, allowlist: [String]) throws {
        guard let host = url.host else { return }

        let lowered = host.lowercased()

        // Allow hosts matching the user-configured allow list (supports * wildcards)
        if allowlist.contains(where: { matchesWildcard(host: lowered, pattern: $0.lowercased()) }) {
            return
        }

        if lowered == "localhost" || lowered == "127.0.0.1" || lowered == "::1" {
            return
        }

        let cfHost = CFHostCreateWithName(kCFAllocatorDefault, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(cfHost, .addresses, nil)
        guard let addresses = CFHostGetAddressing(cfHost, &resolved)?.takeUnretainedValue() as? [Data], resolved.boolValue else {
            return
        }

        for addressData in addresses {
            let isPrivate = addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> Bool in
                guard let sa = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return false }
                if sa.pointee.sa_family == UInt8(AF_INET) {
                    let sin = pointer.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                    let addr = sin.sin_addr.s_addr
                    let a = addr & 0xFF
                    let b = (addr >> 8) & 0xFF
                    if a == 10 { return true }
                    if a == 172 && (b >= 16 && b <= 31) { return true }
                    if a == 192 && b == 168 { return true }
                    if a == 169 && b == 254 { return true }
                    if a == 127 { return true }
                    if addr == 0 { return true }
                }
                return false
            }
            if isPrivate {
                throw AutomationEngineError.ssrfBlocked(url.absoluteString)
            }
        }
    }

    /// Matches a host against a pattern that may contain `*` wildcards.
    private static func matchesWildcard(host: String, pattern: String) -> Bool {
        if !pattern.contains("*") { return host == pattern }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*") + "$"
        return host.range(of: regex, options: .regularExpression) != nil
    }

    /// Headers that must not be set by user-supplied automation configurations.
    private static let restrictedHeaders: Set<String> = [
        "host", "transfer-encoding", "content-length", "connection",
        "authorization", "cookie", "set-cookie", "proxy-authorization",
        "te", "trailer", "upgrade"
    ]

    /// Execute a state variable operation and return a human-readable detail string.
    private func executeStateVariableAction(_ action: StateVariableAction) async throws -> String {
        switch action.operation {
        case let .create(name, variableType, initialValue):
            if await stateVariableStorage.getByName(name) != nil {
                throw AutomationEngineError.stateVariableError("Variable '\(name)' already exists")
            }
            let variable = StateVariable(name: name, type: variableType, value: initialValue)
            await stateVariableStorage.create(variable)
            return "Created \(variableType.displayName) variable '\(name)' = \(variable.displayValue)"

        case let .remove(ref):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
            }
            await stateVariableStorage.delete(id: variable.id)
            return "Removed variable '\(variable.name)'"

        case let .set(ref, value):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
            }
            await stateVariableStorage.update(id: variable.id, value: value)
            return "Set '\(variable.name)' = \(StateVariable(name: variable.name, type: variable.type, value: value).displayValue)"

        case let .increment(ref, by):
            return try await applyNumberOp(ref: ref, label: "Incremented") { $0 + by }

        case let .decrement(ref, by):
            return try await applyNumberOp(ref: ref, label: "Decremented") { $0 - by }

        case let .multiply(ref, by):
            return try await applyNumberOp(ref: ref, label: "Multiplied") { $0 * by }

        case let .addState(ref, otherRef):
            return try await applyCrossNumberOp(ref: ref, otherRef: otherRef, label: "Added") { $0 + $1 }

        case let .subtractState(ref, otherRef):
            return try await applyCrossNumberOp(ref: ref, otherRef: otherRef, label: "Subtracted") { $0 - $1 }

        case let .toggle(ref):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
            }
            guard variable.type == .boolean, let current = variable.boolValue else {
                throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a boolean")
            }
            let newVal = !current
            await stateVariableStorage.update(id: variable.id, value: AnyCodable(newVal))
            return "Toggled '\(variable.name)' → \(newVal)"

        case let .andState(ref, otherRef):
            return try await applyCrossBoolOp(ref: ref, otherRef: otherRef, label: "AND") { $0 && $1 }

        case let .orState(ref, otherRef):
            return try await applyCrossBoolOp(ref: ref, otherRef: otherRef, label: "OR") { $0 || $1 }

        case let .notState(ref):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
            }
            guard variable.type == .boolean, let current = variable.boolValue else {
                throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a boolean")
            }
            let newVal = !current
            await stateVariableStorage.update(id: variable.id, value: AnyCodable(newVal))
            return "NOT '\(variable.name)' → \(newVal)"

        case let .setFromCharacteristic(ref, deviceId, characteristicId, serviceId):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Global value \(ref.displayDescription) not found")
            }
            guard let device: DeviceModel = await MainActor.run(body: { homeKitManager.getDeviceState(id: deviceId) }) else {
                throw AutomationEngineError.stateVariableError("Device '\(deviceId)' not found")
            }
            let resolvedType = registry?.readCharacteristicType(forStableId: characteristicId)
                ?? CharacteristicTypes.characteristicType(forName: characteristicId)
                ?? characteristicId
            let resolvedServiceId = serviceId.map { registry?.readHomeKitServiceId($0) ?? $0 }
            let targetServices = resolvedServiceId != nil ? device.services.filter({ $0.id == resolvedServiceId }) : device.services
            guard let characteristic = targetServices.flatMap(\.characteristics).first(where: { $0.type == resolvedType }),
                  let currentValue = characteristic.value else {
                throw AutomationEngineError.stateVariableError("Characteristic '\(characteristicId)' not found or has no value")
            }
            await stateVariableStorage.update(id: variable.id, value: AnyCodable(currentValue.value))
            return "Set '\(variable.name)' from device = \(currentValue.value)"

        case let .setToNow(ref):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Global value \(ref.displayDescription) not found")
            }
            guard variable.type == .datetime else {
                throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a datetime")
            }
            let now = Date()
            let isoString = StateVariable.formatDateISO(now)
            await stateVariableStorage.update(id: variable.id, value: AnyCodable(isoString))
            return "Set '\(variable.name)' to now (\(StateVariable(name: "", type: .datetime, value: AnyCodable(isoString)).displayValue))"

        case let .addTime(ref, amount, unit):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Global value \(ref.displayDescription) not found")
            }
            guard variable.type == .datetime, let current = variable.dateValue else {
                throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a datetime or has no valid date")
            }
            let seconds = amount * unit.inSeconds
            let newDate = current.addingTimeInterval(seconds)
            let isoString = StateVariable.formatDateISO(newDate)
            await stateVariableStorage.update(id: variable.id, value: AnyCodable(isoString))
            return "Added \(amount) \(unit.rawValue) to '\(variable.name)'"

        case let .subtractTime(ref, amount, unit):
            guard let variable = await stateVariableStorage.resolve(ref) else {
                throw AutomationEngineError.stateVariableError("Global value \(ref.displayDescription) not found")
            }
            guard variable.type == .datetime, let current = variable.dateValue else {
                throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a datetime or has no valid date")
            }
            let seconds = amount * unit.inSeconds
            let newDate = current.addingTimeInterval(-seconds)
            let isoString = StateVariable.formatDateISO(newDate)
            await stateVariableStorage.update(id: variable.id, value: AnyCodable(isoString))
            return "Subtracted \(amount) \(unit.rawValue) from '\(variable.name)'"
        }
    }

    // MARK: - State Variable Helpers

    private func applyNumberOp(ref: StateVariableRef, label: String, op: (Double) -> Double) async throws -> String {
        guard let variable = await stateVariableStorage.resolve(ref) else {
            throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
        }
        guard variable.type == .number, let current = variable.numberValue else {
            throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a number")
        }
        let newVal = op(current)
        await stateVariableStorage.update(id: variable.id, value: AnyCodable(newVal))
        return "\(label) '\(variable.name)' → \(newVal)"
    }

    private func applyCrossNumberOp(ref: StateVariableRef, otherRef: StateVariableRef, label: String, op: (Double, Double) -> Double) async throws -> String {
        guard let variable = await stateVariableStorage.resolve(ref) else {
            throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
        }
        guard variable.type == .number, let current = variable.numberValue else {
            throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a number")
        }
        guard let other = await stateVariableStorage.resolve(otherRef) else {
            throw AutomationEngineError.stateVariableError("Other variable \(otherRef.displayDescription) not found")
        }
        guard other.type == .number, let otherVal = other.numberValue else {
            throw AutomationEngineError.stateVariableError("Variable '\(other.name)' is not a number")
        }
        let newVal = op(current, otherVal)
        await stateVariableStorage.update(id: variable.id, value: AnyCodable(newVal))
        return "\(label) '\(other.name)' to '\(variable.name)' → \(newVal)"
    }

    private func applyCrossBoolOp(ref: StateVariableRef, otherRef: StateVariableRef, label: String, op: (Bool, Bool) -> Bool) async throws -> String {
        guard let variable = await stateVariableStorage.resolve(ref) else {
            throw AutomationEngineError.stateVariableError("Variable \(ref.displayDescription) not found")
        }
        guard variable.type == .boolean, let current = variable.boolValue else {
            throw AutomationEngineError.stateVariableError("Variable '\(variable.name)' is not a boolean")
        }
        guard let other = await stateVariableStorage.resolve(otherRef) else {
            throw AutomationEngineError.stateVariableError("Other variable \(otherRef.displayDescription) not found")
        }
        guard other.type == .boolean, let otherVal = other.boolValue else {
            throw AutomationEngineError.stateVariableError("Variable '\(other.name)' is not a boolean")
        }
        let newVal = op(current, otherVal)
        await stateVariableStorage.update(id: variable.id, value: AnyCodable(newVal))
        return "'\(variable.name)' \(label) '\(other.name)' → \(newVal)"
    }

    private func executeWebhook(_ action: WebhookActionConfig) async throws {
        guard let url = URL(string: action.url) else {
            throw AutomationEngineError.invalidURL(action.url)
        }

        try Self.validateURLNotPrivate(url, allowlist: storage.readWebhookPrivateIPAllowlist())

        var request = URLRequest(url: url)
        request.httpMethod = action.method
        request.timeoutInterval = blockTimeout

        if let headers = action.headers {
            for (key, value) in headers {
                guard !Self.restrictedHeaders.contains(key.lowercased()) else { continue }
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let methodUpper = action.method.uppercased()
        if let body = action.body, methodUpper != "GET", methodUpper != "HEAD" {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw AutomationEngineError.webhookFailed(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Flow Control Execution

    private func executeFlowControl(_ flowControl: FlowControlBlock, index: Int, context: ExecutionContext, onUpdate: @escaping (BlockResult) async -> Void) async throws -> BlockResult {
        let fcName: String? = {
            switch flowControl {
            case let .delay(b): return b.name
            case let .waitForState(b): return b.name
            case let .conditional(b): return b.name
            case let .repeat(b): return b.name
            case let .repeatWhile(b): return b.name
            case let .group(b): return b.name
            case let .stop(b): return b.name
            case let .executeAutomation(b): return b.name
            }
        }()
        var result = BlockResult(blockIndex: index, blockKind: "flowControl", blockType: flowControl.displayType, blockName: fcName)

        // Notify that we are starting
        await onUpdate(result)

        do {
            switch flowControl {
            case let .delay(block):
                // Resolve delay duration from Global Value or use static value
                let delaySecs: Double
                if let ref = block.secondsRef,
                   let variable = await stateVariableStorage.resolve(ref),
                   let numVal = variable.numberValue {
                    delaySecs = numVal
                } else {
                    delaySecs = block.seconds
                }
                let delayStr = BlockHumanizer.formatDurationLong(delaySecs)
                result.detail = "Waiting \(delayStr)…"
                await onUpdate(result)

                try await Task.sleep(nanoseconds: UInt64(max(0, delaySecs) * 1_000_000_000))
                result.detail = "Waited \(delayStr)"
                result.status = .success

            case let .waitForState(block):
                let waitDesc = waitForStateDescription(block)
                let timeoutStr = BlockHumanizer.formatDurationLong(block.timeoutSeconds)
                result.detail = "Waiting for \(waitDesc)…"
                await onUpdate(result)

                let matched = try await waitForState(block, automationId: context.automation.id, automationName: context.automation.name) { elapsedSeconds in
                    // Update parent with elapsed time while waiting
                    result.detail = "Waiting for \(waitDesc)… (\(BlockHumanizer.formatDurationLong(elapsedSeconds)) elapsed)"
                    await onUpdate(result)
                }
                result.detail = matched
                    ? "\(waitDesc) — condition met"
                    : "\(waitDesc) — timed out after \(timeoutStr)"
                result.status = matched ? .success : .failure
                if !matched {
                    result.errorMessage = "Timed out after \(timeoutStr)"
                }

            case let .conditional(block):
                let condResult = await conditionEvaluator.evaluate(block.condition)
                result.detail = condResult.passed ? "Condition met — running Then blocks" : "Condition not met — running Else blocks"
                await onUpdate(result)

                let blocksToRun = condResult.passed ? block.thenBlocks : (block.elseBlocks ?? [])
                var nested: [BlockResult] = []
                var nestedFailed = false

                let nestedUpdate: (BlockResult) async -> Void = { updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                do {
                    for (i, b) in blocksToRun.enumerated() {
                        if Task.isCancelled { break }
                        let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                        conditionEvaluator.blockResults[b.blockId] = r.status
                        if !nested.contains(where: { $0.id == r.id }) {
                            nested.append(r)
                        }
                        if r.status == .cancelled || Task.isCancelled { break }
                        if r.status == .failure {
                            nestedFailed = true
                            if !context.automation.continueOnError { break }
                        }
                    }
                    result.nestedResults = nested
                    result.status = Task.isCancelled ? .cancelled : (nestedFailed ? .failure : .success)
                } catch let error as AutomationEngineError {
                    if case let .stopped(outcome, message) = error {
                        result.nestedResults = nested
                        result.detail = "Returned: \(outcome.rawValue)\(message.map { " — \($0)" } ?? "")"
                        result.status = outcomeToStatus(outcome)
                        result.errorMessage = message
                        result.completedAt = Date()
                        await onUpdate(result)
                        return result
                    }
                    throw error
                }

            case let .repeat(block):
                var nested: [BlockResult] = []
                var repeatFailed = false

                let nestedUpdate: (BlockResult) async -> Void = { updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                do {
                    for iteration in 0 ..< block.count {
                        if Task.isCancelled { break }
                        result.detail = "Iteration \(iteration + 1)/\(block.count)"
                        await onUpdate(result)

                        for (i, b) in block.blocks.enumerated() {
                            if Task.isCancelled { break }
                            let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                            conditionEvaluator.blockResults[b.blockId] = r.status
                            if !nested.contains(where: { $0.id == r.id }) {
                                nested.append(r)
                            }
                            if r.status == .cancelled || Task.isCancelled { break }
                            if r.status == .failure {
                                repeatFailed = true
                                if !context.automation.continueOnError { break }
                            }
                        }
                        if Task.isCancelled { break }
                        if repeatFailed && !context.automation.continueOnError { break }
                        if let delay = block.delayBetweenSeconds, iteration < block.count - 1 {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                    }
                    result.detail = "Repeated \(block.count) times"
                    result.nestedResults = nested
                    result.status = Task.isCancelled ? .cancelled : (repeatFailed ? .failure : .success)
                } catch let error as AutomationEngineError {
                    if case let .stopped(outcome, message) = error {
                        result.nestedResults = nested
                        result.detail = "Returned: \(outcome.rawValue)\(message.map { " — \($0)" } ?? "")"
                        result.status = outcomeToStatus(outcome)
                        result.errorMessage = message
                        result.completedAt = Date()
                        await onUpdate(result)
                        return result
                    }
                    throw error
                }

            case let .repeatWhile(block):
                var nested: [BlockResult] = []
                var repeatFailed = false
                var iterations = 0

                let nestedUpdate: (BlockResult) async -> Void = { updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                do {
                    while iterations < block.maxIterations {
                        if Task.isCancelled { break }
                        let condResult = await conditionEvaluator.evaluate(block.condition)
                        guard condResult.passed else { break }

                        result.detail = "Iteration \(iterations + 1)"
                        await onUpdate(result)

                        for (i, b) in block.blocks.enumerated() {
                            if Task.isCancelled { break }
                            let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                            conditionEvaluator.blockResults[b.blockId] = r.status
                            if !nested.contains(where: { $0.id == r.id }) {
                                nested.append(r)
                            }
                            if r.status == .cancelled || Task.isCancelled { break }
                            if r.status == .failure {
                                repeatFailed = true
                                if !context.automation.continueOnError { break }
                            }
                        }
                        if Task.isCancelled { break }
                        if repeatFailed && !context.automation.continueOnError { break }

                        iterations += 1
                        if let delay = block.delayBetweenSeconds {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                    }
                    result.detail = "Repeated \(iterations) times (max: \(block.maxIterations))"
                    result.nestedResults = nested
                    result.status = Task.isCancelled ? .cancelled : (repeatFailed ? .failure : .success)
                } catch let error as AutomationEngineError {
                    if case let .stopped(outcome, message) = error {
                        result.nestedResults = nested
                        result.detail = "Returned: \(outcome.rawValue)\(message.map { " — \($0)" } ?? "")"
                        result.status = outcomeToStatus(outcome)
                        result.errorMessage = message
                        result.completedAt = Date()
                        await onUpdate(result)
                        return result
                    }
                    throw error
                }

            case let .group(block):
                var nested: [BlockResult] = []
                var groupFailed = false

                let nestedUpdate: (BlockResult) async -> Void = { updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                do {
                    for (i, b) in block.blocks.enumerated() {
                        if Task.isCancelled { break }
                        let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                        conditionEvaluator.blockResults[b.blockId] = r.status
                        if !nested.contains(where: { $0.id == r.id }) {
                            nested.append(r)
                        }
                        if r.status == .cancelled || Task.isCancelled { break }
                        if r.status == .failure {
                            groupFailed = true
                            if !context.automation.continueOnError { break }
                        }
                    }
                    result.detail = block.label ?? "Group"
                    result.nestedResults = nested
                    result.status = Task.isCancelled ? .cancelled : (groupFailed ? .failure : .success)
                } catch let error as AutomationEngineError {
                    if case let .stopped(outcome, message) = error {
                        result.nestedResults = nested
                        result.detail = "Returned: \(outcome.rawValue)\(message.map { " — \($0)" } ?? "")"
                        result.status = outcomeToStatus(outcome)
                        result.errorMessage = message
                        result.completedAt = Date()
                        await onUpdate(result)
                        return result
                    }
                    throw error
                }

            case let .stop(block):
                let msgSuffix = block.message.flatMap { $0.isEmpty ? nil : " — \($0)" } ?? ""
                let outcomeLabel: String = {
                    switch block.outcome {
                    case .success: return "success"
                    case .error: return "error"
                    case .cancelled: return "cancelled"
                    }
                }()
                result.detail = "Stopped with \(outcomeLabel)\(msgSuffix)"
                result.status = .success
                result.completedAt = Date()
                await onUpdate(result)
                throw AutomationEngineError.stopped(outcome: block.outcome, message: block.message)

            case let .executeAutomation(block):
                // Check for circular calls
                if context.callingAutomationIds.contains(block.targetAutomationId) {
                    let targetName = await resolveAutomationName(block.targetAutomationId)
                    result.status = .failure
                    result.errorMessage = "Circular automation call detected: '\(targetName)'"
                    result.completedAt = Date()
                    await onUpdate(result)
                    return result
                }

                guard let targetAutomation = await automationStorageService.getAutomation(id: block.targetAutomationId) else {
                    result.status = .failure
                    result.errorMessage = "Target automation not found"
                    result.completedAt = Date()
                    await onUpdate(result)
                    return result
                }

                // Verify target has a .automation trigger
                let hasAutomationTrigger = targetAutomation.triggers.contains {
                    if case .automation = $0 { return true }; return false
                }
                guard hasAutomationTrigger else {
                    result.status = .failure
                    result.errorMessage = "Target automation '\(targetAutomation.name)' does not accept automation triggers"
                    result.completedAt = Date()
                    await onUpdate(result)
                    return result
                }

                let triggerEvent = TriggerEvent(
                    deviceId: nil, deviceName: nil, serviceName: nil,
                    characteristicName: nil, roomName: nil, oldValue: nil, newValue: nil,
                    triggerDescription: "Called from automation '\(context.automation.name)'"
                )

                // Build caller context with updated calling chain
                var callerContext = context
                callerContext.callingAutomationIds.insert(context.automation.id)

                switch block.executionMode {
                case .inline:
                    result.detail = "Executing '\(targetAutomation.name)' inline..."
                    await onUpdate(result)

                    // Track parent → child relationship for cascading cancellation
                    let parentId = context.automation.id
                    let childId = targetAutomation.id
                    if inlineChildren[parentId] == nil {
                        inlineChildren[parentId] = []
                    }
                    inlineChildren[parentId]?.insert(childId)

                    let targetLog = await triggerAutomation(id: childId, triggerEvent: triggerEvent, callerContext: callerContext)

                    // Clean up parent → child tracking
                    inlineChildren[parentId]?.remove(childId)
                    if inlineChildren[parentId]?.isEmpty == true {
                        inlineChildren.removeValue(forKey: parentId)
                    }

                    if let log = targetLog {
                        result.detail = "Executed '\(targetAutomation.name)': \(log.status.rawValue)"
                        result.status = (log.status == .success) ? .success : .failure
                        if log.status != .success {
                            result.errorMessage = log.errorMessage ?? "Target automation \(log.status.rawValue)"
                        }
                    } else {
                        result.detail = "'\(targetAutomation.name)' skipped (retrigger policy)"
                        result.status = .success
                    }

                case .parallel:
                    result.detail = "Launched '\(targetAutomation.name)' in parallel"
                    Task { [weak self] in
                        _ = await self?.triggerAutomation(id: targetAutomation.id, triggerEvent: triggerEvent, callerContext: callerContext)
                    }
                    result.status = .success

                case .delegate:
                    result.detail = "Delegating to '\(targetAutomation.name)'"
                    result.status = .success
                    result.completedAt = Date()
                    await onUpdate(result)
                    Task { [weak self] in
                        _ = await self?.triggerAutomation(id: targetAutomation.id, triggerEvent: triggerEvent, callerContext: callerContext)
                    }
                    throw AutomationEngineError.stopped(outcome: .success, message: "Delegated to '\(targetAutomation.name)'")
                }
            }
        } catch is CancellationError {
            result.status = .cancelled
        } catch {
            // Re-throw return errors so they propagate to the parent scope
            if let engineError = error as? AutomationEngineError,
               case .stopped = engineError {
                throw engineError
            }
            result.status = .failure
            result.errorMessage = error.localizedDescription
        }

        result.completedAt = Date()
        await onUpdate(result)
        return result
    }

    // MARK: - Helpers

    private func outcomeToStatus(_ outcome: StopOutcome) -> ExecutionStatus {
        switch outcome {
        case .success: return .success
        case .error: return .failure
        case .cancelled: return .cancelled
        }
    }

    private func resolveDeviceName(_ deviceId: String) async -> String {
        // Use getDeviceState which resolves both stable registry IDs and HomeKit UUIDs
        let device = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        if let device {
            if let room = device.roomName, !room.isEmpty {
                return "\(room) \(device.name)"
            }
            return device.name
        }
        return deviceId
    }

    private func resolveServiceDisplayName(deviceId: String, serviceId: String?) async -> String? {
        guard let serviceId else { return nil }
        let device = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        guard let device else { return nil }
        let resolvedId = registry?.readHomeKitServiceId(serviceId) ?? serviceId
        return device.services.first(where: { $0.id == resolvedId })?.displayName
    }

    private func resolveAutomationName(_ automationId: UUID) async -> String {
        if let automation = await automationStorageService.getAutomation(id: automationId) {
            return automation.name
        }
        return automationId.uuidString
    }

    // MARK: - Orphan Logging

    private func logOrphan(automationId: UUID, automationName: String, location: String) async {
        // Orphan details are captured in the AutomationExecutionLog's block results.
        AppLogger.automation.warning("[\(automationName)] Orphaned reference in \(location): unknown device")
    }

    // MARK: - WaitForState

    /// Build a human-readable description of a waitForState block's condition.
    private func waitForStateDescription(_ block: WaitForStateBlock) -> String {
        switch block.condition {
        case .deviceState(let c):
            let resolvedType = registry?.readCharacteristicType(forStableId: c.characteristicId) ?? c.characteristicId
            let charName = CharacteristicTypes.displayName(for: resolvedType)
            return "condition on \(charName)"
        case .and(let conditions):
            return "\(conditions.count) conditions (AND)"
        case .or(let conditions):
            return "\(conditions.count) conditions (OR)"
        case .not:
            return "negated condition"
        default:
            return "condition"
        }
    }

    /// Extract all `deviceId:characteristicType` keys from a AutomationCondition for waiter registration.
    private func extractWaiterKeys(from condition: AutomationCondition) -> Set<String> {
        var keys = Set<String>()
        collectWaiterKeys(condition, into: &keys)
        return keys
    }

    private func collectWaiterKeys(_ condition: AutomationCondition, into keys: inout Set<String>) {
        switch condition {
        case .deviceState(let c):
            let resolvedType = registry?.readCharacteristicType(forStableId: c.characteristicId)
                ?? CharacteristicTypes.characteristicType(forName: c.characteristicId)
                ?? c.characteristicId
            keys.insert("\(c.deviceId):\(resolvedType)")
        case .and(let conditions):
            for c in conditions { collectWaiterKeys(c, into: &keys) }
        case .or(let conditions):
            for c in conditions { collectWaiterKeys(c, into: &keys) }
        case .not(let inner):
            collectWaiterKeys(inner, into: &keys)
        default:
            break // timeCondition, sceneActive, blockResult don't need waiters
        }
    }

    private func waitForState(_ block: WaitForStateBlock, automationId: UUID, automationName: String, onProgress: ((Double) async -> Void)? = nil) async throws -> Bool {
        let keys = extractWaiterKeys(from: block.condition)

        // Check if condition is already met
        conditionEvaluator.automationId = automationId
        conditionEvaluator.automationName = automationName
        let initialResult = await conditionEvaluator.evaluate(block.condition)
        if initialResult.passed {
            return true
        }

        guard !keys.isEmpty else {
            // No device state refs in condition — poll periodically until timeout
            AppLogger.automation.info("[\(automationName)] waitForState has no device state keys — polling every 2s until timeout (\(block.timeoutSeconds)s)")
            let deadline = Date().addingTimeInterval(block.timeoutSeconds)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return false }
                let retryResult = await conditionEvaluator.evaluate(block.condition)
                if retryResult.passed { return true }
                let elapsed = block.timeoutSeconds - deadline.timeIntervalSinceNow
                await onProgress?(elapsed)
            }
            return false
        }

        // Start time for progress tracking
        let startTime = Date()

        // Pre-generate waiter ID so the cancellation handler can reference it
        let waiterId = UUID()
        let firstKey = keys.first!
        var progressTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?

        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                let waiter = StateWaiter(
                    id: waiterId,
                    keys: keys,
                    condition: block.condition,
                    continuation: continuation
                )

                // Register waiter under all relevant device+characteristic keys
                for key in keys {
                    if stateWaiters[key] == nil {
                        stateWaiters[key] = []
                    }
                    stateWaiters[key]?.append(waiter)
                }

                // Progress reporting task
                progressTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        if !Task.isCancelled {
                            let elapsedSeconds = Date().timeIntervalSince(startTime)
                            await onProgress?(elapsedSeconds)
                        }
                    }
                }

                // Timeout task (stored so it can be cancelled)
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(block.timeoutSeconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await self?.timeoutWaiter(waiter, key: firstKey)
                }
            }
        } onCancel: { [weak self] in
            // Runs on arbitrary thread — dispatch to actor for safe stateWaiters access
            Task { [weak self] in
                await self?.cancelWaiter(id: waiterId, key: firstKey)
            }
        }

        // Stop progress and timeout now that the wait resolved
        progressTask?.cancel()
        timeoutTask?.cancel()

        return result
    }

    private func notifyStateWaiters(_ change: StateChange) async {
        let key = "\(change.deviceId):\(change.characteristicType)"
        guard let waiters = stateWaiters[key], !waiters.isEmpty else { return }

        var resolvedWaiterIds = Set<UUID>()
        for waiter in waiters {
            let result = await conditionEvaluator.evaluate(waiter.condition)
            if result.passed {
                resolvedWaiterIds.insert(waiter.id)
                // Remove from ALL keys before resuming
                removeWaiter(id: waiter.id, keys: waiter.keys)
                waiter.continuation.resume(returning: true)
            }
        }
    }

    /// Remove a waiter from all its registered keys.
    private func removeWaiter(id: UUID, keys: Set<String>) {
        for key in keys {
            guard var waiters = stateWaiters[key] else { continue }
            waiters.removeAll { $0.id == id }
            stateWaiters[key] = waiters.isEmpty ? nil : waiters
        }
    }

    private func timeoutWaiter(_ waiter: StateWaiter, key: String) {
        // Check if waiter still exists (may have been resolved already)
        guard let waiters = stateWaiters[key], waiters.contains(where: { $0.id == waiter.id }) else { return }
        removeWaiter(id: waiter.id, keys: waiter.keys)
        waiter.continuation.resume(returning: false)
    }

    /// Cancel a waiter due to task cancellation. Actor-isolated so access to
    /// `stateWaiters` is safe. If the waiter was already removed by
    /// `notifyStateWaiters` or `timeoutWaiter`, this is a no-op (no double-resume).
    private func cancelWaiter(id: UUID, key: String) {
        // Find the waiter in any key to get its full key set
        guard let waiters = stateWaiters[key], let waiter = waiters.first(where: { $0.id == id }) else { return }
        removeWaiter(id: id, keys: waiter.keys)
        waiter.continuation.resume(throwing: CancellationError())
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

    // MARK: - Timeout Helper

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AutomationEngineError.timeout
            }
            guard let result = try await group.next() else {
                throw AutomationEngineError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

private struct ExecutionContext {
    let automation: Automation
    var callingAutomationIds: Set<UUID> = []
    var blockResults: [UUID: ExecutionStatus] = [:]
}

private struct StateWaiter {
    let id: UUID
    /// All device+characteristic keys this waiter is registered under.
    let keys: Set<String>
    let condition: AutomationCondition
    let continuation: CheckedContinuation<Bool, Error>
}

enum AutomationEngineError: LocalizedError {
    case timeout
    case invalidURL(String)
    case webhookFailed(statusCode: Int)
    case ssrfBlocked(String)
    case stopped(outcome: StopOutcome, message: String?)
    case stateVariableError(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Operation timed out"
        case let .invalidURL(url): return "Invalid URL: \(url)"
        case let .webhookFailed(code): return "Webhook failed with status \(code)"
        case let .ssrfBlocked(url): return "Request blocked: URL '\(url)' resolves to a private/internal IP address"
        case let .stopped(outcome, message): return "Return (\(outcome.rawValue))\(message.map { ": \($0)" } ?? "")"
        case let .stateVariableError(msg): return "State variable error: \(msg)"
        }
    }
}
