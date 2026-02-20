import Foundation
import Combine

class WorkflowViewModel: ObservableObject {
    @Published var workflows: [Workflow] = []
    @Published var executionLogs: [WorkflowExecutionLog] = []
    @Published var searchText = ""

    private let storageService: WorkflowStorageService
    private let executionLogService: WorkflowExecutionLogService
    private let workflowEngine: WorkflowEngine
    private var cancellables = Set<AnyCancellable>()

    var filteredWorkflows: [Workflow] {
        guard !searchText.isEmpty else { return workflows }
        let query = searchText.localizedLowercase
        return workflows.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.description?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.metadata.tags?.contains(where: { $0.localizedCaseInsensitiveContains(query) }) ?? false)
        }
    }

    var enabledCount: Int {
        workflows.filter(\.isEnabled).count
    }

    init(storageService: WorkflowStorageService, executionLogService: WorkflowExecutionLogService, workflowEngine: WorkflowEngine) {
        self.storageService = storageService
        self.executionLogService = executionLogService
        self.workflowEngine = workflowEngine

        // Subscribe to workflow changes
        storageService.workflowsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workflows in
                self?.workflows = workflows
            }
            .store(in: &cancellables)

        // Subscribe to execution log changes
        executionLogService.logsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.executionLogs = logs
            }
            .store(in: &cancellables)

        // Initial fetch
        Task {
            let existingWorkflows = await storageService.getAllWorkflows()
            let existingLogs = await executionLogService.getLogs()
            await MainActor.run {
                self.workflows = existingWorkflows
                self.executionLogs = existingLogs
            }
        }
    }

    func toggleEnabled(id: UUID) {
        Task {
            if var workflow = await storageService.getWorkflow(id: id) {
                workflow.isEnabled.toggle()
                workflow.updatedAt = Date()
                await storageService.updateWorkflow(id: id) { $0 = workflow }
            }
        }
    }

    func deleteWorkflow(id: UUID) {
        Task {
            await storageService.deleteWorkflow(id: id)
        }
    }

    func triggerWorkflow(id: UUID) {
        Task {
            _ = await workflowEngine.triggerWorkflow(id: id)
        }
    }

    func executionLogs(for workflowId: UUID) -> [WorkflowExecutionLog] {
        executionLogs.filter { $0.workflowId == workflowId }
    }
}
