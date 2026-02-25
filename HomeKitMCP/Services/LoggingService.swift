import Foundation
import Combine

actor LoggingService: LoggingServiceProtocol {
    /// Ring buffer: append to end (O(1)), trim from start when full, reverse on read.
    private var logs: [StateChangeLog] = []
    private let storage: StorageService
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private var maxLogs: Int { storage.readLogCacheSize() }

    nonisolated let logsSubject = PassthroughSubject<[StateChangeLog], Never>()
    nonisolated let logEntrySubject = PassthroughSubject<StateChangeLog, Never>()

    init(storage: StorageService) {
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

    func log(_ change: StateChange) {
        let entry = StateChangeLog.stateChange(
            deviceId: change.deviceId,
            deviceName: change.deviceName,
            serviceId: change.serviceId,
            serviceName: change.serviceName,
            characteristicType: change.characteristicType,
            oldValue: change.oldValue.map { AnyCodable($0) },
            newValue: change.newValue.map { AnyCodable($0) }
        )
        appendEntry(entry)
    }

    func logEntry(_ entry: StateChangeLog) {
        appendEntry(entry.truncatingLargeFields())
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

    func clearLogs() {
        logs.removeAll()
        logsSubject.send(logs)
        saveNow()
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
