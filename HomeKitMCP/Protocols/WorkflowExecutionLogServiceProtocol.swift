import Foundation
import Combine

/// Protocol abstracting WorkflowExecutionLogService for dependency injection and testability.
protocol WorkflowExecutionLogServiceProtocol: AnyObject, Sendable {
    // MARK: - Publishers
    var logsSubject: PassthroughSubject<[WorkflowExecutionLog], Never> { get }

    // MARK: - Write
    func log(_ execution: WorkflowExecutionLog) async
    func update(_ execution: WorkflowExecutionLog) async

    // MARK: - Read
    func getLogs() async -> [WorkflowExecutionLog]
    func getLogs(forWorkflow id: UUID) async -> [WorkflowExecutionLog]
    func clearLogs() async
    func clearLogs(forWorkflow id: UUID) async
}
