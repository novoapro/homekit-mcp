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
    let deviceConfig: [String: CharacteristicConfiguration]

    static let currentFormatVersion = 1
}

// MARK: - Settings Snapshot

struct BackupSettings: Codable {
    let mcpServerPort: Int
    let webhookEnabled: Bool
    let mcpServerEnabled: Bool
    let hideRoomNameInTheApp: Bool
    let detailedLogsEnabled: Bool
    let aiEnabled: Bool
    let aiProvider: String
    let aiModelId: String
    let mcpServerBindAddress: String
    let sunEventLatitude: Double
    let sunEventLongitude: Double
    let pollingEnabled: Bool
    let pollingInterval: Int
    let workflowsEnabled: Bool
    let autoBackupEnabled: Bool
    let deviceStateLoggingEnabled: Bool?
}

// MARK: - Secrets (plain JSON)

struct BackupSecrets: Codable {
    let aiApiKey: String?
    let mcpApiToken: String?
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
