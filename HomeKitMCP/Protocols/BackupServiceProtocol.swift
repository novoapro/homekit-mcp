import Foundation

/// Protocol abstracting BackupService for dependency injection and testability.
@MainActor
protocol BackupServiceProtocol: AnyObject {
    var isBackingUp: Bool { get }
    var isRestoring: Bool { get }
    var lastError: String? { get }

    func createBackup() async throws -> BackupBundle
    func restoreBackup(_ bundle: BackupBundle) async throws
}
