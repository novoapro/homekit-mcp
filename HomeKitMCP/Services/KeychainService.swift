import Foundation
import Security

/// Simple Keychain wrapper for storing, reading, and deleting API keys securely.
class KeychainService {
    private let service = "com.novoa.HomeKitMCP"

    /// Save or update a value in the Keychain.
    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        // If item doesn't exist, add it
        if updateStatus == errSecItemNotFound {
            var addQuery = updateQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    /// Read a value from the Keychain.
    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    @discardableResult
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if a key exists in the Keychain.
    func exists(key: String) -> Bool {
        read(key: key) != nil
    }
}

// MARK: - Keychain Keys

extension KeychainService {
    enum Keys {
        static let aiApiKey = "ai-api-key"
        static let mcpApiToken = "mcp-api-token"
        static let webhookSecret = "webhook-secret"
        static let webhookURL = "webhook-url"
        static let appleSignInUserId = "apple-signin-user-id"
        static let appleSignInEmail = "apple-signin-email"
        static let appleSignInName = "apple-signin-name"
    }

    /// Returns the existing MCP API token, or generates and stores a new one.
    func getOrCreateMCPApiToken() -> String {
        if let existing = read(key: Keys.mcpApiToken), !existing.isEmpty {
            return existing
        }
        let token = generateSecureToken()
        _ = save(key: Keys.mcpApiToken, value: token)
        return token
    }

    /// Generates a new MCP API token, replacing any existing one.
    @discardableResult
    func regenerateMCPApiToken() -> String {
        let token = generateSecureToken()
        _ = save(key: Keys.mcpApiToken, value: token)
        return token
    }

    /// Returns the existing webhook secret, or generates and stores a new one.
    func getOrCreateWebhookSecret() -> String {
        if let existing = read(key: Keys.webhookSecret), !existing.isEmpty {
            return existing
        }
        let secret = generateSecureToken()
        _ = save(key: Keys.webhookSecret, value: secret)
        return secret
    }

    /// Generates a new webhook secret, replacing any existing one.
    @discardableResult
    func regenerateWebhookSecret() -> String {
        let secret = generateSecureToken()
        _ = save(key: Keys.webhookSecret, value: secret)
        return secret
    }

    /// Generates a cryptographically secure 32-byte hex token.
    private func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
