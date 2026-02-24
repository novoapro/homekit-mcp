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
    let deviceRegistryService: DeviceRegistryService = DeviceRegistryService()
    let workflowStorageService: WorkflowStorageService = WorkflowStorageService()
    let workflowExecutionLogService: WorkflowExecutionLogService = WorkflowExecutionLogService()
    let aiInteractionLogService: AIInteractionLogService = AIInteractionLogService()
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
        storage: storageService,
        registry: deviceRegistryService
    )

    lazy var aiWorkflowService: AIWorkflowService = AIWorkflowService(
        storage: storageService,
        homeKitManager: homeKitManager,
        keychainService: keychainService,
        interactionLog: aiInteractionLogService,
        registry: deviceRegistryService
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
        registry: deviceRegistryService,
        port: storageService.mcpServerPort
    )

    // MARK: - Authentication & Backup

    lazy var appleSignInService: AppleSignInService = AppleSignInService(
        keychainService: keychainService
    )

    lazy var backupService: BackupService = BackupService(
        storage: storageService,
        keychainService: keychainService,
        configService: configService,
        workflowStorageService: workflowStorageService,
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        deviceRegistryService: deviceRegistryService
    )

    lazy var cloudBackupService: CloudBackupService = CloudBackupService(
        backupService: backupService,
        storage: storageService,
        workflowStorageService: workflowStorageService
    )

    lazy var workflowSyncService: WorkflowSyncService = WorkflowSyncService(
        workflowStorageService: workflowStorageService,
        storage: storageService,
        deviceRegistryService: deviceRegistryService,
        homeKitManager: homeKitManager
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
        aiWorkflowService: aiWorkflowService,
        backupService: backupService,
        cloudBackupService: cloudBackupService,
        appleSignInService: appleSignInService,
        deviceRegistryService: deviceRegistryService,
        homeKitManager: homeKitManager,
        workflowStorageService: workflowStorageService
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
        homeKitManager.deviceRegistryService = deviceRegistryService
        workflowEngine.subscribeToStateChanges(from: homeKitManager.stateChangePublisher)
        // Touch workflowSyncService to initialize it (sets up Combine subscriptions)
        _ = workflowSyncService
    }
}
