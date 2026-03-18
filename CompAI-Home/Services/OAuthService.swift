// CompAI-Home/Services/OAuthService.swift
import Foundation
import CryptoKit

actor OAuthService {

    private let keychainService: KeychainService

    // In-memory token stores
    private var tokens: [String: OAuthToken] = [:]         // accessToken → OAuthToken
    private var refreshIndex: [String: OAuthToken] = [:]    // refreshToken → OAuthToken
    private var pendingCodes: [String: OAuthAuthorizationCode] = [:] // code → AuthCode

    // Revocation callback: called with the set of revoked access tokens
    var onTokensRevoked: ((_ accessTokens: Set<String>) async -> Void)?

    private let tokenFileURL: URL = {
        FileManager.appSupportDirectory.appendingPathComponent("oauth-tokens.json")
    }()

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
        loadTokensFromDisk()
    }

    // MARK: - PKCE

    private func validatePKCE(verifier: String, challenge: String) -> Bool {
        guard let verifierData = verifier.data(using: .ascii) else { return false }
        let hash = SHA256.hash(data: verifierData)
        let computed = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return computed == challenge
    }

    // MARK: - Authorization Code

    func createAuthorizationCode(clientId: String, codeChallenge: String, redirectURI: String, scopes: Set<String>, state: String?) -> OAuthAuthorizationCode? {
        let credentials = keychainService.getActiveOAuthCredentials()
        guard credentials.contains(where: { $0.clientId == clientId }) else { return nil }

        let code = keychainService.generateSecureToken()
        let authCode = OAuthAuthorizationCode(
            code: code,
            clientId: clientId,
            codeChallenge: codeChallenge,
            redirectURI: redirectURI,
            scopes: scopes,
            state: state,
            expiresAt: Date().addingTimeInterval(60) // 60-second TTL
        )
        pendingCodes[code] = authCode
        return authCode
    }

    // MARK: - Token Exchange

    func exchangeAuthorizationCode(code: String, clientId: String, clientSecret: String, codeVerifier: String, redirectURI: String) -> OAuthToken? {
        guard let authCode = pendingCodes.removeValue(forKey: code) else { return nil }
        guard !authCode.isExpired else { return nil }
        guard authCode.clientId == clientId else { return nil }
        guard authCode.redirectURI == redirectURI else { return nil }
        guard validatePKCE(verifier: codeVerifier, challenge: authCode.codeChallenge) else { return nil }

        // Validate client secret
        let credentials = keychainService.getActiveOAuthCredentials()
        guard let credential = credentials.first(where: { $0.clientId == clientId && $0.clientSecret == clientSecret }) else { return nil }

        let token = issueToken(credentialId: credential.id, scopes: authCode.scopes)

        // Update lastUsedAt
        var updated = credential
        updated.lastUsedAt = Date()
        keychainService.updateOAuthCredential(updated)

        return token
    }

    // MARK: - Refresh

    func refreshAccessToken(refreshToken: String, clientId: String, clientSecret: String) -> OAuthToken? {
        guard let existingToken = refreshIndex[refreshToken] else { return nil }
        guard !existingToken.isRefreshExpired else {
            removeToken(existingToken)
            return nil
        }

        // Validate client
        let credentials = keychainService.getActiveOAuthCredentials()
        guard let credential = credentials.first(where: { $0.clientId == clientId && $0.clientSecret == clientSecret }) else { return nil }
        guard existingToken.credentialId == credential.id else { return nil }

        // Rotate: remove old token, issue new one
        removeToken(existingToken)
        let newToken = issueToken(credentialId: credential.id, scopes: existingToken.scopes)

        // Update lastUsedAt
        var updated = credential
        updated.lastUsedAt = Date()
        keychainService.updateOAuthCredential(updated)

        return newToken
    }

    // MARK: - Validation

    func validateAccessToken(_ accessToken: String) -> OAuthToken? {
        guard let token = tokens[accessToken], !token.isExpired else {
            // Clean up expired token if present
            if let token = tokens[accessToken] { removeToken(token) }
            return nil
        }
        // Verify credential is still active
        let credentials = keychainService.getActiveOAuthCredentials()
        guard credentials.contains(where: { $0.id == token.credentialId }) else {
            removeToken(token)
            return nil
        }
        return token
    }

    // MARK: - Revocation

    func revokeCredential(id: UUID) async {
        let revokedAccessTokens = Set(tokens.values.filter { $0.credentialId == id }.map(\.accessToken))

        // Remove all tokens for this credential
        for token in tokens.values where token.credentialId == id {
            removeToken(token)
        }

        persistTokensToDisk()

        // Notify for session termination
        if !revokedAccessTokens.isEmpty {
            await onTokensRevoked?(revokedAccessTokens)
        }
    }

    /// Returns all access tokens for a given credential (used for session tracking).
    func accessTokens(for credentialId: UUID) -> Set<String> {
        Set(tokens.values.filter { $0.credentialId == credentialId }.map(\.accessToken))
    }

    /// Sets the callback for token revocation (used for connection termination).
    func setOnTokensRevoked(_ handler: @escaping (_ accessTokens: Set<String>) async -> Void) {
        self.onTokensRevoked = handler
    }

    // MARK: - Private Helpers

    private func issueToken(credentialId: UUID, scopes: Set<String>) -> OAuthToken {
        let token = OAuthToken(
            accessToken: keychainService.generateSecureToken(),
            refreshToken: keychainService.generateSecureToken(),
            credentialId: credentialId,
            expiresAt: Date().addingTimeInterval(3600), // 1 hour
            refreshTokenExpiresAt: Date().addingTimeInterval(30 * 24 * 3600), // 30 days
            scopes: scopes
        )
        tokens[token.accessToken] = token
        refreshIndex[token.refreshToken] = token
        persistTokensToDisk()
        return token
    }

    private func removeToken(_ token: OAuthToken) {
        tokens.removeValue(forKey: token.accessToken)
        refreshIndex.removeValue(forKey: token.refreshToken)
    }

    // MARK: - Persistence

    private func persistTokensToDisk() {
        let allTokens = Array(tokens.values)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(allTokens) else { return }
        try? data.write(to: tokenFileURL, options: .atomic)
    }

    private func loadTokensFromDisk() {
        guard let data = try? Data(contentsOf: tokenFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([OAuthToken].self, from: data) else { return }
        for token in loaded where !token.isExpired {
            tokens[token.accessToken] = token
            refreshIndex[token.refreshToken] = token
        }
    }
}
