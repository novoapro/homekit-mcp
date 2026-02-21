import Foundation
import Combine

/// Owns the creation and wiring of all application services and view models.
/// AppDelegate creates the container and calls `wireServices()` once to
/// establish any cross-service subscriptions.
@MainActor
final class ServiceContainer {

    // MARK: - Infrastructure

    let keychainService = KeychainService()

    lazy var storageService: StorageService = StorageService(keychainService: keychainService)

    // MARK: - Core Services

    let loggingService: LoggingService = LoggingService()
    let configService: DeviceConfigurationService = DeviceConfigurationService()
    let workflowStorageService: WorkflowStorageService = WorkflowStorageService()
    let workflowExecutionLogService: WorkflowExecutionLogService = WorkflowExecutionLogService()
    let scheduleTriggerManager: ScheduleTriggerManager = ScheduleTriggerManager()

    lazy var webhookService: WebhookService = WebhookService(
        storage: storageService,
        loggingService: loggingService,
        keychainService: keychainService
    )

    lazy var homeKitManager: HomeKitManager = HomeKitManager(
        loggingService: loggingService,
        webhookService: webhookService,
        configService: configService,
        storage: storageService
    )

    lazy var workflowEngine: WorkflowEngine = WorkflowEngine(
        storageService: workflowStorageService,
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        executionLogService: workflowExecutionLogService,
        storage: storageService
    )

    lazy var aiWorkflowService: AIWorkflowService = AIWorkflowService(
        storage: storageService,
        homeKitManager: homeKitManager,
        keychainService: keychainService
    )

    lazy var mcpServer: MCPServer = MCPServer(
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        configService: configService,
        storage: storageService,
        workflowStorageService: workflowStorageService,
        workflowEngine: workflowEngine,
        workflowExecutionLogService: workflowExecutionLogService,
        keychainService: keychainService,
        port: storageService.mcpServerPort
    )

    // MARK: - View Models

    lazy var homeKitViewModel: HomeKitViewModel = HomeKitViewModel(
        homeKitManager: homeKitManager,
        configService: configService
    )

    lazy var logViewModel: LogViewModel = LogViewModel(
        loggingService: loggingService,
        executionLogService: workflowExecutionLogService,
        storage: storageService
    )

    lazy var settingsViewModel: SettingsViewModel = SettingsViewModel(
        storage: storageService,
        webhookService: webhookService,
        mcpServer: mcpServer,
        configService: configService,
        keychainService: keychainService,
        aiWorkflowService: aiWorkflowService
    )

    lazy var workflowViewModel: WorkflowViewModel = WorkflowViewModel(
        storageService: workflowStorageService,
        executionLogService: workflowExecutionLogService,
        workflowEngine: workflowEngine,
        homeKitManager: homeKitManager
    )

    // MARK: - Wiring

    /// Establishes cross-service subscriptions that cannot be expressed as init-time
    /// dependencies. Call once after the container is created.
    ///
    /// Currently wires:
    /// - HomeKitManager.stateChangePublisher → WorkflowEngine.processStateChange
    ///   (replaces the old post-init `homeKitManager.workflowEngine = workflowEngine` assignment)
    func wireServices() {
        workflowEngine.subscribeToStateChanges(from: homeKitManager.stateChangePublisher)
    }
}
