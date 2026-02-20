import Foundation
import Combine

actor WorkflowStorageService {
    private var workflows: [UUID: Workflow] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let workflowsSubject = PassthroughSubject<[Workflow], Never>()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("HomeKitMCP")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("workflows.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? Self.decoder.decode([Workflow].self, from: data) {
            for workflow in saved {
                self.workflows[workflow.id] = workflow
            }
        }
    }

    // MARK: - CRUD

    func getAllWorkflows() -> [Workflow] {
        Array(workflows.values).sorted { $0.createdAt > $1.createdAt }
    }

    func getWorkflow(id: UUID) -> Workflow? {
        workflows[id]
    }

    func getEnabledWorkflows() -> [Workflow] {
        workflows.values.filter(\.isEnabled).sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func createWorkflow(_ workflow: Workflow) -> Workflow {
        workflows[workflow.id] = workflow
        publishAndSave()
        return workflow
    }

    @discardableResult
    func updateWorkflow(id: UUID, update: (inout Workflow) -> Void) -> Workflow? {
        guard var workflow = workflows[id] else { return nil }
        update(&workflow)
        workflow.updatedAt = Date()
        workflows[id] = workflow
        publishAndSave()
        return workflow
    }

    @discardableResult
    func deleteWorkflow(id: UUID) -> Bool {
        guard workflows.removeValue(forKey: id) != nil else { return false }
        publishAndSave()
        return true
    }

    // MARK: - Metadata Helpers

    func updateMetadata(id: UUID, lastTriggered: Date, incrementExecutions: Bool, resetFailures: Bool) {
        guard var workflow = workflows[id] else { return }
        workflow.metadata.lastTriggeredAt = lastTriggered
        if incrementExecutions {
            workflow.metadata.totalExecutions += 1
        }
        if resetFailures {
            workflow.metadata.consecutiveFailures = 0
        }
        workflows[id] = workflow
        publishAndSave()
    }

    func incrementFailures(id: UUID) {
        guard var workflow = workflows[id] else { return }
        workflow.metadata.consecutiveFailures += 1
        workflows[id] = workflow
        publishAndSave()
    }

    // MARK: - Persistence

    private func publishAndSave() {
        workflowsSubject.send(getAllWorkflows())
        debouncedSave()
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            let allWorkflows = getAllWorkflows()
            let data = try Self.encoder.encode(allWorkflows)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.general.error("Failed to save workflows: \(error)")
        }
    }
}
