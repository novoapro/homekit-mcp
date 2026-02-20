import Foundation
import Combine

actor WorkflowExecutionLogService {
    private var logs: [WorkflowExecutionLog] = []
    private let maxLogs = 500
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let logsSubject = PassthroughSubject<[WorkflowExecutionLog], Never>()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
        self.fileURL = appDir.appendingPathComponent("workflow-logs.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? Self.decoder.decode([WorkflowExecutionLog].self, from: data) {
            self.logs = saved
        }
    }

    func log(_ execution: WorkflowExecutionLog) {
        logs.insert(execution, at: 0)

        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }

        logsSubject.send(logs)
        debouncedSave()
    }

    func getLogs() -> [WorkflowExecutionLog] {
        logs
    }

    func getLogs(forWorkflow id: UUID) -> [WorkflowExecutionLog] {
        logs.filter { $0.workflowId == id }
    }

    func clearLogs() {
        logs.removeAll()
        logsSubject.send(logs)
        saveNow()
    }

    func clearLogs(forWorkflow id: UUID) {
        logs.removeAll { $0.workflowId == id }
        logsSubject.send(logs)
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
            let data = try Self.encoder.encode(logs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.general.error("Failed to save workflow execution logs: \(error)")
        }
    }
}
