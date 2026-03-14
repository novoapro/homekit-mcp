import Foundation
import Combine

actor LoggingService: LoggingServiceProtocol {
    /// Stored newest-first: insert at index 0, trim from end when full.
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
                saved = Array(saved.prefix(limit))
            }
            self.logs = saved
        }
    }

    func logEntry(_ entry: StateChangeLog) {
        appendEntry(entry.truncatingLargeFields())
    }

    /// Updates an existing log entry by ID (e.g., when a running automation completes).
    /// Moves the entry to the top (newest position) since it's the latest update.
    /// If not found, inserts as a new entry at the top.
    func updateEntry(_ entry: StateChangeLog) {
        let truncated = entry.truncatingLargeFields()
        if let index = logs.firstIndex(where: { $0.id == truncated.id }) {
            logs.remove(at: index)
        }
        logs.insert(truncated, at: 0)
        if logs.count > maxLogs {
            logs.removeLast()
        }
        logsSubject.send(logs)
        logUpdatedSubject.send(truncated)
        debouncedSave()
    }

    /// Removes a log entry by its ID (e.g., to suppress a "running" entry for a skipped automation).
    func removeEntry(id: UUID) {
        logs.removeAll { $0.id == id }
        logsSubject.send(logs)
        debouncedSave()
    }

    /// Inserts newest entry at the front; trims oldest from the end when full.
    private func appendEntry(_ entry: StateChangeLog) {
        logs.insert(entry, at: 0)
        if logs.count > maxLogs {
            logs.removeLast()
        }
        logsSubject.send(logs)
        logEntrySubject.send(entry)
        debouncedSave()
    }

    /// Returns logs in newest-first order (already stored this way).
    func getLogs() -> [StateChangeLog] {
        return logs
    }

    /// Returns automation execution logs for a specific automation, newest-first.
    func getLogs(forAutomationId id: UUID) -> [StateChangeLog] {
        logs.filter {
            ($0.category == .automationExecution || $0.category == .automationError) &&
            $0.automationExecution?.automationId == id
        }
    }

    /// Marks any persisted automation execution logs still in `.running` status as failed.
    /// Called on startup to clean up stale entries from a previous session that never completed
    /// (e.g., app was quit while a automation was executing).
    func cleanupStaleRunningEntries() {
        var changed = false
        for i in 0..<logs.count {
            guard let execution = logs[i].automationExecution,
                  execution.status == .running else { continue }
            var updated = execution
            updated.status = .failure
            updated.errorMessage = "Interrupted — app was quit while automation was running"
            updated.completedAt = updated.triggeredAt
            // Re-wrap in the correct payload/category
            logs[i] = StateChangeLog(
                id: updated.id,
                timestamp: updated.triggeredAt,
                category: .automationError,
                payload: .automationError(updated)
            )
            changed = true
        }
        if changed {
            logsSubject.send(logs)
            saveNow()
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
        logsSubject.send(logs)
        logsClearedSubject.send()
        debouncedSave()
    }

    /// Clears automation execution logs for a specific automation.
    func clearLogs(forAutomationId id: UUID) {
        logs.removeAll {
            ($0.category == .automationExecution || $0.category == .automationError) &&
            $0.automationExecution?.automationId == id
        }
        logsSubject.send(logs)
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
