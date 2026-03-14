import Foundation

// MARK: - Backup Bundle

struct BackupBundle: Codable {
    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let deviceName: String
    let backupId: UUID

    let settings: BackupSettings
    let secrets: BackupSecrets
    let workflows: [Workflow]
    let registry: RegistrySnapshot

    static let currentFormatVersion = 3
}

// MARK: - Settings Snapshot

struct BackupSettings: Codable {
    let mcpServerPort: Int
    let webhookEnabled: Bool
    let mcpServerEnabled: Bool
    let hideRoomNameInTheApp: Bool
    let loggingEnabled: Bool?
    let mcpLoggingEnabled: Bool?
    let restLoggingEnabled: Bool?
    let webhookLoggingEnabled: Bool?
    let workflowLoggingEnabled: Bool?
    let mcpDetailedLogsEnabled: Bool?
    let restDetailedLogsEnabled: Bool?
    let webhookDetailedLogsEnabled: Bool?
    let detailedLogsEnabled: Bool?  // legacy, for backward-compatible restore
    let aiEnabled: Bool
    let aiProvider: String
    let aiModelId: String
    let mcpServerBindAddress: String
    let corsEnabled: Bool?
    let corsAllowedOrigins: [String]?
    let sunEventLatitude: Double
    let sunEventLongitude: Double
    let sunEventZipCode: String?
    let sunEventCityName: String?
    let pollingEnabled: Bool
    let pollingInterval: Int
    let workflowsEnabled: Bool
    let autoBackupEnabled: Bool
    let autoBackupIntervalHours: Int?
    let deviceStateLoggingEnabled: Bool?
    let logOnlyWebhookDevices: Bool?
    let logCacheSize: Int?
}

// MARK: - Secrets (plain JSON)

struct BackupSecrets: Codable {
    let aiApiKey: String?
    let mcpApiToken: String?          // Legacy single token (for backward compat)
    let apiTokens: [APIToken]?        // Multi-token support
    let webhookSecret: String?
    let webhookURL: String?
}

// MARK: - Cloud Backup Metadata

struct CloudBackupMetadata: Identifiable {
    let id: String          // CKRecord.ID.recordName
    let backupId: UUID
    let createdAt: Date
    let deviceName: String
    let appVersion: String
    let formatVersion: Int
}
