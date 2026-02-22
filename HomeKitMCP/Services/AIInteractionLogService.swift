import Combine
import Foundation

actor AIInteractionLogService {
    private var logs: [AIInteractionLog] = []
    private let maxLogs = 50
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let logsSubject = PassthroughSubject<[AIInteractionLog], Never>()

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
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appDir.path)
        fileURL = appDir.appendingPathComponent("ai-interaction-logs.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? Self.decoder.decode([AIInteractionLog].self, from: data)
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
            let data = try Self.encoder.encode(logs)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            AppLogger.general.error("Failed to save AI interaction logs: \(error)")
        }
    }
}
