import Combine
import Foundation

actor AIInteractionLogService {
    private var logs: [AIInteractionLog] = []
    private let maxLogs = 50
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let logsSubject = PassthroughSubject<[AIInteractionLog], Never>()

    init() {
        let appDir = FileManager.appSupportDirectory
        fileURL = appDir.appendingPathComponent("ai-interaction-logs.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.iso8601.decode([AIInteractionLog].self, from: data)
        {
            logs = saved
        }
    }

    func log(_ entry: AIInteractionLog) {
        logs.insert(entry, at: 0)

        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }

        logsSubject.send(logs)
        debouncedSave()
    }

    func getLogs() -> [AIInteractionLog] {
        logs
    }

    func clearLogs() {
        logs.removeAll()
        logsSubject.send(logs)
        saveNow()
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
            AppLogger.general.error("Failed to save AI interaction logs: \(error)")
        }
    }
}
