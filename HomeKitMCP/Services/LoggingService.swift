import Foundation
import Combine

actor LoggingService {
    private var logs: [StateChangeLog] = []
    private let maxLogs = 500
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let logsSubject = PassthroughSubject<[StateChangeLog], Never>()

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
        self.fileURL = appDir.appendingPathComponent("logs.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? Self.decoder.decode([StateChangeLog].self, from: data) {
            self.logs = saved
        }
    }

    func log(_ change: StateChange) {
        let entry = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            deviceId: change.deviceId,
            deviceName: change.deviceName,
            serviceId: change.serviceId,
            serviceName: change.serviceName,
            characteristicType: change.characteristicType,
            oldValue: change.oldValue.map { AnyCodable($0) },
            newValue: change.newValue.map { AnyCodable($0) }
        )

        logs.insert(entry, at: 0)

        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }

        logsSubject.send(logs)
        debouncedSave()
    }

    func logEntry(_ entry: StateChangeLog) {
        logs.insert(entry, at: 0)

        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }

        logsSubject.send(logs)
        debouncedSave()
    }

    func getLogs() -> [StateChangeLog] {
        return logs
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
            let data = try Self.encoder.encode(logs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save logs: \(error)")
        }
    }
}
