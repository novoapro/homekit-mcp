import Foundation
import Combine
import CommonCrypto

actor WebhookService: WebhookServiceProtocol {
    private let storage: StorageService
    private let loggingService: LoggingService
    private let keychainService: KeychainService
    private let maxRetries = 3
    private var cachedSecrets: [UUID: Data] = [:]

    /// Per-endpoint status published on the main actor for UI consumption.
    nonisolated let endpointStatusSubject = CurrentValueSubject<[UUID: WebhookStatus], Never>([:])

    /// Aggregate status for backward compatibility (most recent send result).
    nonisolated let statusSubject = CurrentValueSubject<WebhookStatus, Never>(.idle)

    init(storage: StorageService, loggingService: LoggingService, keychainService: KeychainService) {
        self.storage = storage
        self.loggingService = loggingService
        self.keychainService = keychainService
    }

    func sendStateChange(_ change: StateChange) async {
        let endpoints = storage.readWebhookEndpoints()
        let matching = endpoints.filter { $0.enabled && !$0.url.isEmpty && $0.matches(deviceId: change.deviceId) }
        guard !matching.isEmpty else { return }

        let displayName = CharacteristicTypes.displayName(for: change.characteristicType)

        let payload = WebhookPayload(
            timestamp: change.timestamp,
            deviceId: change.deviceId,
            deviceName: change.deviceName,
            serviceId: change.serviceId,
            serviceName: change.serviceName,
            characteristicId: change.characteristicId,
            characteristicType: change.characteristicType,
            characteristicName: displayName,
            oldValue: change.oldValue.map { AnyCodable($0) },
            newValue: change.newValue.map { AnyCodable($0) }
        )

        for endpoint in matching {
            guard let url = URL(string: endpoint.url) else { continue }
            await send(to: url, payload: payload, endpointId: endpoint.id, endpointName: endpoint.name, deviceName: change.deviceName, roomName: change.roomName)
        }
    }

    func sendTest(endpointId: UUID) async -> Bool {
        let endpoints = storage.readWebhookEndpoints()
        guard let endpoint = endpoints.first(where: { $0.id == endpointId }),
              !endpoint.url.isEmpty,
              let url = URL(string: endpoint.url) else {
            updateStatus(.lastFailure(date: Date(), error: "No webhook URL configured"), forEndpoint: endpointId)
            return false
        }

        let payload = WebhookPayload(
            timestamp: Date(),
            deviceId: "test",
            deviceName: "Test Device",
            serviceId: nil,
            serviceName: nil,
            characteristicId: nil,
            characteristicType: "test",
            characteristicName: "Test",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        updateStatus(.sending, forEndpoint: endpointId)
        return await sendOnce(to: url, payload: payload, endpointId: endpointId)
    }

    // MARK: - Deprecated single-URL test (kept for protocol conformance)

    func sendTest() async -> Bool {
        let endpoints = storage.readWebhookEndpoints()
        guard let first = endpoints.first(where: { $0.enabled && !$0.url.isEmpty }) else {
            statusSubject.send(.lastFailure(date: Date(), error: "No webhook endpoints configured"))
            return false
        }
        return await sendTest(endpointId: first.id)
    }

    // MARK: - Private Send Logic

    private func send(to url: URL, payload: WebhookPayload, attempt: Int = 1, endpointId: UUID, endpointName: String, deviceName: String, roomName: String? = nil) async {
        updateStatus(.sending, forEndpoint: endpointId)

        do {
            let (_, response) = try await performRequest(url: url, payload: payload, endpointId: endpointId)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw WebhookError.httpError(statusCode: statusCode)
            }

            updateStatus(.lastSuccess(date: Date()), forEndpoint: endpointId)

            if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
                let label = endpointName.isEmpty ? url.host ?? "webhook" : endpointName
                let logEntry = StateChangeLog.webhookCall(
                    deviceId: payload.deviceId,
                    deviceName: deviceName,
                    roomName: roomName,
                    serviceId: payload.serviceId,
                    serviceName: payload.serviceName,
                    characteristicType: payload.characteristicType,
                    oldValue: payload.oldValue,
                    newValue: payload.newValue,
                    unit: CharacteristicTypes.unitForCharacteristicType(payload.characteristicType),
                    summary: "POST [\(label)] \(deviceName) (\(payload.characteristicName))",
                    result: "HTTP \(httpResponse.statusCode) OK",
                    detailedRequest: detailedPayloadJSON(payload)
                )
                await loggingService.logEntry(logEntry)
            }
        } catch {
            if attempt < maxRetries {
                let delay = pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await send(to: url, payload: payload, attempt: attempt + 1, endpointId: endpointId, endpointName: endpointName, deviceName: deviceName, roomName: roomName)
            } else {
                let errorDesc = error.localizedDescription
                updateStatus(.lastFailure(date: Date(), error: errorDesc), forEndpoint: endpointId)

                if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
                    let label = endpointName.isEmpty ? url.host ?? "webhook" : endpointName
                    let logEntry = StateChangeLog.webhookError(
                        deviceId: payload.deviceId,
                        deviceName: deviceName,
                        roomName: roomName,
                        serviceId: payload.serviceId,
                        serviceName: payload.serviceName,
                        characteristicType: payload.characteristicType,
                        oldValue: payload.oldValue,
                        newValue: payload.newValue,
                        unit: CharacteristicTypes.unitForCharacteristicType(payload.characteristicType),
                        summary: "POST [\(label)] \(deviceName) (\(payload.characteristicName))",
                        result: errorDesc,
                        errorDetails: "Failed after \(maxRetries) retries: \(errorDesc)",
                        detailedRequest: detailedPayloadJSON(payload)
                    )
                    await loggingService.logEntry(logEntry)
                }
            }
        }
    }

    private func sendOnce(to url: URL, payload: WebhookPayload, endpointId: UUID) async -> Bool {
        do {
            let (_, response) = try await performRequest(url: url, payload: payload, endpointId: endpointId)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorDesc = "HTTP \(statusCode)"
                updateStatus(.lastFailure(date: Date(), error: errorDesc), forEndpoint: endpointId)

                if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
                    let logEntry = StateChangeLog.webhookError(
                        deviceId: "test",
                        deviceName: "Test Device",
                        characteristicType: "test",
                        summary: "POST Test Device (Test)",
                        result: errorDesc,
                        errorDetails: "Test webhook failed: \(errorDesc)",
                        detailedRequest: detailedPayloadJSON(payload)
                    )
                    await loggingService.logEntry(logEntry)
                }

                return false
            }

            updateStatus(.lastSuccess(date: Date()), forEndpoint: endpointId)

            if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
                let logEntry = StateChangeLog.webhookCall(
                    deviceId: "test",
                    deviceName: "Test Device",
                    characteristicType: "test",
                    summary: "POST Test Device (Test)",
                    result: "HTTP \(httpResponse.statusCode) OK",
                    detailedRequest: detailedPayloadJSON(payload)
                )
                await loggingService.logEntry(logEntry)
            }

            return true
        } catch {
            let errorDesc = error.localizedDescription
            updateStatus(.lastFailure(date: Date(), error: errorDesc), forEndpoint: endpointId)

            if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
                let logEntry = StateChangeLog.webhookError(
                    deviceId: "test",
                    deviceName: "Test Device",
                    characteristicType: "test",
                    summary: "POST Test Device (Test)",
                    result: errorDesc,
                    errorDetails: "Test webhook failed: \(errorDesc)",
                    detailedRequest: detailedPayloadJSON(payload)
                )
                await loggingService.logEntry(logEntry)
            }

            return false
        }
    }

    // MARK: - Status Helpers

    private func updateStatus(_ status: WebhookStatus, forEndpoint endpointId: UUID) {
        var current = endpointStatusSubject.value
        current[endpointId] = status
        endpointStatusSubject.send(current)
        statusSubject.send(status)
    }

    // MARK: - Utilities

    private func detailedPayloadJSON(_ payload: WebhookPayload) -> String? {
        guard storage.readWebhookDetailedLogsEnabled(),
              let data = try? JSONEncoder.iso8601.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func validateURLNotPrivate(_ url: URL) throws {
        guard let host = url.host else { return }

        let lowered = host.lowercased()

        let allowlist = storage.readWebhookPrivateIPAllowlist()
        if allowlist.contains(where: { Self.matchesWildcard(host: lowered, pattern: $0.lowercased()) }) {
            return
        }

        if lowered == "localhost" || lowered == "127.0.0.1" || lowered == "::1" {
            return
        }

        let cfHost = CFHostCreateWithName(kCFAllocatorDefault, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(cfHost, .addresses, nil)
        guard let addresses = CFHostGetAddressing(cfHost, &resolved)?.takeUnretainedValue() as? [Data], resolved.boolValue else {
            return
        }

        for addressData in addresses {
            let isPrivate = addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> Bool in
                guard let sa = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return false }
                if sa.pointee.sa_family == UInt8(AF_INET) {
                    let sin = pointer.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                    let addr = sin.sin_addr.s_addr
                    let a = addr & 0xFF
                    let b = (addr >> 8) & 0xFF
                    if a == 10 { return true }
                    if a == 172 && (b >= 16 && b <= 31) { return true }
                    if a == 192 && b == 168 { return true }
                    if a == 169 && b == 254 { return true }
                    if a == 127 { return true }
                    if addr == 0 { return true }
                }
                return false
            }
            if isPrivate {
                throw WebhookError.ssrfBlocked
            }
        }
    }

    private func performRequest(url: URL, payload: WebhookPayload, endpointId: UUID) async throws -> (Data, URLResponse) {
        try validateURLNotPrivate(url)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = try JSONEncoder.iso8601.encode(payload)
        request.httpBody = body

        let secretData = secretDataForEndpoint(endpointId)
        if let secretData {
            let signature = hmacSHA256(data: body, key: secretData)
            request.addValue("sha256=\(signature)", forHTTPHeaderField: "X-Signature-256")
        }

        return try await URLSession.shared.data(for: request)
    }

    private func secretDataForEndpoint(_ endpointId: UUID) -> Data? {
        if let cached = cachedSecrets[endpointId] { return cached }
        let key = "webhook-secret-\(endpointId.uuidString)"
        let secret = keychainService.getOrCreate(key: key)
        let data = secret.data(using: .utf8)
        if let data { cachedSecrets[endpointId] = data }
        return data
    }

    static func matchesWildcard(host: String, pattern: String) -> Bool {
        if !pattern.contains("*") { return host == pattern }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*") + "$"
        return host.range(of: regex, options: .regularExpression) != nil
    }

    private func hmacSHA256(data: Data, key: Data) -> String {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress, key.count,
                        dataBytes.baseAddress, data.count,
                        &hmac)
            }
        }
        return hmac.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Models

struct WebhookEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var enabled: Bool
    /// Stable device IDs this endpoint listens to. Empty means all observed devices.
    var deviceFilter: Set<String>

    init(id: UUID = UUID(), name: String = "", url: String = "", enabled: Bool = true, deviceFilter: Set<String> = []) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.deviceFilter = deviceFilter
    }

    func matches(deviceId: String) -> Bool {
        deviceFilter.isEmpty || deviceFilter.contains(deviceId)
    }
}

struct WebhookPayload: Codable {
    let timestamp: Date
    let deviceId: String
    let deviceName: String
    let serviceId: String?
    let serviceName: String?
    let characteristicId: String?
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
    case ssrfBlocked

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP error \(code)"
        case .ssrfBlocked: return "Request blocked: URL resolves to a private/internal IP address"
        }
    }
}
