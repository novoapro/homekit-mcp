import Foundation
import Combine
import CommonCrypto

actor WebhookService: WebhookServiceProtocol {
    private let storage: StorageService
    private let loggingService: LoggingService
    private let keychainService: KeychainService
    private let maxRetries = 3

    /// Observable status published on the main actor for UI consumption.
    nonisolated let statusSubject = CurrentValueSubject<WebhookStatus, Never>(.idle)

    init(storage: StorageService, loggingService: LoggingService, keychainService: KeychainService) {
        self.storage = storage
        self.loggingService = loggingService
        self.keychainService = keychainService
    }

    func sendStateChange(_ change: StateChange) async {
        let urlString = storage.readWebhookURL()
        let webhookEnabled = storage.readWebhookEnabled()
        guard webhookEnabled,
              let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return }

        let displayName = CharacteristicTypes.displayName(for: change.characteristicType)

        let payload = WebhookPayload(
            timestamp: change.timestamp,
            deviceId: change.deviceId,
            deviceName: change.deviceName,
            serviceId: change.serviceId,
            serviceName: change.serviceName,
            characteristicType: change.characteristicType,
            characteristicName: displayName,
            oldValue: change.oldValue.map { AnyCodable($0) },
            newValue: change.newValue.map { AnyCodable($0) }
        )

        await send(to: url, payload: payload, deviceName: change.deviceName, roomName: change.roomName)
    }

    /// Send a test webhook to verify the configured URL works.
    func sendTest() async -> Bool {
        let urlString = storage.readWebhookURL()
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            statusSubject.send(.lastFailure(date: Date(), error: "No webhook URL configured"))
            return false
        }

        let payload = WebhookPayload(
            timestamp: Date(),
            deviceId: "test",
            deviceName: "Test Device",
            serviceId: nil,
            serviceName: nil,
            characteristicType: "test",
            characteristicName: "Test",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        statusSubject.send(.sending)
        return await sendOnce(to: url, payload: payload)
    }

    private func send(to url: URL, payload: WebhookPayload, attempt: Int = 1, deviceName: String, roomName: String? = nil) async {
        statusSubject.send(.sending)

        do {
            let (_, response) = try await performRequest(url: url, payload: payload)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw WebhookError.httpError(statusCode: statusCode)
            }

            statusSubject.send(.lastSuccess(date: Date()))

            if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
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
                    summary: "POST \(deviceName) (\(payload.characteristicName))",
                    result: "HTTP \(httpResponse.statusCode) OK",
                    detailedRequest: detailedPayloadJSON(payload)
                )
                await loggingService.logEntry(logEntry)
            }
        } catch {
            if attempt < maxRetries {
                let delay = pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await send(to: url, payload: payload, attempt: attempt + 1, deviceName: deviceName, roomName: roomName)
            } else {
                let errorDesc = error.localizedDescription
                statusSubject.send(.lastFailure(date: Date(), error: errorDesc))

                if storage.readLoggingEnabled() && storage.readWebhookLoggingEnabled() {
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
                        summary: "POST \(deviceName) (\(payload.characteristicName))",
                        result: errorDesc,
                        errorDetails: "Failed after \(maxRetries) retries: \(errorDesc)",
                        detailedRequest: detailedPayloadJSON(payload)
                    )
                    await loggingService.logEntry(logEntry)
                }
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

            statusSubject.send(.lastSuccess(date: Date()))

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
            statusSubject.send(.lastFailure(date: Date(), error: errorDesc))

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

    /// Returns JSON-encoded payload string only when detailed webhook logs are enabled.
    private func detailedPayloadJSON(_ payload: WebhookPayload) -> String? {
        guard storage.readWebhookDetailedLogsEnabled(),
              let data = try? JSONEncoder.iso8601.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Validates that a URL does not point to a private/internal IP address (SSRF protection).
    private func validateURLNotPrivate(_ url: URL) throws {
        guard let host = url.host else { return }

        let lowered = host.lowercased()

        // Allow hosts matching the user-configured allow list (supports * wildcards)
        let allowlist = storage.readWebhookPrivateIPAllowlist()
        if allowlist.contains(where: { Self.matchesWildcard(host: lowered, pattern: $0.lowercased()) }) {
            return
        }

        // Allow localhost (for the app's own endpoints)
        if lowered == "localhost" || lowered == "127.0.0.1" || lowered == "::1" {
            return
        }

        // Resolve the hostname and check against private ranges
        let cfHost = CFHostCreateWithName(kCFAllocatorDefault, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(cfHost, .addresses, nil)
        guard let addresses = CFHostGetAddressing(cfHost, &resolved)?.takeUnretainedValue() as? [Data], resolved.boolValue else {
            return // If resolution fails, let the request fail naturally
        }

        for addressData in addresses {
            let isPrivate = addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> Bool in
                guard let sa = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return false }
                if sa.pointee.sa_family == UInt8(AF_INET) {
                    let sin = pointer.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                    let addr = sin.sin_addr.s_addr
                    let a = addr & 0xFF
                    let b = (addr >> 8) & 0xFF
                    // 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8
                    if a == 10 { return true }
                    if a == 172 && (b >= 16 && b <= 31) { return true }
                    if a == 192 && b == 168 { return true }
                    if a == 169 && b == 254 { return true }
                    if a == 127 { return true }
                    if addr == 0 { return true } // 0.0.0.0
                }
                return false
            }
            if isPrivate {
                throw WebhookError.ssrfBlocked
            }
        }
    }

    private func performRequest(url: URL, payload: WebhookPayload) async throws -> (Data, URLResponse) {
        try validateURLNotPrivate(url)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = try JSONEncoder.iso8601.encode(payload)
        request.httpBody = body

        // Sign the payload with HMAC-SHA256
        let secret = keychainService.getOrCreateWebhookSecret()
        if let secretData = secret.data(using: .utf8) {
            let signature = hmacSHA256(data: body, key: secretData)
            request.addValue("sha256=\(signature)", forHTTPHeaderField: "X-Signature-256")
        }

        return try await URLSession.shared.data(for: request)
    }

    /// Matches a host against a pattern that may contain `*` wildcards.
    /// e.g. `192.168.1.*` matches `192.168.1.88`, `*.local` matches `myserver.local`.
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

struct WebhookPayload: Codable {
    let timestamp: Date
    let deviceId: String
    let deviceName: String
    let serviceId: String?
    let serviceName: String?
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
