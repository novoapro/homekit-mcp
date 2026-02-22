import Foundation
import Combine

/// Core workflow engine that evaluates triggers, checks conditions, and executes blocks.
actor WorkflowEngine: WorkflowEngineProtocol {
    private let workflowStorageService: WorkflowStorageService
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let executionLogService: WorkflowExecutionLogService
    private let storage: StorageService
    private var conditionEvaluator: ConditionEvaluator
    private var evaluators: [TriggerEvaluator] = []

    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    /// Maps execution log ID → workflow ID so we can cancel by execution ID.
    private var executionToWorkflow: [UUID: UUID] = [:]
    /// Tracks parent → children workflow IDs for inline executions,
    /// so cancelling a parent also cancels its inline children.
    private var inlineChildren: [UUID: Set<UUID>] = [:]
    /// Maximum number of workflows executing concurrently. When the limit is reached,
    /// additional triggered workflows are evaluated and then queued (not dropped).
    private let maxConcurrentExecutions = 20
    private let blockTimeout: TimeInterval = 30

    // MARK: - Pending Queue

    /// A queued workflow waiting for a free execution slot.
    private struct PendingEntry {
        let workflow: Workflow
        let change: StateChange?
        let triggerEvent: TriggerEvent?
        let queuedAt: Date
    }

    /// FIFO queue of workflows that have triggered but cannot run yet because
    /// all `maxConcurrentExecutions` slots are occupied.
    private var pendingQueue: [PendingEntry] = []

    /// Maximum number of entries that can wait in the pending queue.
    /// Entries beyond this limit are logged and discarded.
    private let maxPendingQueueSize = 50

    /// Maximum time (seconds) a workflow may wait in the pending queue.
    /// Stale entries are logged and discarded when the queue is drained.
    private let pendingQueueStalenessTimeout: TimeInterval = 60

    /// Waiters for `waitForState` blocks — keyed by device+characteristic.
    private var stateWaiters: [String: [StateWaiter]] = [:]

    /// Retains the Combine subscription to HomeKitManager's stateChangePublisher.
    /// Stored as AnyCancellable so it lives as long as the engine.
    nonisolated private let cancellableBag = CancellableBag()

    init(
        storageService: WorkflowStorageService,
        homeKitManager: HomeKitManager,
        loggingService: LoggingService,
        executionLogService: WorkflowExecutionLogService,
        storage: StorageService,
        conditionEvaluator: ConditionEvaluator? = nil
    ) {
        workflowStorageService = storageService
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.executionLogService = executionLogService
        self.storage = storage
        self.conditionEvaluator = conditionEvaluator ?? ConditionEvaluator(homeKitManager: homeKitManager, storage: storage, loggingService: loggingService)
    }

    /// Wire up the one-directional subscription to HomeKitManager's state changes.
    /// Called once by ServiceContainer after both objects are created.
    /// HomeKitManager publishes → WorkflowEngine.processStateChange() is called.
    /// No reference to WorkflowEngine is stored in HomeKitManager.
    nonisolated func subscribeToStateChanges(from publisher: PassthroughSubject<StateChange, Never>) {
        let cancellable = publisher
            .sink { [weak self] change in
                guard let self else { return }
                Task { await self.processStateChange(change) }
            }
        cancellableBag.store(cancellable)
    }

    func registerEvaluator(_ evaluator: TriggerEvaluator) {
        evaluators.append(evaluator)
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
    func processStateChange(_ change: StateChange) async {
        guard storage.readWorkflowsEnabled() else { return }

        // Notify any waitForState waiters first
        notifyStateWaiters(change)

        let workflows = await workflowStorageService.getEnabledWorkflows()
        let context = TriggerContext.stateChange(change)

        for workflow in workflows {
            // Evaluate ALL workflows regardless of slot availability —
            // previously used `break` which silently skipped unevaluated workflows.
            let triggered = await checkTriggers(workflow.triggers, context: context)
            guard triggered else { continue }

            // Already running?
            if let existingTask = runningTasks[workflow.id] {
                switch workflow.retriggerPolicy {
                case .ignoreNew:
                    AppLogger.workflow.debug("[\(workflow.name)] Ignoring new trigger — workflow already running (ignoreNew policy)")
                    continue
                case .cancelAndRestart:
                    AppLogger.workflow.debug("[\(workflow.name)] Cancelling running execution — restarting (cancelAndRestart policy)")
                    existingTask.cancel()
                    runningTasks.removeValue(forKey: workflow.id)
                case .queueAndExecute:
                    enqueueWorkflow(workflow, change: change)
                    continue
                }
            }

            startExecution(workflow, change: change)
        }
    }

    /// Manual trigger for testing.
    func triggerWorkflow(id: UUID) async -> WorkflowExecutionLog? {
        guard storage.readWorkflowsEnabled() else { return nil }
        guard let workflow = await workflowStorageService.getWorkflow(id: id) else { return nil }

        // Handle retrigger policy for manual trigger too
        if let existingTask = runningTasks[id] {
            switch workflow.retriggerPolicy {
            case .ignoreNew:
                return nil
            case .cancelAndRestart:
                existingTask.cancel()
                runningTasks.removeValue(forKey: id)
            case .queueAndExecute:
                enqueueWorkflow(workflow, change: nil)
                return nil
            }
        }

        let task = Task { [weak self] () -> WorkflowExecutionLog in
            let result = await self?.executeWorkflow(workflow, change: nil) ?? WorkflowExecutionLog(workflowId: id, workflowName: workflow.name, triggerEvent: nil)
            await self?.removeRunning(id)
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

    /// Trigger a workflow from a schedule or webhook with a custom trigger event.
    func triggerWorkflow(id: UUID, triggerEvent: TriggerEvent) async -> WorkflowExecutionLog? {
        guard storage.readWorkflowsEnabled() else { return nil }
        guard let workflow = await workflowStorageService.getWorkflow(id: id) else { return nil }
        guard workflow.isEnabled else { return nil }

        if let existingTask = runningTasks[id] {
            switch workflow.retriggerPolicy {
            case .ignoreNew:
                return nil
            case .cancelAndRestart:
                existingTask.cancel()
                runningTasks.removeValue(forKey: id)
            case .queueAndExecute:
                enqueueWorkflow(workflow, change: nil)
                return nil
            }
        }

        let task = Task { [weak self] () -> WorkflowExecutionLog in
            let result = await self?.executeWorkflow(workflow, change: nil, triggerEvent: triggerEvent) ?? WorkflowExecutionLog(workflowId: id, workflowName: workflow.name, triggerEvent: triggerEvent)
            await self?.removeRunning(id)
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
        guard storage.readWorkflowsEnabled() else { return .disabled }
        guard let workflow = await workflowStorageService.getWorkflow(id: id) else { return .notFound }

        if runningTasks[id] != nil {
            switch workflow.retriggerPolicy {
            case .ignoreNew:
                return .ignored(workflowId: id, workflowName: workflow.name)
            case .cancelAndRestart:
                runningTasks[id]?.cancel()
                runningTasks.removeValue(forKey: id)
                startExecution(workflow, change: nil)
                return .replaced(workflowId: id, workflowName: workflow.name)
            case .queueAndExecute:
                enqueueWorkflow(workflow, change: nil)
                return .queued(workflowId: id, workflowName: workflow.name)
            }
        }

        startExecution(workflow, change: nil)
        return .scheduled(workflowId: id, workflowName: workflow.name)
    }

    /// Fire-and-forget trigger with a custom event — returns immediately with the scheduling outcome.
    func scheduleTrigger(id: UUID, triggerEvent: TriggerEvent) async -> TriggerResult {
        guard storage.readWorkflowsEnabled() else { return .disabled }
        guard let workflow = await workflowStorageService.getWorkflow(id: id) else { return .notFound }
        guard workflow.isEnabled else { return .workflowDisabled(workflowId: id, workflowName: workflow.name) }

        if runningTasks[id] != nil {
            switch workflow.retriggerPolicy {
            case .ignoreNew:
                return .ignored(workflowId: id, workflowName: workflow.name)
            case .cancelAndRestart:
                runningTasks[id]?.cancel()
                runningTasks.removeValue(forKey: id)
                startExecution(workflow, change: nil, triggerEvent: triggerEvent)
                return .replaced(workflowId: id, workflowName: workflow.name)
            case .queueAndExecute:
                enqueueWorkflow(workflow, change: nil, triggerEvent: triggerEvent)
                return .queued(workflowId: id, workflowName: workflow.name)
            }
        }

        startExecution(workflow, change: nil, triggerEvent: triggerEvent)
        return .scheduled(workflowId: id, workflowName: workflow.name)
    }

    /// Internal trigger used by the Execute Workflow block — carries caller context for circular call detection.
    private func triggerWorkflow(id: UUID, triggerEvent: TriggerEvent, callerContext: ExecutionContext) async -> WorkflowExecutionLog? {
        guard let workflow = await workflowStorageService.getWorkflow(id: id) else { return nil }
        guard workflow.isEnabled else { return nil }

        // Check circular call before anything else
        if callerContext.callingWorkflowIds.contains(id) {
            AppLogger.workflow.warning("[\(workflow.name)] Circular workflow call detected — aborting")
            return nil
        }

        if let existingTask = runningTasks[id] {
            switch workflow.retriggerPolicy {
            case .ignoreNew:
                return nil
            case .cancelAndRestart:
                existingTask.cancel()
                runningTasks.removeValue(forKey: id)
            case .queueAndExecute:
                enqueueWorkflow(workflow, change: nil)
                return nil
            }
        }

        var context = ExecutionContext(workflow: workflow, callingWorkflowIds: callerContext.callingWorkflowIds)
        context.callingWorkflowIds.insert(callerContext.workflow.id)

        let task = Task { [weak self] () -> WorkflowExecutionLog in
            let result = await self?.executeWorkflow(workflow, change: nil, triggerEvent: triggerEvent, callerContext: context) ?? WorkflowExecutionLog(workflowId: id, workflowName: workflow.name, triggerEvent: triggerEvent)
            await self?.removeRunning(id)
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
        guard let workflowId = executionToWorkflow[executionId] else { return }
        AppLogger.workflow.info("Cancelling execution \(executionId) for workflow \(workflowId)")
        cancelWorkflowTree(workflowId)
    }

    /// Cancel all running executions for a specific workflow.
    func cancelRunningExecutions(forWorkflow workflowId: UUID) {
        AppLogger.workflow.info("Cancelling running execution for workflow \(workflowId)")
        cancelWorkflowTree(workflowId)
        // Also remove any pending queue entries for this workflow
        pendingQueue.removeAll { $0.workflow.id == workflowId }
    }

    /// Recursively cancel a workflow and all its inline children.
    private func cancelWorkflowTree(_ workflowId: UUID) {
        // Cancel inline children first (depth-first)
        if let children = inlineChildren[workflowId] {
            for childId in children {
                cancelWorkflowTree(childId)
            }
        }
        // Cancel this workflow's task
        runningTasks[workflowId]?.cancel()
    }

    // MARK: - Execution Slot Management

    /// Attempt to immediately start a workflow, or queue it if no slots are available.
    private func startExecution(_ workflow: Workflow, change: StateChange?, triggerEvent: TriggerEvent? = nil) {
        guard runningTasks.count < maxConcurrentExecutions else {
            enqueueWorkflow(workflow, change: change, triggerEvent: triggerEvent)
            return
        }
        let workflowId = workflow.id
        let task = Task { [weak self] in
            await self?.executeWorkflow(workflow, change: change, triggerEvent: triggerEvent)
            await self?.removeRunning(workflowId)
        }
        runningTasks[workflowId] = task
    }

    /// Add a workflow to the pending FIFO queue, respecting the max queue size.
    /// Only one pending entry per workflow — duplicate triggers are ignored.
    private func enqueueWorkflow(_ workflow: Workflow, change: StateChange?, triggerEvent: TriggerEvent? = nil) {
        if pendingQueue.contains(where: { $0.workflow.id == workflow.id }) {
            AppLogger.workflow.debug("[\(workflow.name)] Already queued, skipping duplicate trigger")
            return
        }
        let maxSize = maxPendingQueueSize
        guard pendingQueue.count < maxSize else {
            AppLogger.workflow.warning("[\(workflow.name)] Pending queue full (\(maxSize)). Discarding trigger.")
            return
        }
        let slots = runningTasks.count
        let maxSlots = maxConcurrentExecutions
        let pending = pendingQueue.count + 1
        AppLogger.workflow.info("[\(workflow.name)] Queued (slots: \(slots)/\(maxSlots), pending: \(pending))")
        pendingQueue.append(PendingEntry(workflow: workflow, change: change, triggerEvent: triggerEvent, queuedAt: Date()))
    }

    /// Called when a workflow completes. Frees the slot and drains the pending queue.
    private func removeRunning(_ id: UUID) {
        runningTasks.removeValue(forKey: id)
        drainPendingQueue()
    }

    /// Drain queued workflows into available execution slots.
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
                AppLogger.workflow.warning("[\(entry.workflow.name)] Discarding stale queued trigger (waited \(waited)s > \(limit)s limit)")
                continue
            }

            let waitStr = String(format: "%.1f", waitTime)
            AppLogger.workflow.info("[\(entry.workflow.name)] Dequeued after \(waitStr)s — starting execution")
            startExecution(entry.workflow, change: entry.change, triggerEvent: entry.triggerEvent)
        }
    }

    // MARK: - Trigger Evaluation

    private func checkTriggers(_ triggers: [WorkflowTrigger], context: TriggerContext) async -> Bool {
        for trigger in triggers {
            for evaluator in evaluators {
                if evaluator.canEvaluate(trigger) {
                    if await evaluator.evaluate(trigger, context: context) {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Workflow Execution

    @discardableResult
    private func executeWorkflow(_ workflow: Workflow, change: StateChange?, triggerEvent: TriggerEvent? = nil, callerContext: ExecutionContext? = nil) async -> WorkflowExecutionLog {
        let event = triggerEvent ?? change.map { c -> TriggerEvent in
            let charName = CharacteristicTypes.displayName(for: c.characteristicType)
            let desc = "\(c.deviceName) \(charName) changed"
            return TriggerEvent(
                deviceId: c.deviceId,
                deviceName: c.deviceName,
                serviceId: c.serviceId,
                characteristicType: c.characteristicType,
                oldValue: c.oldValue.map { AnyCodable($0) },
                newValue: c.newValue.map { AnyCodable($0) },
                triggerDescription: desc
            )
        }
        var execLog = WorkflowExecutionLog(
            workflowId: workflow.id,
            workflowName: workflow.name,
            triggerEvent: event
        )

        // Track execution → workflow mapping for cancellation by execution ID
        executionToWorkflow[execLog.id] = workflow.id

        // Log immediately as running so it appears in the UI
        await executionLogService.log(execLog)

        // Set workflow context for orphan logging
        conditionEvaluator.workflowId = workflow.id
        conditionEvaluator.workflowName = workflow.name

        // Evaluate guard conditions
        if let conditions = workflow.conditions, !conditions.isEmpty {
            let (allPassed, condResults) = await conditionEvaluator.evaluateAll(conditions)
            execLog.conditionResults = condResults
            await executionLogService.update(execLog)

            if !allPassed {
                execLog.status = .conditionNotMet
                execLog.completedAt = Date()
                await finalizeExecution(execLog, workflow: workflow, succeeded: false)
                return execLog
            }
        }

        // Create a reference box so the @Sendable closure can mutate the log
        class LogBox {
            var execLog: WorkflowExecutionLog
            init(_ log: WorkflowExecutionLog) {
                execLog = log
            }
        }
        let logBox = LogBox(execLog)

        // Execute blocks in order, updating log after each step
        var context = ExecutionContext(workflow: workflow, callingWorkflowIds: callerContext?.callingWorkflowIds ?? [])
        var failed = false

        let onUpdate: @Sendable (BlockResult) async -> Void = { [weak self] updated in
            guard let self = self else { return }
            // Try to update an existing block in the results tree
            if !self.updateBlockResult(updated, in: &logBox.execLog.blockResults) {
                // Block not yet in the array — append it so the UI can show it immediately
                logBox.execLog.blockResults.append(updated)
            }
            await self.executionLogService.update(logBox.execLog)
        }

        do {
            for (index, block) in workflow.blocks.enumerated() {
                if Task.isCancelled {
                    logBox.execLog.status = .cancelled
                    logBox.execLog.completedAt = Date()
                    await finalizeExecution(logBox.execLog, workflow: workflow, succeeded: false)
                    return logBox.execLog
                }

                let result = try await executeBlock(block, index: index, context: context, onUpdate: onUpdate)

                // Note: executeBlock already calls onUpdate for progress and completion,
                // but we append it here if it wasn't already in the top-level list.
                if !logBox.execLog.blockResults.contains(where: { $0.id == result.id }) {
                    logBox.execLog.blockResults.append(result)
                    await executionLogService.update(logBox.execLog)
                }

                if result.status == .failure {
                    failed = true
                    if !workflow.continueOnError {
                        break
                    }
                }
            }
        } catch let error as WorkflowEngineError {
            if case let .stopped(outcome, message) = error {
                logBox.execLog.status = switch outcome {
                case .success: .success
                case .error: .failure
                case .cancelled: .cancelled
                }
                logBox.execLog.errorMessage = message
                logBox.execLog.completedAt = Date()
                await finalizeExecution(logBox.execLog, workflow: workflow, succeeded: outcome == .success)
                return logBox.execLog
            }
        } catch {}

        // Check for cancellation after the loop — don't overwrite with failure/success
        if Task.isCancelled {
            logBox.execLog.status = .cancelled
            logBox.execLog.completedAt = Date()
            await finalizeExecution(logBox.execLog, workflow: workflow, succeeded: false)
            return logBox.execLog
        }

        logBox.execLog.status = failed ? .failure : .success
        logBox.execLog.completedAt = Date()
        logBox.execLog.errorMessage = failed ? logBox.execLog.blockResults.first(where: { $0.status == .failure })?.errorMessage : nil

        await finalizeExecution(logBox.execLog, workflow: workflow, succeeded: !failed)
        return logBox.execLog
    }

    private func finalizeExecution(_ execLog: WorkflowExecutionLog, workflow: Workflow, succeeded: Bool) async {
        // Clean up execution → workflow mapping
        executionToWorkflow.removeValue(forKey: execLog.id)

        // Update the existing running log entry with the final result
        await executionLogService.update(execLog)

        // Update workflow metadata
        await workflowStorageService.updateMetadata(
            id: workflow.id,
            lastTriggered: execLog.triggeredAt,
            incrementExecutions: true,
            resetFailures: succeeded
        )

        if !succeeded, execLog.status != .conditionNotMet, execLog.status != .cancelled {
            await workflowStorageService.incrementFailures(id: workflow.id)
        }

        // Build rich log entry for main logging service
        let category: LogCategory = (succeeded || execLog.status == .cancelled) ? .workflowExecution : .workflowError
        let durationMs: Int = {
            guard let completed = execLog.completedAt else { return 0 }
            return Int(completed.timeIntervalSince(execLog.triggeredAt) * 1000)
        }()

        // requestBody: trigger description
        let requestBody: String = {
            if let trigger = execLog.triggerEvent, let desc = trigger.triggerDescription {
                return desc
            } else if let trigger = execLog.triggerEvent, let deviceName = trigger.deviceName {
                let charName = trigger.characteristicType.map { CharacteristicTypes.displayName(for: $0) } ?? ""
                let oldStr = trigger.oldValue.map { stringFromAny($0.value) } ?? "?"
                let newStr = trigger.newValue.map { stringFromAny($0.value) } ?? "?"
                return "\(deviceName) \(charName): \(oldStr) → \(newStr)"
            } else {
                return "Manual trigger"
            }
        }()

        // responseBody: sequential summary of what happened
        let responseBody: String = {
            var lines: [String] = []
            func summarizeResults(_ results: [BlockResult], depth: Int = 0) {
                let indent = String(repeating: "  ", count: depth)
                for r in results {
                    let icon = r.status == .success ? "✓" : (r.status == .failure ? "✗" : "–")
                    let name = r.blockName ?? r.blockType
                    if let detail = r.detail, !detail.isEmpty {
                        lines.append("\(indent)\(icon) \(name): \(detail)")
                    } else {
                        lines.append("\(indent)\(icon) \(name)")
                    }
                    if let nested = r.nestedResults, !nested.isEmpty {
                        summarizeResults(nested, depth: depth + 1)
                    }
                }
            }
            summarizeResults(execLog.blockResults)
            if lines.isEmpty {
                lines.append("\(execLog.status.rawValue) in \(durationMs)ms")
            }
            return lines.joined(separator: "\n")
        }()

        // Detailed logs (gated by setting)
        var detailedRequest: String?
        var detailedResponse: String?
        if storage.readDetailedLogsEnabled() {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            // Detailed request: trigger event + condition results
            var detailedReqDict: [String: AnyCodable] = [:]
            if let trigger = execLog.triggerEvent {
                var triggerDict: [String: AnyCodable] = [
                    "oldValue": trigger.oldValue ?? AnyCodable("nil"),
                    "newValue": trigger.newValue ?? AnyCodable("nil"),
                ]
                if let deviceId = trigger.deviceId { triggerDict["deviceId"] = AnyCodable(deviceId) }
                if let deviceName = trigger.deviceName { triggerDict["deviceName"] = AnyCodable(deviceName) }
                if let characteristicType = trigger.characteristicType { triggerDict["characteristicType"] = AnyCodable(characteristicType) }
                if let triggerDescription = trigger.triggerDescription { triggerDict["triggerDescription"] = AnyCodable(triggerDescription) }
                detailedReqDict["trigger"] = AnyCodable(triggerDict)
            }
            if let condResults = execLog.conditionResults {
                detailedReqDict["conditions"] = AnyCodable(condResults.map { AnyCodable(["description": AnyCodable($0.conditionDescription), "passed": AnyCodable($0.passed)] as [String: AnyCodable]) })
            }
            if let data = try? encoder.encode(detailedReqDict), let json = String(data: data, encoding: .utf8) {
                detailedRequest = json
            }

            // Detailed response: full block results tree
            if let data = try? encoder.encode(execLog.blockResults), let json = String(data: data, encoding: .utf8) {
                detailedResponse = json
            }
        }

        let logEntry = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            deviceId: workflow.id.uuidString,
            deviceName: workflow.name,
            serviceName: execLog.triggerEvent?.deviceName,
            characteristicType: "workflow",
            oldValue: nil,
            newValue: AnyCodable(execLog.status.rawValue),
            category: category,
            errorDetails: execLog.errorMessage,
            requestBody: requestBody,
            responseBody: responseBody,
            detailedRequestBody: detailedRequest,
            detailedResponseBody: detailedResponse
        )
        await loggingService.logEntry(logEntry)
    }

    // MARK: - Block Execution (Recursive)

    /// Executes a single block. May throw `WorkflowEngineError.stopped` to halt the entire workflow.
    private func executeBlock(_ block: WorkflowBlock, index: Int, context: ExecutionContext, onUpdate: @escaping (BlockResult) async -> Void) async throws -> BlockResult {
        switch block {
        case let .action(action):
            return await executeAction(action, index: index, context: context, onUpdate: onUpdate)
        case let .flowControl(flowControl):
            return try await executeFlowControl(flowControl, index: index, context: context, onUpdate: onUpdate)
        }
    }

    // MARK: - Action Execution

    private func executeAction(_ action: WorkflowAction, index: Int, context: ExecutionContext, onUpdate: @escaping (BlockResult) async -> Void) async -> BlockResult {
        let actionName: String? = {
            switch action {
            case let .controlDevice(a): return a.name
            case let .webhook(a): return a.name
            case let .log(a): return a.name
            case let .runScene(a): return a.name
            }
        }()
        var result = BlockResult(blockIndex: index, blockKind: "action", blockType: action.displayType, blockName: actionName)

        // Notify that we are starting
        await onUpdate(result)

        do {
            try await withTimeout(seconds: blockTimeout) {
                switch action {
                case let .controlDevice(a):
                    try await self.executeControlDevice(a, workflowId: context.workflow.id, workflowName: context.workflow.name)
                    let deviceName = await self.resolveDeviceName(a.deviceId)
                    let charName = CharacteristicTypes.displayName(for: a.characteristicType)
                    result.detail = "Set \(charName) to \(a.value.value) on \(deviceName)"
                case let .webhook(a):
                    try await self.executeWebhook(a)
                    result.detail = "\(a.method) \(a.url)"
                case let .log(a):
                    AppLogger.workflow.info("Workflow log: \(a.message)")
                    result.detail = a.message
                case let .runScene(a):
                    try await self.homeKitManager.executeScene(id: a.sceneId)
                    let sceneName = await MainActor.run { self.homeKitManager.getScene(id: a.sceneId)?.name } ?? a.sceneId
                    result.detail = "Ran scene '\(sceneName)'"
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

    private func executeControlDevice(_ action: ControlDeviceAction, workflowId: UUID, workflowName: String) async throws {
        let resolvedType = CharacteristicTypes.characteristicType(forName: action.characteristicType) ?? action.characteristicType

        // Validate value against characteristic metadata
        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: action.deviceId) }
        if let device {
            let targetServices = action.serviceId != nil ? device.services.filter({ $0.id == action.serviceId }) : device.services
            if let characteristic = targetServices.flatMap(\.characteristics).first(where: { $0.type == resolvedType }) {
                try CharacteristicValidator.validate(value: action.value.value, against: characteristic)
            }
        } else {
            await logOrphan(
                workflowId: workflowId,
                workflowName: workflowName,
                location: "controlDevice block '\(action.name ?? "unnamed")'",
                deviceName: action.deviceName,
                roomName: action.roomName
            )
        }

        try await homeKitManager.updateDevice(
            id: action.deviceId,
            characteristicType: resolvedType,
            value: action.value.value,
            serviceId: action.serviceId
        )
    }

    /// Validates that a URL does not point to a private/internal IP address (SSRF protection).
    private static func validateURLNotPrivate(_ url: URL) throws {
        guard let host = url.host else { return }

        let lowered = host.lowercased()
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
                throw WorkflowEngineError.ssrfBlocked(url.absoluteString)
            }
        }
    }

    /// Headers that must not be set by user-supplied workflow configurations.
    private static let restrictedHeaders: Set<String> = [
        "host", "transfer-encoding", "content-length", "connection",
        "authorization", "cookie", "set-cookie", "proxy-authorization",
        "te", "trailer", "upgrade"
    ]

    private func executeWebhook(_ action: WebhookActionConfig) async throws {
        guard let url = URL(string: action.url) else {
            throw WorkflowEngineError.invalidURL(action.url)
        }

        try Self.validateURLNotPrivate(url)

        var request = URLRequest(url: url)
        request.httpMethod = action.method
        request.timeoutInterval = blockTimeout

        if let headers = action.headers {
            for (key, value) in headers {
                guard !Self.restrictedHeaders.contains(key.lowercased()) else { continue }
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let body = action.body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw WorkflowEngineError.webhookFailed(statusCode: httpResponse.statusCode)
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
            case let .executeWorkflow(b): return b.name
            }
        }()
        var result = BlockResult(blockIndex: index, blockKind: "flowControl", blockType: flowControl.displayType, blockName: fcName)

        // Notify that we are starting
        await onUpdate(result)

        do {
            switch flowControl {
            case let .delay(block):
                result.detail = "Waiting \(block.seconds)s..."
                await onUpdate(result)

                try await Task.sleep(nanoseconds: UInt64(block.seconds * 1_000_000_000))
                result.detail = "Delayed \(block.seconds)s"
                result.status = .success

            case let .waitForState(block):
                let waitDeviceName = await resolveDeviceName(block.deviceId)
                let waitCharName = CharacteristicTypes.displayName(for: block.characteristicType)
                result.detail = "Waiting for \(waitDeviceName) \(waitCharName)..."
                await onUpdate(result)

                let matched = try await waitForState(block, workflowId: context.workflow.id, workflowName: context.workflow.name) { [weak self] elapsedSeconds in
                    // Update parent with elapsed time while waiting
                    result.detail = "Waiting for \(waitDeviceName) \(waitCharName)... (\(String(format: "%.1f", elapsedSeconds))s)"
                    await onUpdate(result)
                }
                result.detail = matched
                    ? "Waited for \(waitDeviceName) \(waitCharName) — condition met"
                    : "Waited for \(waitDeviceName) \(waitCharName) — timed out after \(block.timeoutSeconds)s"
                result.status = matched ? .success : .failure
                if !matched {
                    result.errorMessage = "Timed out after \(block.timeoutSeconds)s"
                }

            case let .conditional(block):
                let condResult = await conditionEvaluator.evaluate(block.condition)
                result.detail = condResult.passed ? "Condition met — running Then blocks" : "Condition not met — running Else blocks"
                await onUpdate(result)

                let blocksToRun = condResult.passed ? block.thenBlocks : (block.elseBlocks ?? [])
                var nested: [BlockResult] = []
                var nestedFailed = false

                let nestedUpdate: (BlockResult) async -> Void = { [weak self] updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                for (i, b) in blocksToRun.enumerated() {
                    let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                    if !nested.contains(where: { $0.id == r.id }) {
                        nested.append(r)
                    }
                    if r.status == .failure {
                        nestedFailed = true
                        if !context.workflow.continueOnError { break }
                    }
                }
                result.nestedResults = nested
                result.status = nestedFailed ? .failure : .success

            case let .repeat(block):
                var nested: [BlockResult] = []
                var repeatFailed = false

                let nestedUpdate: (BlockResult) async -> Void = { [weak self] updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                for iteration in 0 ..< block.count {
                    result.detail = "Iteration \(iteration + 1)/\(block.count)"
                    await onUpdate(result)

                    for (i, b) in block.blocks.enumerated() {
                        let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                        if !nested.contains(where: { $0.id == r.id }) {
                            nested.append(r)
                        }
                        if r.status == .failure {
                            repeatFailed = true
                            if !context.workflow.continueOnError { break }
                        }
                    }
                    if repeatFailed && !context.workflow.continueOnError { break }
                    if let delay = block.delayBetweenSeconds, iteration < block.count - 1 {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
                result.detail = "Repeated \(block.count) times"
                result.nestedResults = nested
                result.status = repeatFailed ? .failure : .success

            case let .repeatWhile(block):
                var nested: [BlockResult] = []
                var repeatFailed = false
                var iterations = 0

                let nestedUpdate: (BlockResult) async -> Void = { [weak self] updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                while iterations < block.maxIterations {
                    let condResult = await conditionEvaluator.evaluate(block.condition)
                    guard condResult.passed else { break }

                    result.detail = "Iteration \(iterations + 1)"
                    await onUpdate(result)

                    for (i, b) in block.blocks.enumerated() {
                        let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                        if !nested.contains(where: { $0.id == r.id }) {
                            nested.append(r)
                        }
                        if r.status == .failure {
                            repeatFailed = true
                            if !context.workflow.continueOnError { break }
                        }
                    }
                    if repeatFailed && !context.workflow.continueOnError { break }

                    iterations += 1
                    if let delay = block.delayBetweenSeconds {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
                result.detail = "Repeated \(iterations) times (max: \(block.maxIterations))"
                result.nestedResults = nested
                result.status = repeatFailed ? .failure : .success

            case let .group(block):
                var nested: [BlockResult] = []
                var groupFailed = false

                let nestedUpdate: (BlockResult) async -> Void = { [weak self] updated in
                    if let index = nested.firstIndex(where: { $0.id == updated.id }) {
                        nested[index] = updated
                    } else {
                        nested.append(updated)
                    }
                    result.nestedResults = nested
                    await onUpdate(result)
                }

                for (i, b) in block.blocks.enumerated() {
                    let r = try await executeBlock(b, index: i, context: context, onUpdate: nestedUpdate)
                    if !nested.contains(where: { $0.id == r.id }) {
                        nested.append(r)
                    }
                    if r.status == .failure {
                        groupFailed = true
                        if !context.workflow.continueOnError { break }
                    }
                }
                result.detail = block.label ?? "Group"
                result.nestedResults = nested
                result.status = groupFailed ? .failure : .success

            case let .stop(block):
                result.detail = "Stopping workflow: \(block.outcome.rawValue)"
                if let msg = block.message, !msg.isEmpty {
                    result.detail! += " — \(msg)"
                }
                result.status = .success
                result.completedAt = Date()
                await onUpdate(result)
                throw WorkflowEngineError.stopped(outcome: block.outcome, message: block.message)

            case let .executeWorkflow(block):
                // Check for circular calls
                if context.callingWorkflowIds.contains(block.targetWorkflowId) {
                    let targetName = await resolveWorkflowName(block.targetWorkflowId)
                    result.status = .failure
                    result.errorMessage = "Circular workflow call detected: '\(targetName)'"
                    result.completedAt = Date()
                    await onUpdate(result)
                    return result
                }

                guard let targetWorkflow = await workflowStorageService.getWorkflow(id: block.targetWorkflowId) else {
                    result.status = .failure
                    result.errorMessage = "Target workflow not found"
                    result.completedAt = Date()
                    await onUpdate(result)
                    return result
                }

                // Verify target has a .workflow trigger
                let hasWorkflowTrigger = targetWorkflow.triggers.contains {
                    if case .workflow = $0 { return true }; return false
                }
                guard hasWorkflowTrigger else {
                    result.status = .failure
                    result.errorMessage = "Target workflow '\(targetWorkflow.name)' does not accept workflow triggers"
                    result.completedAt = Date()
                    await onUpdate(result)
                    return result
                }

                let triggerEvent = TriggerEvent(
                    deviceId: nil, deviceName: nil, serviceId: nil,
                    characteristicType: nil, oldValue: nil, newValue: nil,
                    triggerDescription: "Called from workflow '\(context.workflow.name)'"
                )

                // Build caller context with updated calling chain
                var callerContext = context
                callerContext.callingWorkflowIds.insert(context.workflow.id)

                switch block.executionMode {
                case .inline:
                    result.detail = "Executing '\(targetWorkflow.name)' inline..."
                    await onUpdate(result)

                    // Track parent → child relationship for cascading cancellation
                    let parentId = context.workflow.id
                    let childId = targetWorkflow.id
                    if inlineChildren[parentId] == nil {
                        inlineChildren[parentId] = []
                    }
                    inlineChildren[parentId]?.insert(childId)

                    let targetLog = await triggerWorkflow(id: childId, triggerEvent: triggerEvent, callerContext: callerContext)

                    // Clean up parent → child tracking
                    inlineChildren[parentId]?.remove(childId)
                    if inlineChildren[parentId]?.isEmpty == true {
                        inlineChildren.removeValue(forKey: parentId)
                    }

                    if let log = targetLog {
                        result.detail = "Executed '\(targetWorkflow.name)': \(log.status.rawValue)"
                        result.status = (log.status == .success) ? .success : .failure
                        if log.status != .success {
                            result.errorMessage = log.errorMessage ?? "Target workflow \(log.status.rawValue)"
                        }
                    } else {
                        result.detail = "'\(targetWorkflow.name)' skipped (retrigger policy)"
                        result.status = .success
                    }

                case .parallel:
                    result.detail = "Launched '\(targetWorkflow.name)' in parallel"
                    Task { [weak self] in
                        _ = await self?.triggerWorkflow(id: targetWorkflow.id, triggerEvent: triggerEvent, callerContext: callerContext)
                    }
                    result.status = .success

                case .delegate:
                    result.detail = "Delegating to '\(targetWorkflow.name)'"
                    result.status = .success
                    result.completedAt = Date()
                    await onUpdate(result)
                    Task { [weak self] in
                        _ = await self?.triggerWorkflow(id: targetWorkflow.id, triggerEvent: triggerEvent, callerContext: callerContext)
                    }
                    throw WorkflowEngineError.stopped(outcome: .success, message: "Delegated to '\(targetWorkflow.name)'")
                }
            }
        } catch is CancellationError {
            result.status = .cancelled
        } catch {
            // Re-throw stop errors so they propagate to the main loop
            if let engineError = error as? WorkflowEngineError,
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

    private func resolveDeviceName(_ deviceId: String) async -> String {
        let devices = await MainActor.run { homeKitManager.cachedDevices }
        if let device = devices.first(where: { $0.id == deviceId }) {
            if let room = device.roomName, !room.isEmpty {
                return "\(room) \(device.name)"
            }
            return device.name
        }
        return deviceId
    }

    private func resolveWorkflowName(_ workflowId: UUID) async -> String {
        if let workflow = await workflowStorageService.getWorkflow(id: workflowId) {
            return workflow.name
        }
        return workflowId.uuidString
    }

    // MARK: - Orphan Logging

    private func logOrphan(workflowId: UUID, workflowName: String, location: String, deviceName: String?, roomName: String?) async {
        let deviceDesc = deviceName.map { name in
            roomName.map { "\(name) (\($0))" } ?? name
        } ?? "unknown device"

        let errorDetails = "\(location): device '\(deviceDesc)' not found — likely orphaned after iCloud restore"

        AppLogger.workflow.warning("[\(workflowName)] Orphaned reference in \(location): \(deviceDesc)")

        let logEntry = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            deviceId: workflowId.uuidString,
            deviceName: workflowName,
            characteristicType: "orphan-detection",
            oldValue: nil,
            newValue: nil,
            category: .workflowError,
            errorDetails: errorDetails
        )
        await loggingService.logEntry(logEntry)
    }

    // MARK: - WaitForState

    private func waitForState(_ block: WaitForStateBlock, workflowId: UUID, workflowName: String, onProgress: ((Double) async -> Void)? = nil) async throws -> Bool {
        let resolvedType = CharacteristicTypes.characteristicType(forName: block.characteristicType) ?? block.characteristicType
        let key = "\(block.deviceId):\(resolvedType)"

        // Check if condition is already met
        let device = await MainActor.run { homeKitManager.getDeviceState(id: block.deviceId) }
        if let device {
            let currentValue = findCharacteristicValue(in: device, characteristicType: resolvedType, serviceId: block.serviceId)
            if ConditionEvaluator.compare(currentValue, using: block.condition) {
                return true
            }
        } else {
            await logOrphan(
                workflowId: workflowId,
                workflowName: workflowName,
                location: "waitForState block '\(block.name ?? "unnamed")'",
                deviceName: block.deviceName,
                roomName: block.roomName
            )
        }

        // Start time for progress tracking
        let startTime = Date()

        // Register a waiter and track the progress task so we can cancel it on completion
        var progressTask: Task<Void, Never>?

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let waiter = StateWaiter(
                deviceId: block.deviceId,
                characteristicType: resolvedType,
                serviceId: block.serviceId,
                condition: block.condition,
                continuation: continuation
            )

            if stateWaiters[key] == nil {
                stateWaiters[key] = []
            }
            stateWaiters[key]?.append(waiter)

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

            // Timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(block.timeoutSeconds * 1_000_000_000))
                await self.timeoutWaiter(waiter, key: key)
            }
        }

        // Stop progress reporting now that the wait is done
        progressTask?.cancel()

        return result
    }

    private func notifyStateWaiters(_ change: StateChange) {
        let key = "\(change.deviceId):\(change.characteristicType)"
        guard var waiters = stateWaiters[key], !waiters.isEmpty else { return }

        var remainingWaiters: [StateWaiter] = []
        for waiter in waiters {
            if ConditionEvaluator.compare(change.newValue, using: waiter.condition) {
                waiter.continuation.resume(returning: true)
            } else {
                remainingWaiters.append(waiter)
            }
        }
        stateWaiters[key] = remainingWaiters.isEmpty ? nil : remainingWaiters
    }

    private func timeoutWaiter(_ waiter: StateWaiter, key: String) {
        guard var waiters = stateWaiters[key] else { return }
        if let index = waiters.firstIndex(where: { $0.id == waiter.id }) {
            waiters.remove(at: index)
            stateWaiters[key] = waiters.isEmpty ? nil : waiters
            waiter.continuation.resume(returning: false)
        }
    }

    private func findCharacteristicValue(in device: DeviceModel, characteristicType: String, serviceId: String?) -> Any? {
        let services: [ServiceModel]
        if let serviceId {
            services = device.services.filter { $0.id == serviceId }
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
                throw WorkflowEngineError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

private struct ExecutionContext {
    let workflow: Workflow
    var callingWorkflowIds: Set<UUID> = []
}

private struct StateWaiter {
    let id = UUID()
    let deviceId: String
    let characteristicType: String
    let serviceId: String?
    let condition: ComparisonOperator
    let continuation: CheckedContinuation<Bool, Error>
}

enum WorkflowEngineError: LocalizedError {
    case timeout
    case invalidURL(String)
    case webhookFailed(statusCode: Int)
    case ssrfBlocked(String)
    case stopped(outcome: StopOutcome, message: String?)
    case circularWorkflowCall(workflowName: String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Operation timed out"
        case let .invalidURL(url): return "Invalid URL: \(url)"
        case let .webhookFailed(code): return "Webhook failed with status \(code)"
        case let .ssrfBlocked(url): return "Request blocked: URL '\(url)' resolves to a private/internal IP address"
        case let .stopped(outcome, message): return "Workflow stopped (\(outcome.rawValue))\(message.map { ": \($0)" } ?? "")"
        case let .circularWorkflowCall(name): return "Circular workflow call detected: '\(name)'"
        }
    }
}
