import Foundation
import CloudKit
import Combine

/// Per-workflow CloudKit sync service.
///
/// Each workflow is stored as a separate `SyncedWorkflow` CKRecord using stable registry IDs.
/// Outbound: debounced 5-second save after local changes.
/// Inbound: periodic poll for remote changes (every 60 seconds while enabled).
/// Conflict resolution: last-writer-wins using `updatedAt`.
@MainActor
class WorkflowSyncService: ObservableObject {

    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var lastSyncDate: Date?

    private let container: CKContainer
    private let privateDB: CKDatabase
    private let workflowStorageService: WorkflowStorageService
    private let storage: StorageService
    private let deviceRegistryService: DeviceRegistryService
    private let homeKitManager: HomeKitManager
    private var cancellables = Set<AnyCancellable>()
    private var outboundTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// Tracks which workflow IDs we've seen locally, to detect remote additions.
    private var knownWorkflowIds = Set<UUID>()
    /// Prevents re-entrant saves when applying remote changes.
    private var isApplyingRemote = false

    static let recordType = "SyncedWorkflow"
    static let containerIdentifier = "iCloud.com.novoa.HomeKitMCP"

    private let deviceId: String

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(workflowStorageService: WorkflowStorageService, storage: StorageService, deviceRegistryService: DeviceRegistryService, homeKitManager: HomeKitManager) {
        self.workflowStorageService = workflowStorageService
        self.storage = storage
        self.deviceRegistryService = deviceRegistryService
        self.homeKitManager = homeKitManager
        self.container = CKContainer(identifier: Self.containerIdentifier)
        self.privateDB = container.privateCloudDatabase
        self.deviceId = ProcessInfo.processInfo.hostName

        setupSubscriptions()
    }

    // MARK: - Setup

