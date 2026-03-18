import Foundation
import Combine

/// Owns the creation and wiring of all application services and view models.
/// AppDelegate creates the container and calls `wireServices()` once to
/// establish any cross-service subscriptions.
@MainActor
final class ServiceContainer {

    // MARK: - Infrastructure

    let keychainService = KeychainService()
    let subscriptionService = SubscriptionService()
    lazy var oauthService: OAuthService = OAuthService(keychainService: keychainService)

    lazy var storageService: StorageService = StorageService(keychainService: keychainService)

    // MARK: - Core Services

    lazy var loggingService: LoggingService = LoggingService(storage: storageService)
    let deviceRegistryService: DeviceRegistryService = DeviceRegistryService()
    let automationStorageService: AutomationStorageService = AutomationStorageService()
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

    lazy var automationEngine: AutomationEngine = AutomationEngine(
        storageService: automationStorageService,
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        executionLogService: loggingService,
        storage: storageService,
        registry: deviceRegistryService
    )

    lazy var aiAutomationService: AIAutomationService = AIAutomationService(
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
        automationStorageService: automationStorageService,
        automationEngine: automationEngine,
        keychainService: keychainService,
        registry: deviceRegistryService,
        aiAutomationService: aiAutomationService,
        subscriptionService: subscriptionService,
        oauthService: oauthService,
        port: storageService.mcpServerPort
    )

    // MARK: - Authentication & Backup

    lazy var appleSignInService: AppleSignInService = AppleSignInService(
        keychainService: keychainService
    )

    lazy var backupService: BackupService = BackupService(
        storage: storageService,
        keychainService: keychainService,
        automationStorageService: automationStorageService,
        homeKitManager: homeKitManager,
        loggingService: loggingService,
        deviceRegistryService: deviceRegistryService
    )

    lazy var cloudBackupService: CloudBackupService = CloudBackupService(
        backupService: backupService,
        storage: storageService,
        automationStorageService: automationStorageService
    )

    lazy var automationSyncService: AutomationSyncService = AutomationSyncService(
        automationStorageService: automationStorageService,
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
        aiAutomationService: aiAutomationService,
        backupService: backupService,
        cloudBackupService: cloudBackupService,
        appleSignInService: appleSignInService,
        deviceRegistryService: deviceRegistryService,
        homeKitManager: homeKitManager,
        automationStorageService: automationStorageService,
        subscriptionService: subscriptionService,
        oauthService: oauthService
    )

    lazy var automationViewModel: AutomationViewModel = AutomationViewModel(
        storageService: automationStorageService,
        executionLogService: loggingService,
        automationEngine: automationEngine,
        homeKitManager: homeKitManager,
        aiAutomationService: aiAutomationService
    )

    // MARK: - Wiring

    /// Establishes cross-service subscriptions that cannot be expressed as init-time
    /// dependencies. Call once after the container is created.
    ///
    /// Currently wires:
    /// - HomeKitManager.stateChangePublisher → AutomationEngine.processStateChange
    ///   (replaces the old post-init `homeKitManager.automationEngine = automationEngine` assignment)
    func wireServices() {
        homeKitManager.deviceRegistryService = deviceRegistryService
        automationEngine.subscribeToStateChanges(from: homeKitManager.stateChangePublisher)
        subscriptionService.start()
        // Touch automationSyncService to initialize it (sets up Combine subscriptions)
        _ = automationSyncService

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
