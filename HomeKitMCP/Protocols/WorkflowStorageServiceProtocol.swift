import Foundation
import Combine

/// Protocol abstracting WorkflowStorageService for dependency injection and testability.
protocol WorkflowStorageServiceProtocol: AnyObject, Sendable {
    // MARK: - Publishers
    var workflowsSubject: PassthroughSubject<[Workflow], Never> { get }

    // MARK: - Read
    func getAllWorkflows() async -> [Workflow]
    func getWorkflow(id: UUID) async -> Workflow?
    func getEnabledWorkflows() async -> [Workflow]

    // MARK: - Write
    @discardableResult
    func createWorkflow(_ workflow: Workflow) async -> Workflow
    @discardableResult
    func updateWorkflow(id: UUID, update: (inout Workflow) -> Void) async -> Workflow?
    @discardableResult
    func deleteWorkflow(id: UUID) async -> Bool

    // MARK: - Metadata
    func updateMetadata(id: UUID, lastTriggered: Date, incrementExecutions: Bool, resetFailures: Bool) async
    func incrementFailures(id: UUID) async
}
