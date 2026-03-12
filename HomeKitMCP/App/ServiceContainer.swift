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

    lazy var loggingService: LoggingService = LoggingService(storage: storageService)
    let deviceRegistryService: DeviceRegistryService = DeviceRegistryService()
    let workflowStorageService: WorkflowStorageService = WorkflowStorageService()
    let scheduleTriggerManager: ScheduleTriggerManager = ScheduleTriggerManager()

    lazy var webhookService: WebhookService = WebhookService(
        storage: storageService,
        loggingService: loggingService,
        keychainService: keychainService
    )

    lazy var homeKitManager: HomeKitManager = HomeKitManager(
        loggingService: loggingService,
        webhookService: webhookService,
        storage: storageService
    )

    lazy var workflowEngine: WorkflowEngine = WorkflowEngine(
        storageService: workflowStorageService,
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        executionLogService: loggingService,
        storage: storageService,
        registry: deviceRegistryService
    )

    lazy var aiWorkflowService: AIWorkflowService = AIWorkflowService(
        storage: storageService,
        homeKitManager: homeKitManager,
        keychainService: keychainService,
        loggingService: loggingService,
        registry: deviceRegistryService
    )

    lazy var mcpServer: MCPServer = MCPServer(
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        storage: storageService,
        workflowStorageService: workflowStorageService,
        workflowEngine: workflowEngine,
        keychainService: keychainService,
        registry: deviceRegistryService,
        aiWorkflowService: aiWorkflowService,
        port: storageService.mcpServerPort
    )

    // MARK: - Authentication & Backup

    lazy var appleSignInService: AppleSignInService = AppleSignInService(
        keychainService: keychainService
    )

    lazy var backupService: BackupService = BackupService(
        storage: storageService,
        keychainService: keychainService,
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
        registryService: deviceRegistryService
    )

    lazy var logViewModel: LogViewModel = LogViewModel(
        loggingService: loggingService,
        storage: storageService
    )

    lazy var settingsViewModel: SettingsViewModel = SettingsViewModel(
        storage: storageService,
        webhookService: webhookService,
        mcpServer: mcpServer,
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
        executionLogService: loggingService,
        workflowEngine: workflowEngine,
        homeKitManager: homeKitManager,
        aiWorkflowService: aiWorkflowService
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

        // One-time migration: merge device-config.json settings into registry
        let configFileURL = FileManager.appSupportDirectory.appendingPathComponent("device-config.json")
        if FileManager.default.fileExists(atPath: configFileURL.path) {
            Task {
                // Read the old config file directly
                if let data = try? Data(contentsOf: configFileURL),
                   let oldConfigs = try? JSONDecoder.iso8601.decode([String: LegacyCharacteristicConfiguration].self, from: data),
                   !oldConfigs.isEmpty {
                    let mapped = oldConfigs.mapValues { (enabled: $0.externalAccessEnabled, observed: $0.webhookEnabled) }
                    await deviceRegistryService.migrateFromDeviceConfig(mapped)
                }
                // Delete the old config file
                try? FileManager.default.removeItem(at: configFileURL)
                AppLogger.registry.info("Migration: removed device-config.json after merging into registry")
            }
        }
    }
}

/// Legacy model used only for migration from device-config.json.
private struct LegacyCharacteristicConfiguration: Codable {
    var externalAccessEnabled: Bool
    var webhookEnabled: Bool
}
