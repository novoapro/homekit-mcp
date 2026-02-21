import Foundation
import CloudKit
import Combine

@MainActor
class CloudBackupService: ObservableObject, CloudBackupServiceProtocol {
    @Published var cloudBackups: [CloudBackupMetadata] = []
    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var autoBackupEnabled: Bool {
        didSet { storage.autoBackupEnabled = autoBackupEnabled }
    }
    @Published var lastCloudBackupDate: Date?

    private let container: CKContainer
    private let privateDB: CKDatabase
    private let backupService: BackupService
    private let storage: StorageService
    private var cancellables = Set<AnyCancellable>()
    private var autoBackupTask: Task<Void, Never>?
    private var pendingAutoBackup = false

    static let recordType = "Backup"
    static let containerIdentifier = "iCloud.com.novoa.HomeKitMCP"

    init(
        backupService: BackupService,
        storage: StorageService,
        workflowStorageService: WorkflowStorageService
    ) {
        self.backupService = backupService
        self.storage = storage
        self.container = CKContainer(identifier: Self.containerIdentifier)
        self.privateDB = container.privateCloudDatabase
        self.autoBackupEnabled = storage.autoBackupEnabled

        setupAutoBackup(workflowStorageService: workflowStorageService)
    }

    // MARK: - Save to Cloud

    func saveToCloud() async throws {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            let bundle = try await backupService.createBackup()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bundle)

            // Write to temp file for CKAsset
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(bundle.backupId.uuidString).homekitmcp")
            try data.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let record = CKRecord(recordType: Self.recordType)
            record["backupId"] = bundle.backupId.uuidString as CKRecordValue
            record["createdAt"] = bundle.createdAt as CKRecordValue
            record["deviceName"] = bundle.deviceName as CKRecordValue
            record["appVersion"] = bundle.appVersion as CKRecordValue
            record["formatVersion"] = bundle.formatVersion as CKRecordValue
            record["backupData"] = CKAsset(fileURL: tempURL)

            _ = try await privateDB.save(record)
            lastCloudBackupDate = bundle.createdAt
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Fetch Cloud Backups

