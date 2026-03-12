import Foundation
import Combine

@MainActor
class WorkflowViewModel: ObservableObject {
    @Published var workflows: [Workflow] = []
    @Published var executionLogs: [WorkflowExecutionLog] = []
    @Published var searchText = ""
    @Published var showClonedToast = false
    @Published var isRefreshing = false

    private let storageService: WorkflowStorageService
    private let executionLogService: LoggingService
    private let workflowEngine: WorkflowEngine
    let homeKitManager: HomeKitManager
    private(set) var aiWorkflowService: AIWorkflowService?
    private var cancellables = Set<AnyCancellable>()
    private var clonedToastTask: Task<Void, Never>?

    /// Returns enabled devices with stable registry IDs and effective permissions baked in.
    /// Only characteristics marked as enabled in the registry are included.
    var devices: [DeviceModel] {
        let raw = homeKitManager.cachedDevices
        guard let registry = homeKitManager.deviceRegistryService else { return raw }
        return registry.stableDevices(raw)
    }

    /// Returns scenes with stable registry IDs so picker tags match workflow stable IDs.
    var scenes: [SceneModel] {
        let raw = homeKitManager.getAllScenes()
        guard let registry = homeKitManager.deviceRegistryService else { return raw }
        return registry.stableScenes(raw)
    }

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

    init(storageService: WorkflowStorageService, executionLogService: LoggingService, workflowEngine: WorkflowEngine, homeKitManager: HomeKitManager, aiWorkflowService: AIWorkflowService? = nil) {
        self.storageService = storageService
        self.executionLogService = executionLogService
        self.workflowEngine = workflowEngine
        self.homeKitManager = homeKitManager
        self.aiWorkflowService = aiWorkflowService

        // Subscribe to workflow changes
        storageService.workflowsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workflows in
                self?.workflows = workflows
            }
            .store(in: &cancellables)

        // Subscribe to execution log changes (filter to workflow categories)
        executionLogService.logsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.executionLogs = logs.compactMap(\.workflowExecution)
            }
            .store(in: &cancellables)

        // Initial fetch
        Task {
            let existingWorkflows = await storageService.getAllWorkflows()
            let allLogs = await executionLogService.getLogs()
            let wfLogs = allLogs.compactMap(\.workflowExecution)
            await MainActor.run {
                self.workflows = existingWorkflows
                self.executionLogs = wfLogs
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        let freshWorkflows = await storageService.getAllWorkflows()
        let allLogs = await executionLogService.getLogs()
        let wfLogs = allLogs.compactMap(\.workflowExecution)
        workflows = freshWorkflows
        executionLogs = wfLogs
        isRefreshing = false
    }

    func toggleEnabled(id: UUID) {
        Task {
            if var workflow = await storageService.getWorkflow(id: id) {
                let wasEnabled = workflow.isEnabled
                workflow.isEnabled.toggle()
                workflow.updatedAt = Date()
                await storageService.updateWorkflow(id: id) { $0 = workflow }

                // When disabling, cancel any running executions for this workflow
                if wasEnabled && !workflow.isEnabled {
                    await workflowEngine.cancelRunningExecutions(forWorkflow: id)
                }
            }
        }
    }

    func deleteWorkflow(id: UUID) {
        Task {
            await storageService.deleteWorkflow(id: id)
        }
    }

    func resetStatistics(id: UUID) {
        Task {
            await storageService.resetStatistics(id: id)
            await executionLogService.clearLogs(forWorkflowId: id)
        }
    }

    func triggerWorkflow(id: UUID) {
        Task {
            _ = await workflowEngine.triggerWorkflow(id: id)
        }
    }

    func cancelExecution(executionId: UUID) {
        Task {
            await workflowEngine.cancelExecution(executionId: executionId)
        }
    }

    func executionLogs(for workflowId: UUID) -> [WorkflowExecutionLog] {
        executionLogs.filter { $0.workflowId == workflowId }
    }

    func createWorkflow(from draft: WorkflowDraft) {
        Task {
            let workflow = draft.toWorkflow(devices: devices, existingMetadata: nil, createdAt: nil)
            await storageService.createWorkflow(workflow)
        }
    }

    func updateWorkflow(id: UUID, from draft: WorkflowDraft) {
        Task {
            guard let existing = await storageService.getWorkflow(id: id) else { return }
            let workflow = draft.toWorkflow(devices: devices, existingMetadata: existing.metadata, createdAt: existing.createdAt)
            await storageService.updateWorkflow(id: id) { $0 = workflow }
        }
    }

    func cloneWorkflow(id: UUID) {
        Task {
            guard let original = await storageService.getWorkflow(id: id) else { return }
            var draft = WorkflowDraft(from: original, devices: devices)
            draft.id = UUID()
            draft.name = "\(original.name) (Copy)"
            draft.isEnabled = false
            // Regenerate webhook trigger tokens to avoid collisions
            for i in draft.triggers.indices where draft.triggers[i].triggerType == .webhook {
                draft.triggers[i].webhookToken = UUID().uuidString
            }
            let clonedMetadata = WorkflowMetadata(
                createdBy: original.metadata.createdBy,
                tags: original.metadata.tags,
                lastTriggeredAt: nil,
                totalExecutions: 0,
                consecutiveFailures: 0
            )
            let cloned = draft.toWorkflow(devices: devices, existingMetadata: clonedMetadata, createdAt: nil)
            await storageService.createWorkflow(cloned)
            showCloneToast()
        }
    }

    func improveWorkflow(id: UUID, prompt: String?) async throws -> Workflow {
        guard let aiService = aiWorkflowService else {
            throw AIWorkflowError.notConfigured
        }
        guard let workflow = await storageService.getWorkflow(id: id) else {
            throw NSError(domain: "WorkflowViewModel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Workflow not found"])
        }
        let defaultPrompt = "Review this workflow and suggest improvements. Fix any labels that don't match their configuration. Optimize the structure if possible."
        let improved = try await aiService.refineWorkflow(workflow, feedback: prompt ?? defaultPrompt)
        // Preserve identity from the original workflow
        return Workflow(
            id: workflow.id,
            name: improved.name,
            description: improved.description,
            isEnabled: improved.isEnabled,
            triggers: improved.triggers,
            conditions: improved.conditions,
            blocks: improved.blocks,
            continueOnError: improved.continueOnError,
            retriggerPolicy: improved.retriggerPolicy,
            metadata: workflow.metadata,
            createdAt: workflow.createdAt,
            updatedAt: Date()
        )
    }

    private func showCloneToast() {
        clonedToastTask?.cancel()
        showClonedToast = true
        clonedToastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                showClonedToast = false
            }
        }
    }

    func saveGeneratedWorkflow(_ workflow: Workflow) {
        Task {
            await storageService.createWorkflow(workflow)
        }
    }

    func evaluateCondition(_ condition: WorkflowCondition) async -> ConditionResult {
        await workflowEngine.evaluateCondition(condition)
    }
}
