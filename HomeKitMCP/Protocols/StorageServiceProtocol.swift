import Foundation

/// Protocol abstracting StorageService for dependency injection and testability.
@MainActor
protocol StorageServiceProtocol: AnyObject {
    // MARK: - Published Settings
    var webhookURL: String? { get set }
    var mcpServerPort: Int { get set }
    var webhookEnabled: Bool { get set }
    var mcpServerEnabled: Bool { get set }
    var hideRoomNameInTheApp: Bool { get set }
    var detailedLogsEnabled: Bool { get set }
    var aiEnabled: Bool { get set }
    var aiProvider: AIProvider { get set }
    var aiModelId: String { get set }
    var mcpServerBindAddress: String { get set }

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
    nonisolated func readBindAddress() -> String
}
