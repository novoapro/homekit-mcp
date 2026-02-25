import Foundation

/// Protocol abstracting StorageService for dependency injection and testability.
@MainActor
protocol StorageServiceProtocol: AnyObject {
    // MARK: - Published Settings
    var webhookURL: String? { get set }
    var mcpServerPort: Int { get set }
    var webhookEnabled: Bool { get set }
    var mcpServerEnabled: Bool { get set }
    var mcpProtocolEnabled: Bool { get set }
    var restApiEnabled: Bool { get set }
    var hideRoomNameInTheApp: Bool { get set }
    var detailedLogsEnabled: Bool { get set }
    var aiEnabled: Bool { get set }
    var aiProvider: AIProvider { get set }
    var aiModelId: String { get set }
    var aiSystemPrompt: String { get set }
    var mcpServerBindAddress: String { get set }
    var corsEnabled: Bool { get set }
    var corsAllowedOrigins: [String] { get set }
    var pollingEnabled: Bool { get set }
    var pollingInterval: Int { get set }
    var workflowsEnabled: Bool { get set }
    var autoBackupEnabled: Bool { get set }
    var webhookPrivateIPAllowlist: [String] { get set }
    var registryMigrationCompleted: Bool { get set }
    var workflowSyncEnabled: Bool { get set }
    var sunEventLatitude: Double { get set }
    var sunEventLongitude: Double { get set }
    var sunEventZipCode: String { get set }
    var sunEventCityName: String { get set }
    var deviceStateLoggingEnabled: Bool { get set }
    var logOnlyWebhookDevices: Bool { get set }
    var logAccessEnabled: Bool { get set }
    var logCacheSize: Int { get set }
    var websocketEnabled: Bool { get set }

    // MARK: - Derived
    func isWebhookConfigured() -> Bool

    // MARK: - Nonisolated Reads (safe to call from any context)
    nonisolated func readHideRoomName() -> Bool
    nonisolated func readWebhookURL() -> String?
    nonisolated func readWebhookEnabled() -> Bool
    nonisolated func readDetailedLogsEnabled() -> Bool
    nonisolated func readAIEnabled() -> Bool
    nonisolated func readAIProvider() -> AIProvider
    nonisolated func readAIModelId() -> String
    nonisolated func readAISystemPrompt() -> String
    nonisolated func readBindAddress() -> String
    nonisolated func readCorsEnabled() -> Bool
    nonisolated func readCorsAllowedOrigins() -> [String]
    nonisolated func readPollingEnabled() -> Bool
    nonisolated func readPollingInterval() -> Int
    nonisolated func readWorkflowsEnabled() -> Bool
    nonisolated func readMCPProtocolEnabled() -> Bool
    nonisolated func readRestApiEnabled() -> Bool
    nonisolated func readRegistryMigrationCompleted() -> Bool
    nonisolated func readWorkflowSyncEnabled() -> Bool
    nonisolated func readWebhookPrivateIPAllowlist() -> [String]
    nonisolated func readSunEventLatitude() -> Double
    nonisolated func readSunEventLongitude() -> Double
    nonisolated func readSunEventZipCode() -> String
    nonisolated func readSunEventCityName() -> String
    nonisolated func readDeviceStateLoggingEnabled() -> Bool
    nonisolated func readLogOnlyWebhookDevices() -> Bool
    nonisolated func readLogAccessEnabled() -> Bool
    nonisolated func readLogCacheSize() -> Int
    nonisolated func readWebsocketEnabled() -> Bool
}
