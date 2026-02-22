import Foundation

@MainActor
class BackupService: ObservableObject, BackupServiceProtocol {
    @Published var isBackingUp = false
    @Published var isRestoring = false
    @Published var lastError: String?

    private let storage: StorageService
    private let keychainService: KeychainService
    private let configService: DeviceConfigurationService
    private let workflowStorageService: WorkflowStorageService
    private let homeKitManager: HomeKitManager

    init(
        storage: StorageService,
        keychainService: KeychainService,
        configService: DeviceConfigurationService,
        workflowStorageService: WorkflowStorageService,
        homeKitManager: HomeKitManager
    ) {
        self.storage = storage
        self.keychainService = keychainService
        self.configService = configService
        self.workflowStorageService = workflowStorageService
        self.homeKitManager = homeKitManager
    }

    // MARK: - Create Backup

    func createBackup() async throws -> BackupBundle {
        isBackingUp = true
        lastError = nil
        defer { isBackingUp = false }

        let settings = BackupSettings(
            mcpServerPort: storage.mcpServerPort,
            webhookEnabled: storage.webhookEnabled,
            mcpServerEnabled: storage.mcpServerEnabled,
            hideRoomNameInTheApp: storage.hideRoomNameInTheApp,
            detailedLogsEnabled: storage.detailedLogsEnabled,
            aiEnabled: storage.aiEnabled,
            aiProvider: storage.aiProvider.rawValue,
            aiModelId: storage.aiModelId,
            mcpServerBindAddress: storage.mcpServerBindAddress,
            sunEventLatitude: storage.sunEventLatitude,
            sunEventLongitude: storage.sunEventLongitude,
            sunEventZipCode: storage.sunEventZipCode,
            sunEventCityName: storage.sunEventCityName,
            pollingEnabled: storage.pollingEnabled,
            pollingInterval: storage.pollingInterval,
            workflowsEnabled: storage.workflowsEnabled,
            autoBackupEnabled: storage.autoBackupEnabled,
            deviceStateLoggingEnabled: storage.deviceStateLoggingEnabled
        )

        let secrets = BackupSecrets(
            aiApiKey: keychainService.read(key: KeychainService.Keys.aiApiKey),
            mcpApiToken: nil,
            apiTokens: keychainService.getAPITokens(),
            webhookSecret: keychainService.read(key: KeychainService.Keys.webhookSecret),
            webhookURL: keychainService.read(key: KeychainService.Keys.webhookURL)
        )

        let workflows = await workflowStorageService.getAllWorkflows()
        let deviceConfig = await configService.getAllConfigs()

        let deviceName = ProcessInfo.processInfo.hostName

        return BackupBundle(
            formatVersion: BackupBundle.currentFormatVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            createdAt: Date(),
            deviceName: deviceName,
            backupId: UUID(),
            settings: settings,
            secrets: secrets,
            workflows: workflows,
            deviceConfig: deviceConfig
        )
    }

    // MARK: - Restore Backup

    func restoreBackup(_ bundle: BackupBundle) async throws {
        isRestoring = true
        lastError = nil
        defer { isRestoring = false }

        guard bundle.formatVersion <= BackupBundle.currentFormatVersion else {
            let error = "Backup format version \(bundle.formatVersion) is newer than supported version \(BackupBundle.currentFormatVersion). Please update the app."
            lastError = error
            throw BackupError.unsupportedVersion(bundle.formatVersion)
        }

        // Restore settings
        let s = bundle.settings
        storage.mcpServerPort = s.mcpServerPort
        storage.webhookEnabled = s.webhookEnabled
        storage.mcpServerEnabled = s.mcpServerEnabled
        storage.hideRoomNameInTheApp = s.hideRoomNameInTheApp
        storage.detailedLogsEnabled = s.detailedLogsEnabled
        storage.aiEnabled = s.aiEnabled
        storage.aiProvider = AIProvider(rawValue: s.aiProvider) ?? .claude
        storage.aiModelId = s.aiModelId
        storage.mcpServerBindAddress = s.mcpServerBindAddress
        storage.sunEventLatitude = s.sunEventLatitude
        storage.sunEventLongitude = s.sunEventLongitude
        storage.sunEventZipCode = s.sunEventZipCode ?? ""
        storage.sunEventCityName = s.sunEventCityName ?? ""
        storage.pollingEnabled = s.pollingEnabled
        storage.pollingInterval = s.pollingInterval
        storage.workflowsEnabled = s.workflowsEnabled
        storage.autoBackupEnabled = s.autoBackupEnabled
        storage.deviceStateLoggingEnabled = s.deviceStateLoggingEnabled ?? true

        // Restore secrets
        let sec = bundle.secrets
        if let key = sec.aiApiKey, !key.isEmpty {
            keychainService.save(key: KeychainService.Keys.aiApiKey, value: key)
        }
        // Restore API tokens (prefer multi-token, fall back to legacy single token)
        if let tokens = sec.apiTokens, !tokens.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(tokens),
               let json = String(data: data, encoding: .utf8) {
                keychainService.save(key: KeychainService.Keys.mcpApiTokens, value: json)
            }
            keychainService.delete(key: KeychainService.Keys.mcpApiToken)
        } else if let token = sec.mcpApiToken, !token.isEmpty {
            // Legacy backup — migrate single token
            let migrated = APIToken(name: "Default", token: token)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode([migrated]),
               let json = String(data: data, encoding: .utf8) {
                keychainService.save(key: KeychainService.Keys.mcpApiTokens, value: json)
            }
            keychainService.delete(key: KeychainService.Keys.mcpApiToken)
        }
        if let secret = sec.webhookSecret, !secret.isEmpty {
            keychainService.save(key: KeychainService.Keys.webhookSecret, value: secret)
        }
        if let url = sec.webhookURL, !url.isEmpty {
            keychainService.save(key: KeychainService.Keys.webhookURL, value: url)
            storage.webhookURL = url
        } else {
            keychainService.delete(key: KeychainService.Keys.webhookURL)
            storage.webhookURL = nil
        }

        // Restore workflows, then migrate device UUIDs that may differ on this machine
        await workflowStorageService.replaceAll(workflows: bundle.workflows)

        let currentDevices = homeKitManager.cachedDevices
        if !currentDevices.isEmpty {
            let (migratedWorkflows, totalRemapped, _) = WorkflowMigrationService.migrateAll(bundle.workflows, using: currentDevices)
            if totalRemapped > 0 {
                await workflowStorageService.replaceAll(workflows: migratedWorkflows)
            }
        }

        // Restore device config
        await configService.replaceAll(configs: bundle.deviceConfig)
    }

}

// MARK: - Errors

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidFormat(String)
    case cloudNotAvailable
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Backup format version \(v) is not supported. Please update the app."
        case .invalidFormat(let detail):
            return "Invalid backup file: \(detail)"
        case .cloudNotAvailable:
            return "iCloud is not available. Please sign in to iCloud in System Settings."
        case .notSignedIn:
            return "Please sign in with Apple to use iCloud backup."
        }
    }
}
