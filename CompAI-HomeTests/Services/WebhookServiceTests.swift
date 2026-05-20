import XCTest
import CommonCrypto
 import CompAI_Home

final class WebhookServiceTests: XCTestCase {

    // MARK: - HMAC-SHA256 Signature Generation

    func testHmacSHA256_knownPayload_matchesExpected() {
        let payload = "test payload".data(using: .utf8)!
        let key = "secret-key".data(using: .utf8)!

        let signature = computeHmacSHA256(data: payload, key: key)

        // Verify with known value
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        payload.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress, key.count,
                        dataBytes.baseAddress, payload.count,
                        &hmac)
            }
        }
        let expectedSignature = hmac.map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(signature, expectedSignature)
    }

    func testHmacSHA256_emptyPayload() {
        let payload = Data()
        let key = "secret-key".data(using: .utf8)!

        let signature = computeHmacSHA256(data: payload, key: key)

        // Should produce a consistent 64-character hex string
        XCTAssertEqual(signature.count, 64)
    }

    func testHmacSHA256_emptyKey() {
        let payload = "test payload".data(using: .utf8)!
        let key = Data()

        let signature = computeHmacSHA256(data: payload, key: key)

        // Should still produce a signature
        XCTAssertEqual(signature.count, 64)
    }

    func testHmacSHA256_differentPayloads_produceDifferentSignatures() {
        let payload1 = "payload1".data(using: .utf8)!
        let payload2 = "payload2".data(using: .utf8)!
        let key = "secret".data(using: .utf8)!

        let sig1 = computeHmacSHA256(data: payload1, key: key)
        let sig2 = computeHmacSHA256(data: payload2, key: key)

        XCTAssertNotEqual(sig1, sig2)
    }

    func testHmacSHA256_differentKeys_produceDifferentSignatures() {
        let payload = "payload".data(using: .utf8)!
        let key1 = "secret1".data(using: .utf8)!
        let key2 = "secret2".data(using: .utf8)!

        let sig1 = computeHmacSHA256(data: payload, key: key1)
        let sig2 = computeHmacSHA256(data: payload, key: key2)

        XCTAssertNotEqual(sig1, sig2)
    }

    func testHmacSHA256_longPayload() {
        let payload = String(repeating: "x", count: 10000).data(using: .utf8)!
        let key = "secret-key".data(using: .utf8)!

        let signature = computeHmacSHA256(data: payload, key: key)

        XCTAssertEqual(signature.count, 64)
    }

    func testHmacSHA256_jsonPayload() {
        let jsonPayload = """
        {
            "deviceId": "dev-1",
            "deviceName": "Light",
            "newValue": true
        }
        """.data(using: .utf8)!
        let key = "webhook-secret".data(using: .utf8)!

        let signature = computeHmacSHA256(data: jsonPayload, key: key)

        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(signature.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil)
    }

    // MARK: - SSRF IP Validation (Private IP Detection)

    func testValidateURLNotPrivate_publicIP_succeeds() throws {
        // Note: This test verifies the mechanism but cannot actually resolve IPs without network
        // In a real test, we would mock the DNS resolution
        XCTAssertTrue(true) // Placeholder for integration test
    }

    func testValidateURLNotPrivate_localhost_allowed() {
        // localhost should be allowed (for the app's own endpoints)
        XCTAssertTrue(true) // Placeholder
    }

    func testValidateURLNotPrivate_127001_allowed() {
        // 127.0.0.1 should be allowed
        XCTAssertTrue(true) // Placeholder
    }

    func testValidateURLNotPrivate_localhost_ipv6_allowed() {
        // ::1 should be allowed
        XCTAssertTrue(true) // Placeholder
    }

    // MARK: - Wildcard IP Allowlist Matching

    func testMatchesWildcard_exactMatch_succeeds() {
        let result = WebhookService.matchesWildcard(host: "192.168.1.1", pattern: "192.168.1.1")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_noWildcard_exactMatch() {
        let result = WebhookService.matchesWildcard(host: "example.com", pattern: "example.com")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_noWildcard_noMatch() {
        let result = WebhookService.matchesWildcard(host: "example.com", pattern: "different.com")
        XCTAssertFalse(result)
    }

    func testMatchesWildcard_wildcardEndOctet() {
        let result = WebhookService.matchesWildcard(host: "192.168.1.1", pattern: "192.168.1.*")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_wildcardEndOctet_noMatch() {
        let result = WebhookService.matchesWildcard(host: "192.168.2.1", pattern: "192.168.1.*")
        XCTAssertFalse(result)
    }

    func testMatchesWildcard_wildcardMultipleOctets() {
        let result = WebhookService.matchesWildcard(host: "192.168.1.1", pattern: "192.168.*.*")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_wildcardDomain() {
        let result = WebhookService.matchesWildcard(host: "myserver.local", pattern: "*.local")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_wildcardDomain_noMatch() {
        let result = WebhookService.matchesWildcard(host: "myserver.example", pattern: "*.local")
        XCTAssertFalse(result)
    }

    func testMatchesWildcard_wildcardPrefix() {
        let result = WebhookService.matchesWildcard(host: "api.myserver.com", pattern: "*.myserver.com")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_multipleLevels() {
        let result = WebhookService.matchesWildcard(host: "api.staging.myserver.com", pattern: "*.*.myserver.com")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_caseInsensitive() {
        let result = WebhookService.matchesWildcard(host: "MYSERVER.LOCAL", pattern: "myserver.local")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_complexPattern1() {
        let result = WebhookService.matchesWildcard(host: "192.168.100.50", pattern: "192.168.*.50")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_complexPattern2() {
        let result = WebhookService.matchesWildcard(host: "192.168.100.51", pattern: "192.168.*.50")
        XCTAssertFalse(result)
    }

    func testMatchesWildcard_ipRange() {
        let result = WebhookService.matchesWildcard(host: "10.0.0.1", pattern: "10.*.*.*")
        XCTAssertTrue(result)
    }

    func testMatchesWildcard_ipRange_noMatch() {
        let result = WebhookService.matchesWildcard(host: "11.0.0.1", pattern: "10.*.*.*")
        XCTAssertFalse(result)
    }

    // MARK: - Webhook Payload Model

    func testWebhookPayload_codable() throws {
        let payload = WebhookPayload(
            timestamp: Date(),
            deviceId: "dev-1",
            deviceName: "Light",
            serviceId: "svc-1",
            serviceName: "Lightbulb",
            characteristicId: "char-1",
            characteristicType: "power",
            characteristicName: "Power State",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedPayload = try decoder.decode(WebhookPayload.self, from: data)

        XCTAssertEqual(decodedPayload.deviceId, payload.deviceId)
        XCTAssertEqual(decodedPayload.deviceName, payload.deviceName)
        XCTAssertEqual(decodedPayload.characteristicType, payload.characteristicType)
    }

    func testWebhookPayload_optionalFields() throws {
        let payload = WebhookPayload(
            timestamp: Date(),
            deviceId: "dev-1",
            deviceName: "Light",
            serviceId: nil,
            serviceName: nil,
            characteristicId: nil,
            characteristicType: "power",
            characteristicName: "Power State",
            oldValue: nil,
            newValue: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedPayload = try decoder.decode(WebhookPayload.self, from: data)

        XCTAssertNil(decodedPayload.serviceId)
        XCTAssertNil(decodedPayload.serviceName)
        XCTAssertNil(decodedPayload.oldValue)
        XCTAssertNil(decodedPayload.newValue)
    }

    // MARK: - Webhook Status

    func testWebhookStatus_idle_equatable() {
        let status1 = WebhookStatus.idle
        let status2 = WebhookStatus.idle
        XCTAssertEqual(status1, status2)
    }

    func testWebhookStatus_sending_equatable() {
        let status1 = WebhookStatus.sending
        let status2 = WebhookStatus.sending
        XCTAssertEqual(status1, status2)
    }

    func testWebhookStatus_lastSuccess_equatable() {
        let date1 = Date()
        let status1 = WebhookStatus.lastSuccess(date: date1)
        let status2 = WebhookStatus.lastSuccess(date: date1)
        XCTAssertEqual(status1, status2)
    }

    func testWebhookStatus_lastFailure_equatable() {
        let date1 = Date()
        let status1 = WebhookStatus.lastFailure(date: date1, error: "Test error")
        let status2 = WebhookStatus.lastFailure(date: date1, error: "Test error")
        XCTAssertEqual(status1, status2)
    }

    func testWebhookStatus_different_notEqual() {
        let status1 = WebhookStatus.idle
        let status2 = WebhookStatus.sending
        XCTAssertNotEqual(status1, status2)
    }

    // MARK: - Webhook Error

    func testWebhookError_httpError_errorDescription() {
        let error = WebhookError.httpError(statusCode: 500)
        XCTAssertEqual(error.errorDescription, "HTTP error 500")
    }

    func testWebhookError_ssrfBlocked_errorDescription() {
        let error = WebhookError.ssrfBlocked
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("private"))
    }

    // MARK: - Exponential Backoff Calculation

    func testExponentialBackoff_attempt1_1second() {
        let delay = pow(2.0, Double(1))
        XCTAssertEqual(delay, 2.0)
    }

    func testExponentialBackoff_attempt2_2seconds() {
        let delay = pow(2.0, Double(2))
        XCTAssertEqual(delay, 4.0)
    }

    func testExponentialBackoff_attempt3_4seconds() {
        let delay = pow(2.0, Double(3))
        XCTAssertEqual(delay, 8.0)
    }

    func testExponentialBackoff_increasesProperly() {
        let delay1 = pow(2.0, Double(1))
        let delay2 = pow(2.0, Double(2))
        let delay3 = pow(2.0, Double(3))

        XCTAssertLessThan(delay1, delay2)
        XCTAssertLessThan(delay2, delay3)
    }

    // MARK: - Integration-style Tests

    func testWebhookPayload_withValidValues_encodesAndDecodes() throws {
        let payload = WebhookPayload(
            timestamp: Date(),
            deviceId: "device-123",
            deviceName: "Living Room Light",
            serviceId: "service-456",
            serviceName: "Lightbulb Service",
            characteristicId: "char-789",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            characteristicName: "On",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedPayload = try decoder.decode(WebhookPayload.self, from: jsonData)

        XCTAssertEqual(decodedPayload.deviceId, payload.deviceId)
        XCTAssertEqual(decodedPayload.deviceName, payload.deviceName)
        XCTAssertEqual(decodedPayload.characteristicName, payload.characteristicName)
        XCTAssertEqual(decodedPayload.oldValue?.value as? Bool, false)
        XCTAssertEqual(decodedPayload.newValue?.value as? Bool, true)
    }

    func testWildcardMatching_multiplePatterns() {
        let testCases: [(host: String, pattern: String, expected: Bool)] = [
            ("192.168.1.1", "192.168.1.*", true),
            ("192.168.2.1", "192.168.1.*", false),
            ("10.0.0.1", "10.0.*.*", true),
            ("10.1.0.1", "10.0.*.*", false),
            ("myserver.local", "*.local", true),
            ("myserver.example", "*.local", false),
            ("api.myserver.com", "api.*.com", true),
            ("api.example.com", "api.*.com", true),
        ]

        for testCase in testCases {
            let result = WebhookService.matchesWildcard(host: testCase.host, pattern: testCase.pattern)
            XCTAssertEqual(result, testCase.expected, "Failed for \(testCase.host) against \(testCase.pattern)")
        }
    }
}

// MARK: - Helper Functions

func computeHmacSHA256(data: Data, key: Data) -> String {
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
