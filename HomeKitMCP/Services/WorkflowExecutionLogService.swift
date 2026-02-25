import Combine
import Foundation

actor WorkflowExecutionLogService: WorkflowExecutionLogServiceProtocol {
    private var logs: [WorkflowExecutionLog] = []
    private let maxLogs = 500
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let logsSubject = PassthroughSubject<[WorkflowExecutionLog], Never>()
    nonisolated let logAddedSubject = PassthroughSubject<WorkflowExecutionLog, Never>()
    nonisolated let logUpdatedSubject = PassthroughSubject<WorkflowExecutionLog, Never>()

    init() {
        let appDir = FileManager.appSupportDirectory
        fileURL = appDir.appendingPathComponent("workflow-logs.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.iso8601.decode([WorkflowExecutionLog].self, from: data)
        {
            logs = saved
        }
    }

    func log(_ execution: WorkflowExecutionLog) {
        logs.insert(execution, at: 0)

        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }

        logsSubject.send(logs)
        logAddedSubject.send(execution)
        debouncedSave()
    }

    /// Updates an existing log entry (e.g., when a running workflow completes).
    func update(_ execution: WorkflowExecutionLog) {
        if let index = logs.firstIndex(where: { $0.id == execution.id }) {
            logs[index] = execution
        } else {
            logs.insert(execution, at: 0)
        }

        logsSubject.send(logs)
        logUpdatedSubject.send(execution)
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
            let data = try JSONEncoder.iso8601.encode(logs)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            AppLogger.general.error("Failed to save workflow execution logs: \(error)")
        }
    }
}
