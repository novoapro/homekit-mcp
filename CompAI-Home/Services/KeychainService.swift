import Foundation
import Security

/// Simple Keychain wrapper for storing, reading, and deleting API keys securely.
class KeychainService {
    private let service = "com.mnplab.compai-home"

    /// Save or update a value in the Keychain.
    @discardableResult
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
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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

// MARK: - API Token Model

struct APIToken: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let token: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, token: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.token = token
        self.createdAt = createdAt
    }
}

// MARK: - Keychain Keys

extension KeychainService {
    enum Keys {
        static let aiApiKey = "ai-api-key"
        static let mcpApiToken = "mcp-api-token"
        static let mcpApiTokens = "mcp-api-tokens"
        static let webhookSecret = "webhook-secret"
        static let webhookURL = "webhook-url"
        static let appleSignInUserId = "apple-signin-user-id"
        static let appleSignInEmail = "apple-signin-email"
        static let appleSignInName = "apple-signin-name"
    }

    // MARK: - Multi-Token Management

    /// Returns all API tokens, migrating the legacy single token if needed.
    func getAPITokens() -> [APIToken] {
        if let json = read(key: Keys.mcpApiTokens), let data = json.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let tokens = try? decoder.decode([APIToken].self, from: data), !tokens.isEmpty {
                return tokens
            }
        }

        // Migrate legacy single token
        if let legacyToken = read(key: Keys.mcpApiToken), !legacyToken.isEmpty {
            let migrated = APIToken(name: "Default", token: legacyToken)
            saveAPITokens([migrated])
            delete(key: Keys.mcpApiToken)
            return [migrated]
        }

        return []
    }

    /// Creates a new API token with the given name and persists it.
    @discardableResult
    func addAPIToken(name: String) -> APIToken {
        var tokens = getAPITokens()
        let newToken = APIToken(name: name, token: generateSecureToken())
        tokens.append(newToken)
        saveAPITokens(tokens)
        return newToken
    }

    /// Deletes an API token by ID.
    func deleteAPIToken(id: UUID) {
        var tokens = getAPITokens()
        tokens.removeAll { $0.id == id }
        saveAPITokens(tokens)
    }

    /// Returns the set of valid token strings for middleware validation.
    func getValidTokenStrings() -> Set<String> {
        var tokens = Set(getAPITokens().map(\.token))
        #if DEV_ENVIRONMENT
        tokens.insert(AppEnvironment.devDefaultToken)
        #endif
        return tokens
    }

    private func saveAPITokens(_ tokens: [APIToken]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tokens),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = save(key: Keys.mcpApiTokens, value: json)
    }

    // MARK: - Webhook Secret

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
    func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
