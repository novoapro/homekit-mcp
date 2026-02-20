import Foundation

/// Core workflow engine that evaluates triggers, checks conditions, and executes blocks.
actor WorkflowEngine {
    private let storageService: WorkflowStorageService
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let executionLogService: WorkflowExecutionLogService
    private let conditionEvaluator: ConditionEvaluator
    private var evaluators: [TriggerEvaluator] = []

    private var runningWorkflows: Set<UUID> = []
    private let maxConcurrentExecutions = 10
    private let blockTimeout: TimeInterval = 30

    /// Waiters for `waitForState` blocks — keyed by device+characteristic.
    private var stateWaiters: [String: [StateWaiter]] = [:]

    init(
        storageService: WorkflowStorageService,
        homeKitManager: HomeKitManager,
        loggingService: LoggingService,
        executionLogService: WorkflowExecutionLogService
    ) {
        self.storageService = storageService
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.executionLogService = executionLogService
        self.conditionEvaluator = ConditionEvaluator(homeKitManager: homeKitManager)
    }

    func registerEvaluator(_ evaluator: TriggerEvaluator) {
        evaluators.append(evaluator)
    }

    // MARK: - State Change Processing

    /// Main entry — called by HomeKitManager on ALL state changes.
    func processStateChange(_ change: StateChange) async {
        // Notify any waitForState waiters first
        notifyStateWaiters(change)

        let workflows = await storageService.getEnabledWorkflows()
        let context = TriggerContext.stateChange(change)

        for workflow in workflows {
            guard !runningWorkflows.contains(workflow.id) else { continue }
            guard runningWorkflows.count < maxConcurrentExecutions else { break }

            // Check if ANY trigger matches
            let triggered = await checkTriggers(workflow.triggers, context: context)
            guard triggered else { continue }

            // Dispatch execution
            let workflowId = workflow.id
            runningWorkflows.insert(workflowId)

            Task { [weak self] in
                await self?.executeWorkflow(workflow, change: change)
                await self?.removeRunning(workflowId)
            }
        }
    }

    /// Manual trigger for testing.
    func triggerWorkflow(id: UUID) async -> WorkflowExecutionLog? {
        guard let workflow = await storageService.getWorkflow(id: id) else { return nil }
        guard !runningWorkflows.contains(id) else { return nil }

        runningWorkflows.insert(id)
        let result = await executeWorkflow(workflow, change: nil)
        runningWorkflows.remove(id)
        return result
    }

    private func removeRunning(_ id: UUID) {
        runningWorkflows.remove(id)
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
    private func executeWorkflow(_ workflow: Workflow, change: StateChange?) async -> WorkflowExecutionLog {
        var execLog = WorkflowExecutionLog(
            workflowId: workflow.id,
            workflowName: workflow.name,
            triggerEvent: change.map {
                TriggerEvent(
                    deviceId: $0.deviceId,
                    deviceName: $0.deviceName,
                    serviceId: $0.serviceId,
                    characteristicType: $0.characteristicType,
                    oldValue: $0.oldValue.map { AnyCodable($0) },
                    newValue: $0.newValue.map { AnyCodable($0) }
                )
            }
        )

        // Evaluate guard conditions
        if let conditions = workflow.conditions, !conditions.isEmpty {
            let (allPassed, condResults) = await conditionEvaluator.evaluateAll(conditions)
            execLog.conditionResults = condResults

            if !allPassed {
                execLog.status = .conditionNotMet
                execLog.completedAt = Date()
                await finalizeExecution(execLog, workflow: workflow, succeeded: false)
                return execLog
            }
        }

        // Execute blocks in order
        let context = ExecutionContext(workflow: workflow)
        var blockResults: [BlockResult] = []
        var failed = false

        for (index, block) in workflow.blocks.enumerated() {
            let result = await executeBlock(block, index: index, context: context)
            blockResults.append(result)

            if result.status == .failure {
                failed = true
                if !workflow.continueOnError {
                    break
                }
            }
        }

        execLog.blockResults = blockResults
        execLog.status = failed ? .failure : .success
        execLog.completedAt = Date()
        execLog.errorMessage = failed ? blockResults.first(where: { $0.status == .failure })?.errorMessage : nil

        await finalizeExecution(execLog, workflow: workflow, succeeded: !failed)
        return execLog
    }

    private func finalizeExecution(_ execLog: WorkflowExecutionLog, workflow: Workflow, succeeded: Bool) async {
        // Log to execution log service
        await executionLogService.log(execLog)

        // Update workflow metadata
        await storageService.updateMetadata(
            id: workflow.id,
            lastTriggered: execLog.triggeredAt,
            incrementExecutions: true,
            resetFailures: succeeded
        )

        if !succeeded && execLog.status != .conditionNotMet {
            await storageService.incrementFailures(id: workflow.id)
        }

        // Log to main logging service
        let category: LogCategory = succeeded ? .workflowExecution : .workflowError
        let logEntry = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            deviceId: workflow.id.uuidString,
            deviceName: workflow.name,
            characteristicType: "workflow",
            oldValue: nil,
            newValue: AnyCodable(execLog.status.rawValue),
            category: category,
            errorDetails: execLog.errorMessage,
            requestBody: "Workflow \(succeeded ? "completed" : "failed"): \(workflow.name)",
            responseBody: execLog.status.rawValue
        )
        await loggingService.logEntry(logEntry)
    }

    // MARK: - Block Execution (Recursive)

    private func executeBlock(_ block: WorkflowBlock, index: Int, context: ExecutionContext) async -> BlockResult {
        switch block {
        case .action(let action):
            return await executeAction(action, index: index, context: context)
        case .flowControl(let flowControl):
            return await executeFlowControl(flowControl, index: index, context: context)
        }
    }

    // MARK: - Action Execution

    private func executeAction(_ action: WorkflowAction, index: Int, context: ExecutionContext) async -> BlockResult {
        var result = BlockResult(blockIndex: index, blockKind: "action", blockType: action.displayType)

        do {
            try await withTimeout(seconds: blockTimeout) {
                switch action {
                case .controlDevice(let a):
                    try await self.executeControlDevice(a)
                    result.detail = "Set \(a.characteristicType) = \(a.value.value) on device \(a.deviceId)"
                case .webhook(let a):
                    try await self.executeWebhook(a)
                    result.detail = "\(a.method) \(a.url)"
                case .log(let a):
                    AppLogger.workflow.info("Workflow log: \(a.message)")
                    result.detail = a.message
                }
            }
            result.status = .success
            result.completedAt = Date()
        } catch {
            result.status = .failure
            result.errorMessage = error.localizedDescription
            result.completedAt = Date()
        }

        return result
    }

    private func executeControlDevice(_ action: ControlDeviceAction) async throws {
        let resolvedType = CharacteristicTypes.characteristicType(forName: action.characteristicType) ?? action.characteristicType
        try await homeKitManager.updateDevice(
            id: action.deviceId,
            characteristicType: resolvedType,
            value: action.value.value,
            serviceId: action.serviceId
        )
    }

    private func executeWebhook(_ action: WebhookActionConfig) async throws {
        guard let url = URL(string: action.url) else {
            throw WorkflowEngineError.invalidURL(action.url)
        }

        var request = URLRequest(url: url)
        request.httpMethod = action.method
        request.timeoutInterval = blockTimeout

        if let headers = action.headers {
            for (key, value) in headers {
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
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw WorkflowEngineError.webhookFailed(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Flow Control Execution

    private func executeFlowControl(_ flowControl: FlowControlBlock, index: Int, context: ExecutionContext) async -> BlockResult {
        var result = BlockResult(blockIndex: index, blockKind: "flowControl", blockType: flowControl.displayType)

        do {
            switch flowControl {
            case .delay(let block):
                try await Task.sleep(nanoseconds: UInt64(block.seconds * 1_000_000_000))
                result.detail = "Delayed \(block.seconds)s"
                result.status = .success

            case .waitForState(let block):
                let matched = try await waitForState(block)
                result.detail = matched ? "State condition met" : "Timed out waiting for state"
                result.status = matched ? .success : .failure
                if !matched {
                    result.errorMessage = "Timed out after \(block.timeoutSeconds)s"
                }

            case .conditional(let block):
                let condResult = await conditionEvaluator.evaluate(block.condition)
                result.detail = "Condition: \(condResult.conditionDescription) = \(condResult.passed)"

                let blocksToRun = condResult.passed ? block.thenBlocks : (block.elseBlocks ?? [])
                var nested: [BlockResult] = []
                var nestedFailed = false
                for (i, b) in blocksToRun.enumerated() {
                    let r = await executeBlock(b, index: i, context: context)
                    nested.append(r)
                    if r.status == .failure {
                        nestedFailed = true
                        if !context.workflow.continueOnError { break }
                    }
                }
                result.nestedResults = nested
                result.status = nestedFailed ? .failure : .success

            case .repeat(let block):
                var nested: [BlockResult] = []
                var repeatFailed = false
                for iteration in 0..<block.count {
                    for (i, b) in block.blocks.enumerated() {
                        let r = await executeBlock(b, index: i, context: context)
                        nested.append(r)
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

            case .repeatWhile(let block):
                var nested: [BlockResult] = []
                var repeatFailed = false
                var iterations = 0

                while iterations < block.maxIterations {
                    let condResult = await conditionEvaluator.evaluate(block.condition)
                    guard condResult.passed else { break }

                    for (i, b) in block.blocks.enumerated() {
                        let r = await executeBlock(b, index: i, context: context)
                        nested.append(r)
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

            case .group(let block):
                var nested: [BlockResult] = []
                var groupFailed = false
                for (i, b) in block.blocks.enumerated() {
                    let r = await executeBlock(b, index: i, context: context)
                    nested.append(r)
                    if r.status == .failure {
                        groupFailed = true
                        if !context.workflow.continueOnError { break }
                    }
                }
                result.detail = block.label ?? "Group"
                result.nestedResults = nested
                result.status = groupFailed ? .failure : .success
            }
        } catch {
            result.status = .failure
            result.errorMessage = error.localizedDescription
        }

        result.completedAt = Date()
        return result
    }

    // MARK: - WaitForState

    private func waitForState(_ block: WaitForStateBlock) async throws -> Bool {
        let resolvedType = CharacteristicTypes.characteristicType(forName: block.characteristicType) ?? block.characteristicType
        let key = "\(block.deviceId):\(resolvedType)"

        // Check if condition is already met
        let device = await MainActor.run { homeKitManager.getDeviceState(id: block.deviceId) }
        if let device {
            let currentValue = findCharacteristicValue(in: device, characteristicType: resolvedType, serviceId: block.serviceId)
            if ConditionEvaluator.compare(currentValue, using: block.condition) {
                return true
            }
        }

        // Register a waiter
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
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

            // Timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(block.timeoutSeconds * 1_000_000_000))
                await self.timeoutWaiter(waiter, key: key)
            }
        }
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

    var errorDescription: String? {
        switch self {
        case .timeout: return "Operation timed out"
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .webhookFailed(let code): return "Webhook failed with status \(code)"
        }
    }
}
