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
    private let loggingService: LoggingService
    private let deviceRegistryService: DeviceRegistryService

    init(
        storage: StorageService,
        keychainService: KeychainService,
        configService: DeviceConfigurationService,
        workflowStorageService: WorkflowStorageService,
        homeKitManager: HomeKitManager,
        loggingService: LoggingService,
        deviceRegistryService: DeviceRegistryService = DeviceRegistryService()
    ) {
        self.storage = storage
        self.keychainService = keychainService
        self.configService = configService
        self.workflowStorageService = workflowStorageService
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.deviceRegistryService = deviceRegistryService
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
            corsEnabled: storage.corsEnabled,
            corsAllowedOrigins: storage.corsAllowedOrigins,
            sunEventLatitude: storage.sunEventLatitude,
            sunEventLongitude: storage.sunEventLongitude,
            sunEventZipCode: storage.sunEventZipCode,
            sunEventCityName: storage.sunEventCityName,
            pollingEnabled: storage.pollingEnabled,
            pollingInterval: storage.pollingInterval,
            workflowsEnabled: storage.workflowsEnabled,
            autoBackupEnabled: storage.autoBackupEnabled,
            autoBackupIntervalHours: storage.autoBackupIntervalHours,
            deviceStateLoggingEnabled: storage.deviceStateLoggingEnabled,
            logOnlyWebhookDevices: storage.logOnlyWebhookDevices,
            logCacheSize: storage.logCacheSize
        )

        let secrets = BackupSecrets(
            aiApiKey: keychainService.read(key: KeychainService.Keys.aiApiKey),
            mcpApiToken: nil,
            apiTokens: keychainService.getAPITokens(),
            webhookSecret: keychainService.read(key: KeychainService.Keys.webhookSecret),
            webhookURL: keychainService.read(key: KeychainService.Keys.webhookURL)
        )

        // Normalize workflow IDs to stable registry IDs before export
        var workflows = await workflowStorageService.getAllWorkflows()
        let (normalizedExportWorkflows, exportNormalizedCount) = WorkflowMigrationService.migrateToStableIds(
            workflows, registry: deviceRegistryService
        )
        if exportNormalizedCount > 0 {
            workflows = normalizedExportWorkflows
            await workflowStorageService.replaceAll(workflows: normalizedExportWorkflows)
            AppLogger.registry.info("Backup export: normalized \(exportNormalizedCount) workflow ID reference(s) to stable IDs")
        }

        // Capture the full registry snapshot
        let registrySnapshot = await deviceRegistryService.snapshot()

        // Device config keys transformed from HomeKit UUIDs to stable IDs
        let deviceConfig = transformConfigKeysToStableIds(await configService.getAllConfigs())

        return BackupBundle(
            formatVersion: BackupBundle.currentFormatVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            createdAt: Date(),
            deviceName: ProcessInfo.processInfo.hostName,
            backupId: UUID(),
            settings: settings,
            secrets: secrets,
            workflows: workflows,
            registry: registrySnapshot,
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
        storage.mcpServerBindAddress = NetworkInterfaceEnumerator.resolvedBindAddress(s.mcpServerBindAddress)
        storage.corsEnabled = s.corsEnabled ?? true
        storage.corsAllowedOrigins = s.corsAllowedOrigins ?? []
        storage.sunEventLatitude = s.sunEventLatitude
        storage.sunEventLongitude = s.sunEventLongitude
        storage.sunEventZipCode = s.sunEventZipCode ?? ""
        storage.sunEventCityName = s.sunEventCityName ?? ""
        storage.pollingEnabled = s.pollingEnabled
        storage.pollingInterval = s.pollingInterval
        storage.workflowsEnabled = s.workflowsEnabled
        storage.autoBackupEnabled = s.autoBackupEnabled
        storage.autoBackupIntervalHours = s.autoBackupIntervalHours ?? 24
        storage.deviceStateLoggingEnabled = s.deviceStateLoggingEnabled ?? true
        storage.logOnlyWebhookDevices = s.logOnlyWebhookDevices ?? false
        storage.logCacheSize = s.logCacheSize ?? 500

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

        // Restore workflows
        await workflowStorageService.replaceAll(workflows: bundle.workflows)

        // Import the backup's registry and consolidate with local HomeKit devices.
        let consolidation = await deviceRegistryService.importAndConsolidate(
            bundle.registry,
            currentDevices: homeKitManager.cachedDevices,
            currentScenes: homeKitManager.cachedScenes
        )

        // Normalize any remaining HomeKit UUIDs in workflows to stable IDs.
        // After consolidation, the registry has the correct mappings.
        let restoredWorkflows = await workflowStorageService.getAllWorkflows()
        let (normalizedRestoreWorkflows, restoreNormalizedCount) = WorkflowMigrationService.migrateToStableIds(
            restoredWorkflows, registry: deviceRegistryService
        )
        if restoreNormalizedCount > 0 {
            await workflowStorageService.replaceAll(workflows: normalizedRestoreWorkflows)
            AppLogger.registry.info("Backup restore: normalized \(restoreNormalizedCount) workflow ID reference(s) to stable IDs")
        }

        // Deep validation: check all serviceId + characteristicType references against the registry.
        let latestWorkflows = await workflowStorageService.getAllWorkflows()
        let validation = await WorkflowMigrationService.validateAndRepairReferences(
            latestWorkflows, registry: deviceRegistryService
        )
        if !validation.autoFixed.isEmpty {
            await workflowStorageService.replaceAll(workflows: validation.updatedWorkflows)
            AppLogger.registry.info("Backup restore validation: auto-fixed \(validation.autoFixed.count) issue(s)")
        }
        if !validation.unresolvable.isEmpty {
            AppLogger.registry.warning("Backup restore validation: \(validation.unresolvable.count) unresolvable issue(s)")
            for issue in validation.unresolvable {
                let logEntry = StateChangeLog.serverError(
                    errorDetails: "[\(issue.workflowName)] Restore: \(issue.location): \(issue.detail)"
                )
                await loggingService.logEntry(logEntry)
            }
        }

        // Restore device config: keys are stable IDs, transform back to local HomeKit UUIDs
        let localConfig = transformConfigKeysToHomeKitIds(bundle.deviceConfig)
        await configService.replaceAll(configs: localConfig)

        // Log consolidation summary
        let summary = buildConsolidationSummary(
            workflowCount: bundle.workflows.count,
            consolidation: consolidation,
            validationAutoFixed: validation.autoFixed.count,
            validationUnresolvable: validation.unresolvable.count
        )
        let summaryEntry = StateChangeLog.backupRestore(
            subtype: "restore-summary",
            summary: summary
        )
        await loggingService.logEntry(summaryEntry)
    }

    // MARK: - Helpers

    /// Transforms device config keys from HomeKit UUIDs to stable IDs for backup export.
    private func transformConfigKeysToStableIds(_ configs: [String: CharacteristicConfiguration]) -> [String: CharacteristicConfiguration] {
        var result: [String: CharacteristicConfiguration] = [:]
        for (key, value) in configs {
            let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else {
                result[key] = value
                continue
            }
            let stableDeviceId = deviceRegistryService.readStableDeviceId(parts[0]) ?? parts[0]
            let stableServiceId = deviceRegistryService.readStableServiceId(parts[1]) ?? parts[1]
            let stableCharId = deviceRegistryService.readStableCharacteristicId(parts[2]) ?? parts[2]
            result["\(stableDeviceId):\(stableServiceId):\(stableCharId)"] = value
        }
        return result
    }

    /// Transforms device config keys from stable IDs back to HomeKit UUIDs for restore.
    /// Uses the registry (already consolidated) to resolve stable → HomeKit IDs.
    /// Entries that can't be resolved (unresolved devices) are dropped.
    private func transformConfigKeysToHomeKitIds(_ configs: [String: CharacteristicConfiguration]) -> [String: CharacteristicConfiguration] {
        var result: [String: CharacteristicConfiguration] = [:]
        for (key, value) in configs {
            let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else {
                result[key] = value
                continue
            }
            guard let hkDeviceId = deviceRegistryService.readHomeKitDeviceId(parts[0]),
                  let hkServiceId = deviceRegistryService.readHomeKitServiceId(parts[1]),
                  let hkCharId = deviceRegistryService.readHomeKitCharacteristicId(parts[2]) else {
                continue // Device is unresolved — skip this config entry
            }
            result["\(hkDeviceId):\(hkServiceId):\(hkCharId)"] = value
        }
        return result
    }

    private func buildConsolidationSummary(workflowCount: Int, consolidation: ConsolidationResult, validationAutoFixed: Int = 0, validationUnresolvable: Int = 0) -> String {
        var parts: [String] = ["Restored \(workflowCount) workflow(s) with registry."]
        parts.append("Devices: \(consolidation.matchedDevices) matched, \(consolidation.unmatchedDevices) unresolved, \(consolidation.newDevices) new local.")
        parts.append("Scenes: \(consolidation.matchedScenes) matched, \(consolidation.unmatchedScenes) unresolved, \(consolidation.newScenes) new local.")
        if validationAutoFixed > 0 {
            parts.append("Validation: auto-fixed \(validationAutoFixed) workflow reference(s).")
        }
        if validationUnresolvable > 0 {
            parts.append("Validation: \(validationUnresolvable) unresolvable reference(s) — check Settings > Device Registry.")
        }
        if consolidation.unmatchedDevices > 0 || consolidation.unmatchedScenes > 0 {
            parts.append("Unresolved entries can be remapped in Settings > Device Registry.")
        }
        return parts.joined(separator: " ")
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
