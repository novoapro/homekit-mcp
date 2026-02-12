import Foundation
import Combine

actor WebhookService {
    private let storage: StorageService
    private let loggingService: LoggingService
    private let maxRetries = 3

    /// Observable status published on the main actor for UI consumption.
    nonisolated let statusSubject = CurrentValueSubject<WebhookStatus, Never>(.idle)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(storage: StorageService, loggingService: LoggingService) {
        self.storage = storage
        self.loggingService = loggingService
    }

    func sendStateChange(_ change: StateChange) async {
        let (urlString, webhookEnabled) = await MainActor.run { (storage.webhookURL, storage.webhookEnabled) }
        guard webhookEnabled,
              let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }

        let displayName = CharacteristicTypes.displayName(for: change.characteristicType)

        let payload = WebhookPayload(
            timestamp: change.timestamp,
            deviceId: change.deviceId,
            deviceName: change.deviceName,
            characteristicType: change.characteristicType,
            characteristicName: displayName,
            oldValue: change.oldValue.map { AnyCodable($0) },
            newValue: change.newValue.map { AnyCodable($0) }
        )

        await send(to: url, payload: payload, deviceName: change.deviceName)
    }

    /// Send a test webhook to verify the configured URL works.
    func sendTest() async -> Bool {
        let urlString = await MainActor.run { storage.webhookURL }
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            statusSubject.send(.lastFailure(date: Date(), error: "No webhook URL configured"))
            return false
        }

        let payload = WebhookPayload(
            timestamp: Date(),
            deviceId: "test",
            deviceName: "Test Device",
            characteristicType: "test",
            characteristicName: "Test",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        statusSubject.send(.sending)
        return await sendOnce(to: url, payload: payload)
    }

    private func send(to url: URL, payload: WebhookPayload, attempt: Int = 1, deviceName: String) async {
        statusSubject.send(.sending)

        do {
            let (data, response) = try await performRequest(url: url, payload: payload)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw WebhookError.httpError(statusCode: statusCode)
            }

            statusSubject.send(.lastSuccess(date: Date()))
        } catch {
            if attempt < maxRetries {
                let delay = pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await send(to: url, payload: payload, attempt: attempt + 1, deviceName: deviceName)
            } else {
                let errorDesc = error.localizedDescription
                statusSubject.send(.lastFailure(date: Date(), error: errorDesc))

                let logEntry = StateChangeLog(
                    id: UUID(),
                    timestamp: Date(),
                    deviceId: payload.deviceId,
                    deviceName: deviceName,
                    characteristicType: payload.characteristicType,
                    oldValue: payload.oldValue,
                    newValue: payload.newValue,
                    category: .webhookError,
                    errorDetails: "Webhook failed after \(maxRetries) retries to \(url.absoluteString): \(errorDesc)"
                )
                await loggingService.logEntry(logEntry)
            }
        }
    }

    /// Single attempt, returns success/failure. Used for test sends.
    private func sendOnce(to url: URL, payload: WebhookPayload) async -> Bool {
        do {
            let (_, response) = try await performRequest(url: url, payload: payload)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorDesc = "HTTP \(statusCode)"
                statusSubject.send(.lastFailure(date: Date(), error: errorDesc))
                
                // Log the test failure
                let logEntry = StateChangeLog(
                    id: UUID(),
                    timestamp: Date(),
                    deviceId: "test",
                    deviceName: "Test Device",
                    characteristicType: "test",
                    oldValue: nil,
                    newValue: nil,
                    category: .webhookError,
                    errorDetails: "Test webhook failed: \(errorDesc)"
                )
                await loggingService.logEntry(logEntry)
                
                return false
            }

            statusSubject.send(.lastSuccess(date: Date()))
            return true
        } catch {
            let errorDesc = error.localizedDescription
            statusSubject.send(.lastFailure(date: Date(), error: errorDesc))
            
            // Log the test failure
            let logEntry = StateChangeLog(
                id: UUID(),
                timestamp: Date(),
                deviceId: "test",
                deviceName: "Test Device",
                characteristicType: "test",
                oldValue: nil,
                newValue: nil,
                category: .webhookError,
                errorDetails: "Test webhook failed: \(errorDesc)"
            )
            await loggingService.logEntry(logEntry)
            
            return false
        }
    }

    private func performRequest(url: URL, payload: WebhookPayload) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try Self.encoder.encode(payload)
        return try await URLSession.shared.data(for: request)
    }
}

// MARK: - Models

struct WebhookPayload: Codable {
    let timestamp: Date
    let deviceId: String
    let deviceName: String
    let characteristicType: String
    let characteristicName: String
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
}

enum WebhookStatus: Equatable {
    case idle
    case sending
    case lastSuccess(date: Date)
    case lastFailure(date: Date, error: String)
}

enum WebhookError: LocalizedError {
    case httpError(statusCode: Int)
    case noURL

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP error \(code)"
        case .noURL: return "No webhook URL configured"
        }
    }
}
