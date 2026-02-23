import Foundation

/// Protocol abstracting WorkflowEngine for dependency injection and testability.
protocol WorkflowEngineProtocol: AnyObject, Sendable {
    func registerEvaluator(_ evaluator: TriggerEvaluator) async
    func processStateChange(_ change: StateChange) async
    func triggerWorkflow(id: UUID) async -> WorkflowExecutionLog?
    func triggerWorkflow(id: UUID, triggerEvent: TriggerEvent) async -> WorkflowExecutionLog?
    func triggerWorkflow(id: UUID, triggerEvent: TriggerEvent, policy: ConcurrentExecutionPolicy?) async -> WorkflowExecutionLog?
    func scheduleTrigger(id: UUID) async -> TriggerResult
    func scheduleTrigger(id: UUID, triggerEvent: TriggerEvent) async -> TriggerResult
    func scheduleTrigger(id: UUID, triggerEvent: TriggerEvent, policy: ConcurrentExecutionPolicy?) async -> TriggerResult
    func cancelExecution(executionId: UUID) async
    func cancelRunningExecutions(forWorkflow workflowId: UUID) async
}