    private func setupSubscriptions() {
        // Watch for local workflow changes → outbound sync
        workflowStorageService.workflowsSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] workflows in
                guard let self else { return }
                Task { @MainActor in
                    guard self.storage.workflowSyncEnabled, !self.isApplyingRemote else { return }
                    self.scheduleOutboundSync(workflows)
                }
            }
            .store(in: &cancellables)

        // Watch for sync toggle changes
        storage.$workflowSyncEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startPolling()
                    // Perform initial sync
                    Task { await self.performFullSync() }
                } else {
                    self.stopPolling()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Outbound Sync

    private func scheduleOutboundSync(_ workflows: [Workflow]) {
        outboundTask?.cancel()
        outboundTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second debounce
            guard !Task.isCancelled else { return }
            await pushWorkflows(workflows)
        }
    }

    private func pushWorkflows(_ workflows: [Workflow]) async {
        guard storage.workflowSyncEnabled else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            var recordsToSave: [CKRecord] = []

            for workflow in workflows {
                let recordName = "syncwf-\(workflow.id.uuidString)"
                let recordID = CKRecord.ID(recordName: recordName)
                let record = CKRecord(recordType: Self.recordType, recordID: recordID)

                let data = try Self.encoder.encode(workflow)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(workflow.id.uuidString).workflow.json")
                try data.write(to: tempURL, options: .atomic)

                record["workflowId"] = workflow.id.uuidString as CKRecordValue
                record["workflowData"] = CKAsset(fileURL: tempURL)
                record["updatedAt"] = (workflow.updatedAt ?? workflow.createdAt) as CKRecordValue
                record["syncVersion"] = 1 as CKRecordValue
                record["originDeviceId"] = deviceId as CKRecordValue
                record["isDeleted"] = 0 as CKRecordValue

                recordsToSave.append(record)
            }

            // Also mark deleted workflows as tombstones
            let localIds = Set(workflows.map(\.id))
            let removedIds = knownWorkflowIds.subtracting(localIds)
            for removedId in removedIds {
                let recordName = "syncwf-\(removedId.uuidString)"
                let recordID = CKRecord.ID(recordName: recordName)
                let record = CKRecord(recordType: Self.recordType, recordID: recordID)
                record["workflowId"] = removedId.uuidString as CKRecordValue
                record["updatedAt"] = Date() as CKRecordValue
                record["originDeviceId"] = deviceId as CKRecordValue
                record["isDeleted"] = 1 as CKRecordValue
                recordsToSave.append(record)
            }

            knownWorkflowIds = localIds

            guard !recordsToSave.isEmpty else { return }

            // Batch save with overwrite policy
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDB.add(operation)
            }

            lastSyncDate = Date()
            lastSyncError = nil

            // Clean up temp files
            for record in recordsToSave {
                if let asset = record["workflowData"] as? CKAsset, let url = asset.fileURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            AppLogger.workflow.info("Workflow sync: pushed \(recordsToSave.count) workflow(s)")
        } catch {
            lastSyncError = error.localizedDescription
            AppLogger.workflow.error("Workflow sync push failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Inbound Sync (Pull)

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                guard !Task.isCancelled else { break }
                await pullRemoteChanges()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pullRemoteChanges() async {
        guard storage.workflowSyncEnabled else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await verifyCloudAvailability()

            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 200)

            var remoteWorkflows: [UUID: (Workflow, Date, Bool)] = [:] // id → (workflow, updatedAt, isDeleted)

            for (_, result) in results {
                guard let record = try? result.get() else { continue }
                let isDeleted = (record["isDeleted"] as? Int ?? 0) == 1
                guard let workflowIdStr = record["workflowId"] as? String,
                      let workflowId = UUID(uuidString: workflowIdStr) else { continue }

                let updatedAt = record["updatedAt"] as? Date ?? Date.distantPast

                if isDeleted {
                    remoteWorkflows[workflowId] = (Workflow(id: workflowId, name: "", triggers: [], blocks: []), updatedAt, true)
                    continue
                }

                guard let asset = record["workflowData"] as? CKAsset,
                      let fileURL = asset.fileURL,
                      let data = try? Data(contentsOf: fileURL),
                      let workflow = try? Self.decoder.decode(Workflow.self, from: data) else { continue }

                remoteWorkflows[workflowId] = (workflow, updatedAt, false)
            }

            // Apply remote changes
            let localWorkflows = await workflowStorageService.getAllWorkflows()
            let localById = Dictionary(uniqueKeysWithValues: localWorkflows.map { ($0.id, $0) })
            var changed = false

            isApplyingRemote = true
            defer { isApplyingRemote = false }

            for (id, (remoteWorkflow, remoteUpdatedAt, isDeleted)) in remoteWorkflows {
                if isDeleted {
                    if localById[id] != nil {
                        await workflowStorageService.deleteWorkflow(id: id)
                        changed = true
                        AppLogger.workflow.info("Workflow sync: deleted '\(id)' from remote tombstone")
                    }
                    continue
                }

                if let localWorkflow = localById[id] {
                    let localUpdatedAt = localWorkflow.updatedAt ?? localWorkflow.createdAt
                    // Last-writer-wins: only apply if remote is newer
                    if remoteUpdatedAt > localUpdatedAt {
                        await workflowStorageService.updateWorkflow(id: id) { workflow in
                            workflow = remoteWorkflow
                        }
                        changed = true
                        AppLogger.workflow.info("Workflow sync: updated '\(remoteWorkflow.name)' from remote")
                    }
                } else {
                    // New workflow from remote
                    await workflowStorageService.createWorkflow(remoteWorkflow)
                    changed = true
                    AppLogger.workflow.info("Workflow sync: added '\(remoteWorkflow.name)' from remote")
                }
            }

            // Update known IDs
            let allLocal = await workflowStorageService.getAllWorkflows()
            knownWorkflowIds = Set(allLocal.map(\.id))

            lastSyncDate = Date()
            lastSyncError = nil

            if changed {
                // Remap foreign stable IDs to local stable IDs so triggers fire correctly.
                // Imported workflows from other machines use that machine's stable IDs, which
                // differ from local ones. Migration matches by name/room and remaps to local IDs.
                let rawDevices = homeKitManager.getAllDevices()
                let rawScenes = homeKitManager.getAllScenes()
                let stableDevices = rawDevices.map { deviceRegistryService.withStableIds($0) }
                let stableScenes = rawScenes.map { deviceRegistryService.withStableIds($0) }

                if !stableDevices.isEmpty || !stableScenes.isEmpty {
                    let migration = WorkflowMigrationService.migrateAll(allLocal, using: stableDevices, scenes: stableScenes)
                    let totalRemapped = migration.totalRemappedDevices + migration.totalRemappedScenes
                    if totalRemapped > 0 {
                        await workflowStorageService.replaceAll(workflows: migration.workflows)
                        AppLogger.workflow.info("Workflow sync: remapped \(migration.totalRemappedDevices) device(s), \(migration.totalRemappedScenes) scene(s)")
                    }
                }

                // Reconcile any remaining foreign stable IDs against local registry
                let workflowsForReconciliation = await workflowStorageService.getAllWorkflows()
                let reconciledCount = await deviceRegistryService.reconcileWorkflowReferences(
                    workflowsForReconciliation,
                    currentDevices: rawDevices,
                    currentScenes: rawScenes
                )
                if reconciledCount > 0 {
                    AppLogger.workflow.info("Workflow sync: reconciled \(reconciledCount) foreign registry references")
                }

                AppLogger.workflow.info("Workflow sync: applied remote changes")
            }
        } catch {
            lastSyncError = error.localizedDescription
            AppLogger.workflow.error("Workflow sync pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Full Sync

    /// Performs a complete sync: pull remote changes first, then push local state.
    func performFullSync() async {
        guard storage.workflowSyncEnabled else { return }
        await pullRemoteChanges()
        let workflows = await workflowStorageService.getAllWorkflows()
        await pushWorkflows(workflows)
    }

    // MARK: - Helpers

    private func verifyCloudAvailability() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw WorkflowSyncError.cloudNotAvailable
        }
    }
}

// MARK: - Errors

enum WorkflowSyncError: LocalizedError {
    case cloudNotAvailable

    var errorDescription: String? {
        switch self {
        case .cloudNotAvailable:
            return "iCloud is not available. Sign in to iCloud to enable workflow sync."
        }
    }
}