    func fetchCloudBackups() async throws {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            // Explicitly request only metadata keys (exclude backupData asset for listing)
            let desiredKeys = ["backupId", "createdAt", "deviceName", "appVersion", "formatVersion"]
            let (results, _) = try await privateDB.records(
                matching: query,
                desiredKeys: desiredKeys,
                resultsLimit: 50
            )

            var backups: [CloudBackupMetadata] = []
            AppLogger.general.info("CloudKit query returned \(results.count) records")
            for (recordID, result) in results {
                switch result {
                case .success(let record):
                    if let metadata = Self.metadata(from: record) {
                        backups.append(metadata)
                    } else {
                        AppLogger.general.error("Failed to parse metadata from record \(recordID)")
                    }
                case .failure(let error):
                    AppLogger.general.error("Failed to fetch CloudKit record \(recordID): \(error.localizedDescription)")
                }
            }

            AppLogger.general.info("Parsed \(backups.count) backups from \(results.count) CloudKit records")
            cloudBackups = backups

            // Update last backup date
            lastCloudBackupDate = backups.first?.createdAt
        } catch {
            lastSyncError = error.localizedDescription
            AppLogger.general.error("fetchCloudBackups failed: \(error)")
            throw error
        }
    }

    // MARK: - Download and Restore

    func downloadAndRestore(recordName: String) async throws {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            let recordID = CKRecord.ID(recordName: recordName)
            let record = try await privateDB.record(for: recordID)

            guard let asset = record["backupData"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                throw BackupError.invalidFormat("Cloud backup has no data")
            }

            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bundle = try decoder.decode(BackupBundle.self, from: data)
            try await backupService.restoreBackup(bundle)
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Delete Cloud Backup

    func deleteCloudBackup(recordName: String) async throws {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            let recordID = CKRecord.ID(recordName: recordName)
            try await privateDB.deleteRecord(withID: recordID)
            cloudBackups.removeAll { $0.id == recordName }
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }

    func deleteAllCloudBackups() async throws {
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            let recordIDs = cloudBackups.map { CKRecord.ID(recordName: $0.id) }
            guard !recordIDs.isEmpty else { return }

            // Use CKModifyRecordsOperation for batch delete
            let (_, deleteResults) = try await privateDB.modifyRecords(
                saving: [],
                deleting: recordIDs
            )

            // Check for per-record errors
            var failures: [String] = []
            for (recordID, result) in deleteResults {
                if case .failure(let error) = result {
                    failures.append("\(recordID.recordName): \(error.localizedDescription)")
                }
            }

            if !failures.isEmpty {
                AppLogger.general.error("Some cloud backups failed to delete: \(failures.joined(separator: ", "))")
            }

            cloudBackups.removeAll()
            lastCloudBackupDate = nil
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Auto-Backup

    private func setupAutoBackup(workflowStorageService: WorkflowStorageService) {
        // Listen for workflow changes
        workflowStorageService.workflowsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAutoBackup()
            }
            .store(in: &cancellables)

        // Listen for settings changes
        storage.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAutoBackup()
            }
            .store(in: &cancellables)
    }

    private func scheduleAutoBackup() {
        guard autoBackupEnabled else { return }

        autoBackupTask?.cancel()
        autoBackupTask = Task { [weak self] in
            // Debounce: wait 5 minutes before auto-backing up
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }

            do {
                try await self.saveToCloud()
                AppLogger.general.info("Auto-backup to iCloud completed")
            } catch {
                AppLogger.general.error("Auto-backup to iCloud failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func verifyCloudAvailability() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw BackupError.cloudNotAvailable
        }
    }

    private static func metadata(from record: CKRecord) -> CloudBackupMetadata? {
        // Log all keys present in the record for debugging
        let allKeys = record.allKeys()
        AppLogger.general.info("CloudKit record \(record.recordID.recordName) keys: \(allKeys)")

        guard let backupIdString = record["backupId"] as? String else {
            AppLogger.general.error("Missing or invalid backupId in record \(record.recordID.recordName). Value: \(String(describing: record["backupId"]))")
            return nil
        }
        guard let backupId = UUID(uuidString: backupIdString) else {
            AppLogger.general.error("Invalid UUID string for backupId: \(backupIdString)")
            return nil
        }
        guard let createdAt = record["createdAt"] as? Date else {
            AppLogger.general.error("Missing or invalid createdAt in record \(record.recordID.recordName). Value: \(String(describing: record["createdAt"]))")
            return nil
        }
        guard let deviceName = record["deviceName"] as? String else {
            AppLogger.general.error("Missing or invalid deviceName in record \(record.recordID.recordName). Value: \(String(describing: record["deviceName"]))")
            return nil
        }
        guard let appVersion = record["appVersion"] as? String else {
            AppLogger.general.error("Missing or invalid appVersion in record \(record.recordID.recordName). Value: \(String(describing: record["appVersion"]))")
            return nil
        }

        // CloudKit stores integers as NSNumber — accept both Int and NSNumber
        let formatVersion: Int
        if let num = record["formatVersion"] as? NSNumber {
            formatVersion = num.intValue
        } else if let intVal = record["formatVersion"] as? Int {
            formatVersion = intVal
        } else {
            AppLogger.general.error("Missing or invalid formatVersion in record \(record.recordID.recordName). Value: \(String(describing: record["formatVersion"])), type: \(type(of: record["formatVersion"] as Any))")
            return nil
        }

        AppLogger.general.info("Successfully parsed CloudKit backup: \(backupIdString), device: \(deviceName)")

        return CloudBackupMetadata(
            id: record.recordID.recordName,
            backupId: backupId,
            createdAt: createdAt,
            deviceName: deviceName,
            appVersion: appVersion,
            formatVersion: formatVersion
        )
    }
}
