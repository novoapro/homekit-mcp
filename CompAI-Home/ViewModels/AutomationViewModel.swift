import Foundation
import Combine

@MainActor
class AutomationViewModel: ObservableObject {
    @Published var automations: [Automation] = []
    @Published var executionLogs: [AutomationExecutionLog] = []
    @Published var searchText = ""
    @Published var showClonedToast = false
    @Published var isRefreshing = false

    private let storageService: AutomationStorageService
    private let executionLogService: LoggingService
    private let automationEngine: AutomationEngine
    let homeKitManager: HomeKitManager
    private(set) var aiAutomationService: AIAutomationService?
    private var cancellables = Set<AnyCancellable>()
    private var clonedToastTask: Task<Void, Never>?

    /// Returns enabled devices with stable registry IDs and effective permissions baked in.
    /// Only characteristics marked as enabled in the registry are included.
    var devices: [DeviceModel] {
        let raw = homeKitManager.cachedDevices
        guard let registry = homeKitManager.deviceRegistryService else { return raw }
        return registry.stableDevices(raw)
    }

    /// Returns scenes with stable registry IDs so picker tags match automation stable IDs.
    var scenes: [SceneModel] {
        let raw = homeKitManager.getAllScenes()
        guard let registry = homeKitManager.deviceRegistryService else { return raw }
        return registry.stableScenes(raw)
    }

    var filteredAutomations: [Automation] {
        guard !searchText.isEmpty else { return automations }
        let query = searchText.localizedLowercase
        return automations.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.description?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.metadata.tags?.contains(where: { $0.localizedCaseInsensitiveContains(query) }) ?? false)
        }
    }

    var enabledCount: Int {
        automations.filter(\.isEnabled).count
    }

    init(storageService: AutomationStorageService, executionLogService: LoggingService, automationEngine: AutomationEngine, homeKitManager: HomeKitManager, aiAutomationService: AIAutomationService? = nil) {
        self.storageService = storageService
        self.executionLogService = executionLogService
        self.automationEngine = automationEngine
        self.homeKitManager = homeKitManager
        self.aiAutomationService = aiAutomationService

        // Subscribe to automation changes
        storageService.automationsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] automations in
                self?.automations = automations
            }
            .store(in: &cancellables)

        // Subscribe to execution log changes (filter to automation categories)
        executionLogService.logsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.executionLogs = logs.compactMap(\.automationExecution)
            }
            .store(in: &cancellables)

        // Initial fetch
        Task {
            let existingAutomations = await storageService.getAllAutomations()
            let allLogs = await executionLogService.getLogs()
            let wfLogs = allLogs.compactMap(\.automationExecution)
            await MainActor.run {
                self.automations = existingAutomations
                self.executionLogs = wfLogs
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        let freshAutomations = await storageService.getAllAutomations()
        let allLogs = await executionLogService.getLogs()
        let wfLogs = allLogs.compactMap(\.automationExecution)
        automations = freshAutomations
        executionLogs = wfLogs
        isRefreshing = false
    }

    func toggleEnabled(id: UUID) {
        Task {
            if var automation = await storageService.getAutomation(id: id) {
                let wasEnabled = automation.isEnabled
                automation.isEnabled.toggle()
                automation.updatedAt = Date()
                await storageService.updateAutomation(id: id) { $0 = automation }

                // When disabling, cancel any running executions for this automation
                if wasEnabled && !automation.isEnabled {
                    await automationEngine.cancelRunningExecutions(forAutomation: id)
                }
            }
        }
    }

    func deleteAutomation(id: UUID) {
        Task {
            await storageService.deleteAutomation(id: id)
        }
    }

    func resetStatistics(id: UUID) {
        Task {
            await storageService.resetStatistics(id: id)
            await executionLogService.clearLogs(forAutomationId: id)
        }
    }

    func triggerAutomation(id: UUID) {
        Task {
            _ = await automationEngine.triggerAutomation(id: id)
        }
    }

    func cancelExecution(executionId: UUID) {
        Task {
            await automationEngine.cancelExecution(executionId: executionId)
        }
    }

    func executionLogs(for automationId: UUID) -> [AutomationExecutionLog] {
        executionLogs.filter { $0.automationId == automationId }
    }

    func createAutomation(from draft: AutomationDraft) {
        Task {
            let automation = draft.toAutomation(devices: devices, existingMetadata: nil, createdAt: nil)
            await storageService.createAutomation(automation)
        }
    }

    func updateAutomation(id: UUID, from draft: AutomationDraft) {
        Task {
            guard let existing = await storageService.getAutomation(id: id) else { return }
            let automation = draft.toAutomation(devices: devices, existingMetadata: existing.metadata, createdAt: existing.createdAt)
            await storageService.updateAutomation(id: id) { $0 = automation }
        }
    }

    func cloneAutomation(id: UUID) {
        Task {
            guard let original = await storageService.getAutomation(id: id) else { return }
            var draft = AutomationDraft(from: original, devices: devices)
            draft.id = UUID()
            draft.name = "\(original.name) (Copy)"
            draft.isEnabled = false
            // Regenerate webhook trigger tokens to avoid collisions
            for i in draft.triggers.indices where draft.triggers[i].triggerType == .webhook {
                draft.triggers[i].webhookToken = UUID().uuidString
            }
            let clonedMetadata = AutomationMetadata(
                createdBy: original.metadata.createdBy,
                tags: original.metadata.tags,
                lastTriggeredAt: nil,
                totalExecutions: 0,
                consecutiveFailures: 0
            )
            let cloned = draft.toAutomation(devices: devices, existingMetadata: clonedMetadata, createdAt: nil)
            await storageService.createAutomation(cloned)
            showCloneToast()
        }
    }

    func improveAutomation(id: UUID, prompt: String?) async throws -> Automation {
        guard let aiService = aiAutomationService else {
            throw AIAutomationError.notConfigured
        }
        guard let automation = await storageService.getAutomation(id: id) else {
            throw NSError(domain: "AutomationViewModel", code: 404, userInfo: [NSLocalizedDescriptionKey: "Automation not found"])
        }
        let defaultPrompt = "Review this automation and suggest improvements. Fix any labels that don't match their configuration. Optimize the structure if possible."
        let improved = try await aiService.refineAutomation(automation, feedback: prompt ?? defaultPrompt)
        // Preserve identity from the original automation
        return Automation(
            id: automation.id,
            name: improved.name,
            description: improved.description,
            isEnabled: improved.isEnabled,
            triggers: improved.triggers,
            conditions: improved.conditions,
            blocks: improved.blocks,
            continueOnError: improved.continueOnError,
            retriggerPolicy: improved.retriggerPolicy,
            loggingOverride: improved.loggingOverride,
            metadata: automation.metadata,
            createdAt: automation.createdAt,
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

    func saveGeneratedAutomation(_ automation: Automation) {
        Task {
            await storageService.createAutomation(automation)
        }
    }

    func evaluateCondition(_ condition: AutomationCondition) async -> ConditionResult {
        await automationEngine.evaluateCondition(condition)
    }
}
