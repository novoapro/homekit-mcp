import Foundation

/// Protocol abstracting WorkflowEngine for dependency injection and testability.
protocol WorkflowEngineProtocol: AnyObject, Sendable {
    func registerEvaluator(_ evaluator: TriggerEvaluator) async
    func processStateChange(_ change: StateChange) async
    func triggerWorkflow(id: UUID) async -> WorkflowExecutionLog?
    func triggerWorkflow(id: UUID, triggerEvent: TriggerEvent) async -> WorkflowExecutionLog?
}
