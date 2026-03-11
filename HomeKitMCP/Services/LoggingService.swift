import Foundation
import Combine

actor LoggingService: LoggingServiceProtocol {
    /// Ring buffer: append to end (O(1)), trim from start when full, reverse on read.
    private var logs: [StateChangeLog] = []
    private let storage: any StorageServiceProtocol
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private var maxLogs: Int { storage.readLogCacheSize() }

    nonisolated let logsSubject = PassthroughSubject<[StateChangeLog], Never>()
    nonisolated let logEntrySubject = PassthroughSubject<StateChangeLog, Never>()
    nonisolated let logUpdatedSubject = PassthroughSubject<StateChangeLog, Never>()
    nonisolated let logsClearedSubject = PassthroughSubject<Void, Never>()

    init(storage: any StorageServiceProtocol) {
        self.storage = storage
        let appDir = FileManager.appSupportDirectory
        self.fileURL = appDir.appendingPathComponent("logs.json")

        let limit = storage.readLogCacheSize()
        if let data = try? Data(contentsOf: fileURL),
           var saved = try? JSONDecoder.iso8601.decode([StateChangeLog].self, from: data) {
            // Trim to current cache size in case user reduced it
            if saved.count > limit {
                saved = Array(saved.suffix(limit))
            }
            self.logs = saved
        }
    }

    func logEntry(_ entry: StateChangeLog) {
        appendEntry(entry.truncatingLargeFields())
    }

    /// Updates an existing log entry by ID (e.g., when a running workflow completes).
    /// If not found, appends as a new entry.
    func updateEntry(_ entry: StateChangeLog) {
        let truncated = entry.truncatingLargeFields()
        if let index = logs.firstIndex(where: { $0.id == truncated.id }) {
            logs[index] = truncated
        } else {
            logs.append(truncated)
            if logs.count > maxLogs {
                logs.removeFirst()
            }
        }
        logsSubject.send(logs.reversed())
        logUpdatedSubject.send(truncated)
        debouncedSave()
    }

    /// Removes a log entry by its ID (e.g., to suppress a "running" entry for a skipped workflow).
    func removeEntry(id: UUID) {
        logs.removeAll { $0.id == id }
        logsSubject.send(logs.reversed())
        debouncedSave()
    }

    /// O(1) append; trims oldest entry when the buffer is full.
    private func appendEntry(_ entry: StateChangeLog) {
        logs.append(entry)
        if logs.count > maxLogs {
            logs.removeFirst()  // O(n) but rare — only when buffer is full
        }
        logsSubject.send(logs.reversed())
        logEntrySubject.send(entry)
        debouncedSave()
    }

    /// Returns logs in newest-first order (reversed once on read, not on every insert).
    func getLogs() -> [StateChangeLog] {
        return logs.reversed()
    }

    /// Returns workflow execution logs for a specific workflow, newest-first.
    func getLogs(forWorkflowId id: UUID) -> [StateChangeLog] {
        logs.reversed().filter {
            ($0.category == .workflowExecution || $0.category == .workflowError) &&
            $0.workflowExecution?.workflowId == id
        }
    }

    func clearLogs() {
        logs.removeAll()
        logsSubject.send(logs)
        logsClearedSubject.send()
        saveNow()
    }

    /// Clears logs matching any of the given categories.
    func clearLogs(forCategories categories: Set<LogCategory>) {
        logs.removeAll { categories.contains($0.category) }
        logsSubject.send(logs.reversed())
        logsClearedSubject.send()
        debouncedSave()
    }

    /// Clears workflow execution logs for a specific workflow.
    func clearLogs(forWorkflowId id: UUID) {
        logs.removeAll {
            ($0.category == .workflowExecution || $0.category == .workflowError) &&
            $0.workflowExecution?.workflowId == id
        }
        logsSubject.send(logs.reversed())
        logsClearedSubject.send()
        debouncedSave()
    }

    /// Debounce saves: wait 2 seconds of inactivity before writing to disk.
    /// This avoids thrashing the filesystem when many state changes arrive in bursts.
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
            AppLogger.general.error("Failed to save logs: \(error)")
        }
    }
}
