import Foundation

/// Protocol abstracting CloudBackupService for dependency injection and testability.
@MainActor
protocol CloudBackupServiceProtocol: AnyObject {
    var cloudBackups: [CloudBackupMetadata] { get }
    var isSyncing: Bool { get }
    var lastSyncError: String? { get }
    var autoBackupEnabled: Bool { get set }

    func saveToCloud() async throws
    func fetchCloudBackups() async throws
    func downloadAndRestore(recordName: String) async throws
    func deleteCloudBackup(recordName: String) async throws
    func deleteAllCloudBackups() async throws
}
