import Foundation

/// Protocol abstracting MCPServer for dependency injection and testability.
protocol MCPServerProtocol: AnyObject {
    @MainActor var isRunning: Bool { get }
    @MainActor var connectedClients: Int { get }
    @MainActor var lastError: String? { get }

    func start() async throws
    func stop()
}
