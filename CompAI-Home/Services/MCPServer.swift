import Foundation
import Vapor
import NIOCore
import Combine

/// MCP server exposing HomeKit devices via HTTP/SSE/WebSocket.
///
/// Threading contract: `@Published` properties and `app` lifecycle are accessed from the main queue.
/// Vapor route handlers run on NIO event loops but only call the `Sendable` `handler` and
/// the actor-isolated `connectionTracker`. Marked `@unchecked Sendable` because mutable state
/// (`app`, `wsCancellables`, `serverTask`) is only mutated from `start()`/`stopAsync()` which
/// are serialized through the main-queue `stop()` entry point.
class MCPServer: ObservableObject, MCPServerProtocol, @unchecked Sendable {
    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var lastError: String?

    private var app: Application?
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let storage: StorageService
    private let port: Int
    private let handler: MCPRequestHandler
    private let connectionTracker = ConnectionTracker()
    private let automationStorageService: AutomationStorageService
    private let automationEngine: AutomationEngine
    private let keychainService: KeychainService
    private let registry: DeviceRegistryService?
    private let aiAutomationService: AIAutomationService?
    private let subscriptionService: SubscriptionService?
    private let oauthService: OAuthService
    private var wsCancellables = Set<AnyCancellable>()
    private var serverTask: Task<Void, Never>?

    init(
        homeKitManager: HomeKitManager,
        loggingService: LoggingService,
        storage: StorageService,
        automationStorageService: AutomationStorageService,
        automationEngine: AutomationEngine,
        keychainService: KeychainService,
        registry: DeviceRegistryService? = nil,
        aiAutomationService: AIAutomationService? = nil,
        subscriptionService: SubscriptionService? = nil,
        oauthService: OAuthService,
        port: Int = 3000,
        handler: MCPRequestHandler? = nil
    ) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.storage = storage
        self.port = port
        self.automationStorageService = automationStorageService
        self.automationEngine = automationEngine
        self.keychainService = keychainService
        self.registry = registry
        self.aiAutomationService = aiAutomationService
        self.subscriptionService = subscriptionService
        self.oauthService = oauthService
        self.handler = handler ?? MCPRequestHandler(
            homeKitManager: homeKitManager,
            loggingService: loggingService,
            storage: storage,
            automationStorageService: automationStorageService,
            automationEngine: automationEngine,
            registry: registry,
            aiAutomationService: aiAutomationService,
            subscriptionService: subscriptionService
        )
    }

    func start() async throws {
        // Stop any existing instance first
        if app != nil {
            await stopAsync()
        }

        let env = Environment(name: "production", arguments: ["serve"])

        serverTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let app = try await Application.make(env)
                let requestedAddress = self.storage.readBindAddress()
                let resolvedAddress = NetworkInterfaceEnumerator.resolvedBindAddress(requestedAddress)
                if resolvedAddress != requestedAddress {
                    AppLogger.server.warning("Bind address \(requestedAddress) is unavailable, falling back to \(resolvedAddress)")
                }
                app.http.server.configuration.hostname = resolvedAddress
                app.http.server.configuration.port = self.port
                app.http.server.configuration.reuseAddress = true
                app.logger.logLevel = .warning

                self.configureRoutes(app)
                self.subscribeToLogSubjects()
                self.app = app

                // Mark as running before the blocking startup() call.
                // Use DispatchQueue.main instead of MainActor.run to avoid
                // potential deadlocks in detached tasks.
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.lastError = nil
                }

                // Wire OAuth token revocation to connection termination
                Task {
                    await self.oauthService.setOnTokensRevoked { [weak self] accessTokens in
                        guard let self else { return }
                        await self.connectionTracker.revokeTokenConnections(accessTokens)
                        self.updateClientCount()
                    }
                }

                do {
                    // startup() blocks while the server runs — it only returns on shutdown or error
                    try await app.startup()
                } catch {
                    let message = "MCP Server failed to start on port \(self.port): \(error.localizedDescription)"
                    AppLogger.server.error("\(message)")
                    self.logServerError(message)
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.lastError = message
                    }
                }
            } catch {
                let message = "MCP Server failed to initialize Application: \(error.localizedDescription)"
                AppLogger.server.error("\(message)")
                self.logServerError(message)
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.lastError = message
                }
            }
        }
    }

    func stop() {
        Task {
            await stopAsync()
            DispatchQueue.main.async {
                self.isRunning = false
                self.connectedClients = 0
            }
        }
    }

    private func stopAsync() async {
        serverTask?.cancel()
        serverTask = nil
        wsCancellables.removeAll()
        await connectionTracker.removeAll()
        if let app = self.app {
            self.app = nil
            do {
                try await app.asyncShutdown()
            } catch {
                AppLogger.server.error("Error shutting down app: \(error)")
            }
        }
    }

    // MARK: - WebSocket Broadcasting

    private func subscribeToLogSubjects() {
        wsCancellables.removeAll()

        guard storage.readWebsocketEnabled() else { return }

        let tracker = connectionTracker

        // Broadcast new log entries + automation execution logs in a single subscriber
        loggingService.logEntrySubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] entry in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    do {
                        let logData = try JSONEncoder.iso8601.encode(entry)
                        if let logJson = try JSONSerialization.jsonObject(with: logData) as? [String: Any] {
                            let msg: [String: Any] = ["type": "log", "data": logJson]
                            let msgData = try JSONSerialization.data(withJSONObject: msg)
                            if let text = String(data: msgData, encoding: .utf8) {
                                await tracker.broadcastToWS(text)
                            }
                        }
                    } catch {
                        AppLogger.server.error("Failed to encode log for WS broadcast: \(error)")
                    }
                    // Also broadcast as typed automation log if applicable
                    if let execLog = entry.automationExecution {
                        self?.broadcastAutomationLog(execLog, type: "automation_log", tracker: tracker)
                    }
                }
            }
            .store(in: &wsCancellables)

        // Broadcast updated automation execution logs (separate subject)
        loggingService.logUpdatedSubject
            .filter { $0.category == .automationExecution || $0.category == .automationError }
            .compactMap(\.automationExecution)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] entry in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    self?.broadcastAutomationLog(entry, type: "automation_log_updated", tracker: tracker)
                }
            }
            .store(in: &wsCancellables)

        // Broadcast logs_cleared when log store is cleared
        loggingService.logsClearedSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { _ in
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    let msg = "{\"type\":\"logs_cleared\"}"
                    await tracker.broadcastToWS(msg)
                }
            }
            .store(in: &wsCancellables)

        // Broadcast automation definition changes (create/update/delete/enable/disable)
        automationStorageService.automationsSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] automations in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    do {
                        let data = try JSONEncoder.iso8601.encode(automations)
                        if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                            let msg: [String: Any] = ["type": "automations_updated", "data": json]
                            let msgData = try JSONSerialization.data(withJSONObject: msg)
                            if let text = String(data: msgData, encoding: .utf8) {
                                await tracker.broadcastToWS(text)
                            }
                        }
                    } catch {
                        AppLogger.server.error("Failed to encode automations for WS broadcast: \(error)")
                    }
                }
            }
            .store(in: &wsCancellables)

        // Broadcast device registry changes (device added/removed/renamed)
        if let registry {
            registry.registrySyncSubject
                .receive(on: DispatchQueue.global(qos: .utility))
                .debounce(for: .seconds(0.5), scheduler: DispatchQueue.global(qos: .utility))
                .sink { _ in
                    Task {
                        guard await tracker.wsConnectionCount > 0 else { return }
                        await tracker.broadcastToWS("{\"type\":\"devices_updated\"}")
                    }
                }
                .store(in: &wsCancellables)
        }

        // Broadcast subscription tier changes
        if let subscriptionService {
            subscriptionService.tierChangedSubject
                .receive(on: DispatchQueue.global(qos: .utility))
                .sink { tier in
                    Task {
                        guard await tracker.wsConnectionCount > 0 else { return }
                        let msg = "{\"type\":\"subscription_changed\",\"data\":{\"tier\":\"\(tier.rawValue)\",\"isPro\":\(tier == .pro)}}"
                        await tracker.broadcastToWS(msg)
                    }
                }
                .store(in: &wsCancellables)
        }

        // Broadcast granular characteristic value changes (observed devices only)
        homeKitManager.characteristicValueChangePublisher
            .receive(on: DispatchQueue.global(qos: .utility))
            .collect(.byTime(DispatchQueue.global(qos: .utility), .milliseconds(100)))
            .filter { !$0.isEmpty }
            .sink { [weak self] changes in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    for change in changes {
                        let valueJson: Any
                        if let v = change.value {
                            // Convert temperature values to user's preferred unit
                            var effectiveValue: Any = v
                            if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(change.characteristicType) {
                                if let d = v as? Double { effectiveValue = TemperatureConversion.celsiusToFahrenheit(d) }
                                else if let i = v as? Int { effectiveValue = TemperatureConversion.celsiusToFahrenheit(Double(i)) }
                            }
                            let encoded = try? JSONEncoder.iso8601.encode(AnyCodable(effectiveValue))
                            valueJson = encoded.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) ?? effectiveValue
                        } else {
                            valueJson = NSNull()
                        }
                        let msg: [String: Any] = [
                            "type": "characteristic_updated",
                            "data": [
                                "deviceId": change.deviceId,
                                "serviceId": change.serviceId,
                                "characteristicId": change.characteristicId,
                                "characteristicType": change.characteristicType,
                                "value": valueJson,
                                "oldValue": change.oldValue,
                                "timestamp": isoFormatter.string(from: change.timestamp)
                            ] as [String: Any]
                        ]
                        do {
                            let msgData = try JSONSerialization.data(withJSONObject: msg)
                            if let text = String(data: msgData, encoding: .utf8) {
                                await tracker.broadcastToWS(text)
                            }
                        } catch {
                            AppLogger.server.error("Failed to encode characteristic_updated for WS: \(error)")
                        }
                    }
                }
            }
            .store(in: &wsCancellables)
    }

    private func broadcastAutomationLog(_ entry: AutomationExecutionLog, type: String, tracker: ConnectionTracker) {
        Task {
            do {
                let logData = try JSONEncoder.iso8601.encode(entry)
                if let logJson = try JSONSerialization.jsonObject(with: logData) as? [String: Any] {
                    let msg: [String: Any] = ["type": type, "data": logJson]
                    let msgData = try JSONSerialization.data(withJSONObject: msg)
                    if let text = String(data: msgData, encoding: .utf8) {
                        await tracker.broadcastToWS(text)
                    }
                }
            } catch {
                AppLogger.server.error("Failed to encode automation log for WS broadcast: \(error)")
            }
        }
    }

    // MARK: - Route Configuration

    private func configureRoutes(_ app: Application) {
        let validTokens = keychainService.getValidTokenStrings()
        let authMiddleware = BearerAuthMiddleware(validTokens: validTokens, oauthService: oauthService)

        // CORS middleware — app-level so OPTIONS preflight requests get proper headers.
        if storage.readCorsEnabled() {
            let allowedOrigins = storage.readCorsAllowedOrigins()
            let corsOrigin: CORSMiddleware.AllowOriginSetting
            if !allowedOrigins.isEmpty {
                corsOrigin = .any(allowedOrigins)
            } else {
                let requestedAddr = storage.readBindAddress()
                let bindAddr = NetworkInterfaceEnumerator.resolvedBindAddress(requestedAddr)
                if bindAddr == "0.0.0.0" {
                    AppLogger.server.warning("CORS is set to allow all origins because the server binds to 0.0.0.0. Configure specific allowed origins in settings for tighter security.")
                }
                corsOrigin = bindAddr == "0.0.0.0" ? .all : .custom("http://\(bindAddr):\(port)")
            }
            let corsConfig = CORSMiddleware.Configuration(
                allowedOrigin: corsOrigin,
                allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
                allowedHeaders: [.contentType, .authorization, .init("Mcp-Session-Id")]
            )
            app.middleware.use(CORSMiddleware(configuration: corsConfig), at: .beginning)
        }

        // Health check — no auth required
        app.on(.GET, "health") { _ -> String in
            return "ok"
        }

        // WebSocket endpoint for real-time log streaming.
        // Auth via query param since browser WebSocket API cannot send Authorization headers.
        if storage.readWebsocketEnabled() {
            app.webSocket("ws") { [weak self] req, ws async in
                guard let self else {
                    try? await ws.close()
                    return
                }

                // Validate bearer token from query parameter
                let wsToken = req.query[String.self, at: "token"]
                let isValidBearerToken = wsToken.map { validTokens.contains($0) } ?? false
                let isValidOAuthToken: Bool
                if let t = wsToken {
                    isValidOAuthToken = await self.oauthService.validateAccessToken(t) != nil
                } else {
                    isValidOAuthToken = false
                }
                guard isValidBearerToken || isValidOAuthToken else {
                    try? await ws.close(code: .policyViolation)
                    return
                }

                guard self.storage.readLogAccessEnabled() else {
                    try? await ws.close(code: .policyViolation)
                    return
                }

                let connectionId = UUID()
                let tracker = self.connectionTracker

                await tracker.addWSConnection(id: connectionId, ws: ws)
                if isValidOAuthToken, let oauthToken = wsToken {
                    await tracker.associateToken(oauthToken, withWS: connectionId)
                }
                self.updateClientCount()

                AppLogger.server.info("WebSocket client connected: \(connectionId)")

                // Send welcome message
                let welcome = "{\"type\":\"connected\",\"connectionId\":\"\(connectionId.uuidString)\"}"
                try? await ws.send(welcome)

                // Handle incoming text (app-level ping)
                ws.onText { ws, text in
                    if text.contains("\"ping\"") {
                        try? await ws.send("{\"type\":\"pong\"}")
                    }
                }

                // Wait for close — this suspends until the WebSocket disconnects
                try? await ws.onClose.get()

                await tracker.dissociateWS(id: connectionId)
                await tracker.removeWSConnection(id: connectionId)
                self.updateClientCount()
                AppLogger.server.info("WebSocket client disconnected: \(connectionId)")
            }
        }

        // MARK: - OAuth 2.1 Endpoints (unauthenticated)

        app.on(.GET, ".well-known", "oauth-authorization-server") { [weak self] req -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            let host = req.headers.first(name: .host) ?? "localhost:\(self.port)"
            let baseURL = "http://\(host)"
            let metadata: [String: Any] = [
                "issuer": baseURL,
                "authorization_endpoint": "\(baseURL)/oauth/authorize",
                "token_endpoint": "\(baseURL)/oauth/token",
                "grant_types_supported": ["authorization_code", "refresh_token"],
                "code_challenge_methods_supported": ["S256"],
                "token_endpoint_auth_methods_supported": ["client_secret_post"],
                "response_types_supported": ["code"]
            ]
            let data = try JSONSerialization.data(withJSONObject: metadata)
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/json")
            return Response(status: .ok, headers: headers, body: .init(data: data))
        }

        app.on(.GET, "oauth", "authorize") { [weak self] req -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }

            guard let responseType = req.query[String.self, at: "response_type"],
                  responseType == "code",
                  let clientId = req.query[String.self, at: "client_id"],
                  let codeChallenge = req.query[String.self, at: "code_challenge"],
                  let codeChallengeMethod = req.query[String.self, at: "code_challenge_method"],
                  codeChallengeMethod == "S256",
                  let redirectURI = req.query[String.self, at: "redirect_uri"] else {
                if let redirectURI = req.query[String.self, at: "redirect_uri"] {
                    let state = req.query[String.self, at: "state"]
                    guard var components = URLComponents(string: redirectURI) else {
                        return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Invalid redirect_uri\"}"))
                    }
                    components.queryItems = [
                        URLQueryItem(name: "error", value: "invalid_request"),
                        URLQueryItem(name: "error_description", value: "Missing or invalid required parameters")
                    ]
                    if let state { components.queryItems?.append(URLQueryItem(name: "state", value: state)) }
                    return Response(status: .found, headers: ["Location": components.string!])
                }
                return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Missing or invalid required parameters\"}"))
            }

            let state = req.query[String.self, at: "state"]
            let scope = req.query[String.self, at: "scope"] ?? "*"
            let scopes = Set(scope.split(separator: " ").map(String.init))

            guard let authCode = await self.oauthService.createAuthorizationCode(
                clientId: clientId,
                codeChallenge: codeChallenge,
                redirectURI: redirectURI,
                scopes: scopes,
                state: state
            ) else {
                guard var components = URLComponents(string: redirectURI) else {
                    return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Invalid redirect_uri\"}"))
                }
                components.queryItems = [
                    URLQueryItem(name: "error", value: "unauthorized_client"),
                    URLQueryItem(name: "error_description", value: "Unknown or revoked client")
                ]
                if let state { components.queryItems?.append(URLQueryItem(name: "state", value: state)) }
                return Response(status: .found, headers: ["Location": components.string!])
            }

            guard var components = URLComponents(string: redirectURI) else {
                return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Invalid redirect_uri\"}"))
            }
            components.queryItems = [URLQueryItem(name: "code", value: authCode.code)]
            if let state { components.queryItems?.append(URLQueryItem(name: "state", value: state)) }
            return Response(status: .found, headers: ["Location": components.string!])
        }

        app.on(.POST, "oauth", "token", body: .collect(maxSize: "16kb")) { [weak self] req -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }

            struct TokenRequest: Content {
                let grant_type: String
                let code: String?
                let client_id: String?
                let client_secret: String?
                let code_verifier: String?
                let redirect_uri: String?
                let refresh_token: String?
            }

            let tokenReq: TokenRequest
            do {
                tokenReq = try req.content.decode(TokenRequest.self)
            } catch {
                return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Malformed request body\"}"))
            }

            switch tokenReq.grant_type {
            case "authorization_code":
                guard let code = tokenReq.code,
                      let clientId = tokenReq.client_id,
                      let clientSecret = tokenReq.client_secret,
                      let codeVerifier = tokenReq.code_verifier,
                      let redirectURI = tokenReq.redirect_uri else {
                    return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Missing required parameters\"}"))
                }

                guard let token = await self.oauthService.exchangeAuthorizationCode(
                    code: code,
                    clientId: clientId,
                    clientSecret: clientSecret,
                    codeVerifier: codeVerifier,
                    redirectURI: redirectURI
                ) else {
                    return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_grant\",\"error_description\":\"Invalid or expired authorization code\"}"))
                }

                return self.tokenResponse(token)

            case "refresh_token":
                guard let refreshToken = tokenReq.refresh_token,
                      let clientId = tokenReq.client_id,
                      let clientSecret = tokenReq.client_secret else {
                    return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_request\",\"error_description\":\"Missing required parameters\"}"))
                }

                guard let token = await self.oauthService.refreshAccessToken(
                    refreshToken: refreshToken,
                    clientId: clientId,
                    clientSecret: clientSecret
                ) else {
                    return Response(status: .badRequest, body: .init(string: "{\"error\":\"invalid_grant\",\"error_description\":\"Invalid or expired refresh token\"}"))
                }

                return self.tokenResponse(token)

            default:
                return Response(status: .badRequest, body: .init(string: "{\"error\":\"unsupported_grant_type\"}"))
            }
        }

        // All routes require bearer token auth
        let protected = app.grouped(authMiddleware)

        // Webhook trigger endpoint — requires Bearer auth + webhook token in URL path.
        protected.on(.POST, "automations", "webhook", ":token", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return try await self.handleRestWebhookTrigger(req)
        }

        // Streamable HTTP transport: single endpoint supporting POST, GET, and DELETE
        protected.on(.POST, "mcp", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardMCPProtocolEnabled()
            return try await self.handleStreamablePost(req)
        }

        protected.on(.GET, "mcp") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardMCPProtocolEnabled()
            return self.handleStreamableGet(req)
        }

        protected.on(.DELETE, "mcp") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardMCPProtocolEnabled()
            return await self.handleStreamableDelete(req)
        }

        // Legacy SSE transport (2024-11-05): separate /sse and /messages endpoints
        protected.on(.GET, "sse") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardMCPProtocolEnabled()
            return self.handleLegacySSE(req)
        }

        protected.on(.POST, "messages", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardMCPProtocolEnabled()
            return try await self.handleLegacyMessages(req)
        }

        // REST Endpoints
        protected.on(.GET, "devices") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetDevices(req)
        }

        protected.on(.GET, "devices", ":deviceId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetDevice(req)
        }

        protected.on(.PATCH, "services", ":serviceId", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestRenameService(req)
        }

        // Scene REST Endpoints
        protected.on(.GET, "scenes") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetScenes(req)
        }

        protected.on(.GET, "scenes", ":sceneId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetScene(req)
        }

        protected.on(.POST, "scenes", ":sceneId", "execute", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestExecuteScene(req)
        }

        // Log REST Endpoint
        protected.on(.GET, "logs") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardLogAccessEnabled()
            return try await self.handleRestGetLogs(req)
        }

        // Automation Runtime Info
        protected.on(.GET, "automation-runtime") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return self.handleGetAutomationRuntime()
        }

        // Automation REST Endpoints (Pro subscription required)
        protected.on(.GET, "automations") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestGetAutomations(req)
        }

        protected.on(.GET, "automations", ":automationId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestGetAutomation(req)
        }

        protected.on(.POST, "automations", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestCreateAutomation(req)
        }

        protected.on(.PUT, "automations", ":automationId", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestUpdateAutomation(req)
        }

        protected.on(.DELETE, "automations", ":automationId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestDeleteAutomation(req)
        }

        protected.on(.POST, "automations", ":automationId", "trigger", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestTriggerAutomation(req)
        }

        protected.on(.GET, "automations", ":automationId", "logs") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            return try await self.handleRestGetAutomationLogs(req)
        }

        // AI Automation Generation (Pro subscription required)
        protected.on(.POST, "automations", "generate", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            try self.guardAutomationsEnabled()
            try self.guardAIEnabled()
            return try await self.handleRestGenerateAutomation(req)
        }

        // AI Automation Improvement (Pro subscription required)
        protected.on(.POST, "automations", ":automationId", "improve", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardProSubscription()
            try self.guardAutomationsEnabled()
            try self.guardAIEnabled()
            return try await self.handleRestImproveAutomation(req)
        }

        // Clear all logs (state-change logs + automation execution logs)
        protected.on(.DELETE, "logs") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            guard self.storage.readLogAccessEnabled() else { throw Abort(.notFound) }
            await self.loggingService.clearLogs()
            let body = try JSONSerialization.data(withJSONObject: ["cleared": true])
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: body))
        }

        // Temperature unit preference
        protected.on(.GET, "settings", "temperature-unit") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            let unit = self.storage.readTemperatureUnit()
            let body = try JSONSerialization.data(withJSONObject: ["unit": unit])
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: body))
        }

        protected.on(.PATCH, "settings", "temperature-unit", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            struct Body: Codable { let unit: String }
            let body = try req.content.decode(Body.self)
            guard body.unit == "celsius" || body.unit == "fahrenheit" else {
                throw Abort(.badRequest, reason: "unit must be 'celsius' or 'fahrenheit'")
            }
            await MainActor.run { self.storage.temperatureUnit = body.unit }
            let responseBody = try JSONSerialization.data(withJSONObject: ["unit": body.unit])
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: responseBody))
        }

        // Subscription status
        protected.on(.GET, "subscription", "status") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            let tier = self.subscriptionService?.readCurrentTier() ?? .free
            let body = try JSONSerialization.data(withJSONObject: [
                "tier": tier.rawValue,
                "isPro": tier == .pro
            ] as [String: Any])
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: body))
        }
    }
    
    // MARK: - REST Helpers

    private func guardAutomationsEnabled() throws {
        guard storage.readAutomationsEnabled() else {
            throw Abort(.notFound, reason: "Automations are not enabled. Enable them in the app settings.")
        }
    }

    private func guardMCPProtocolEnabled() throws {
        guard storage.readMCPProtocolEnabled() else {
            throw Abort(.notFound, reason: "MCP protocol is not enabled. Enable it in the app settings.")
        }
    }

    private func guardRestApiEnabled() throws {
        guard storage.readRestApiEnabled() else {
            throw Abort(.notFound, reason: "REST API is not enabled. Enable it in the app settings.")
        }
    }

    private func guardLogAccessEnabled() throws {
        guard storage.readLogAccessEnabled() else {
            throw Abort(.notFound, reason: "Log access is not enabled. Enable it in the app settings.")
        }
    }

    private func guardAIEnabled() throws {
        guard storage.readAIEnabled() else {
            throw Abort(.notFound, reason: "AI features are not enabled. Enable them in the app settings.")
        }
    }

    private func guardProSubscription() throws {
        guard let sub = subscriptionService, sub.readCurrentTier() == .pro else {
            throw Abort(.paymentRequired, reason: "This feature requires a CompAI - Home Pro subscription.")
        }
    }

    // MARK: - REST Handlers

    private func handleRestGetDevices(_ req: Request) async throws -> Response {
        let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
        let filteredDevices = handler.stableDevices(allDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }

        let data = try JSONEncoder.iso8601.encode(restDevices)
        logRESTCall(method: "GET", path: "/devices", statusCode: 200,
                    resultSummary: "\(restDevices.count) devices",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestGetDevice(_ req: Request) async throws -> Response {
        guard let deviceId = req.parameters.get("deviceId") else {
            logRESTCall(method: "GET", path: "/devices/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest)
        }

        let device = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }

        guard let device else {
            logRESTCall(method: "GET", path: "/devices/\(deviceId)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Device not found")
        }

        let filtered = handler.stableDevices([device])

        guard let filteredDevice = filtered.first else {
            logRESTCall(method: "GET", path: "/devices/\(deviceId)", statusCode: 404, resultSummary: "Not Exposed")
            throw Abort(.notFound, reason: "Device not found or not exposed")
        }

        let restDevice = RESTDevice.from(filteredDevice)
        let data = try JSONEncoder.iso8601.encode(restDevice)
        logRESTCall(method: "GET", path: "/devices/\(deviceId)", statusCode: 200,
                    resultSummary: restDevice.name,
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestRenameService(_ req: Request) async throws -> Response {
        guard let serviceId = req.parameters.get("serviceId") else {
            logRESTCall(method: "PATCH", path: "/services/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest)
        }

        struct RenameBody: Codable { let name: String? }
        let body = try req.content.decode(RenameBody.self)

        if let name = body.name, name.count > 255 {
            throw Abort(.badRequest, reason: "Name must be 255 characters or fewer.")
        }

        await registry?.setServiceCustomName(stableServiceId: serviceId, customName: body.name)

        let responseData = try JSONEncoder().encode(["success": true])
        logRESTCall(method: "PATCH", path: "/services/\(serviceId)", statusCode: 200,
                    resultSummary: body.name ?? "(cleared)",
                    req: req, responseBody: String(data: responseData, encoding: .utf8))
        return jsonResponse(data: responseData)
    }

    // MARK: - Log REST Handler

    private func handleRestGetLogs(_ req: Request) async throws -> Response {
        // All log types are now in the unified LoggingService.
        var logs = await loggingService.getLogs()

        // Category filtering: ?categories=mcp_call,rest_call
        if let categoriesParam = req.query[String.self, at: "categories"] {
            let categoryStrings = categoriesParam.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            let categories = categoryStrings.compactMap { LogCategory(rawValue: $0) }
            if !categories.isEmpty {
                let categorySet = Set(categories)
                logs = logs.filter { categorySet.contains($0.category) }
            }
        }

        // Device name filtering: ?device_name=Light
        if let deviceName = req.query[String.self, at: "device_name"] {
            logs = logs.filter { $0.deviceName.localizedCaseInsensitiveContains(deviceName) }
        }

        // Date filtering
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso8601NoFrac = ISO8601DateFormatter()
        iso8601NoFrac.formatOptions = [.withInternetDateTime]
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.timeZone = TimeZone.current

        if let dateParam = req.query[String.self, at: "date"] {
            guard let date = dateOnly.date(from: dateParam) ?? iso8601.date(from: dateParam) ?? iso8601NoFrac.date(from: dateParam) else {
                throw Abort(.badRequest, reason: "Invalid date format: '\(dateParam)'. Use 'yyyy-MM-dd' or ISO 8601.")
            }
            let startOfDay = Calendar.current.startOfDay(for: date)
            guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                throw Abort(.internalServerError, reason: "Failed to compute date range")
            }
            logs = logs.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        } else {
            if let fromParam = req.query[String.self, at: "from"] {
                guard let fromDate = dateOnly.date(from: fromParam) ?? iso8601.date(from: fromParam) ?? iso8601NoFrac.date(from: fromParam) else {
                    throw Abort(.badRequest, reason: "Invalid 'from' date format: '\(fromParam)'. Use 'yyyy-MM-dd' or ISO 8601.")
                }
                logs = logs.filter { $0.timestamp >= fromDate }
            }
            if let toParam = req.query[String.self, at: "to"] {
                guard let toDate = dateOnly.date(from: toParam) ?? iso8601.date(from: toParam) ?? iso8601NoFrac.date(from: toParam) else {
                    throw Abort(.badRequest, reason: "Invalid 'to' date format: '\(toParam)'. Use 'yyyy-MM-dd' or ISO 8601.")
                }
                logs = logs.filter { $0.timestamp <= toDate }
            }
        }

        // Pagination
        let total = logs.count
        let offset = max(req.query[Int.self, at: "offset"] ?? 0, 0)
        let limit = min(max(req.query[Int.self, at: "limit"] ?? 50, 1), 500)
        let paginatedLogs = Array(logs.dropFirst(offset).prefix(limit))

        // Build response with pagination metadata
        let logsData = try JSONEncoder.iso8601.encode(paginatedLogs)
        let logsJson = (try? JSONSerialization.jsonObject(with: logsData)) ?? []
        let response: [String: Any] = [
            "logs": logsJson,
            "total": total,
            "offset": offset,
            "limit": limit
        ]
        let responseData = try JSONSerialization.data(withJSONObject: response)

        return jsonResponse(data: responseData)
    }

    // MARK: - Scene REST Handlers

    private func handleRestGetScenes(_ req: Request) async throws -> Response {
        let rawScenes = await MainActor.run { homeKitManager.getAllScenes() }
        let scenes = handler.stableScenes(rawScenes)
        let restScenes = scenes.map { RESTScene.from($0) }

        let data = try JSONEncoder.iso8601.encode(restScenes)
        logRESTCall(method: "GET", path: "/scenes", statusCode: 200,
                    resultSummary: "\(restScenes.count) scenes",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestGetScene(_ req: Request) async throws -> Response {
        guard let sceneId = req.parameters.get("sceneId") else {
            logRESTCall(method: "GET", path: "/scenes/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest)
        }

        let rawScene = await MainActor.run { homeKitManager.getScene(id: sceneId) }

        guard let rawScene else {
            logRESTCall(method: "GET", path: "/scenes/\(sceneId)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Scene not found")
        }

        let scene = handler.stableScenes([rawScene]).first ?? rawScene
        let restScene = RESTScene.from(scene)
        let data = try JSONEncoder.iso8601.encode(restScene)
        logRESTCall(method: "GET", path: "/scenes/\(sceneId)", statusCode: 200,
                    resultSummary: restScene.name,
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestExecuteScene(_ req: Request) async throws -> Response {
        guard let sceneId = req.parameters.get("sceneId") else {
            logRESTCall(method: "POST", path: "/scenes/:id/execute", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest)
        }

        do {
            try await homeKitManager.executeScene(id: sceneId)
            let scene = await MainActor.run { homeKitManager.getScene(id: sceneId) }
            let sceneName = scene?.name ?? sceneId

            let result: [String: Any] = ["success": true, "scene": sceneName]
            let data = try JSONSerialization.data(withJSONObject: result)
            logRESTCall(method: "POST", path: "/scenes/\(sceneId)/execute", statusCode: 200,
                        resultSummary: "Executed: \(sceneName)",
                        req: req, responseBody: String(data: data, encoding: .utf8))
            return jsonResponse(data: data)
        } catch {
            logRESTCall(method: "POST", path: "/scenes/\(sceneId)/execute", statusCode: 500,
                        resultSummary: "Error: \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }
    }

    // MARK: - Automation REST Handlers

    private struct AutomationRuntimeResponse: Codable {
        struct SunEventsInfo: Codable {
            let sunrise: String?
            let sunset: String?
            let locationConfigured: Bool
            let cityName: String?
        }
        let sunEvents: SunEventsInfo
    }

    private func handleGetAutomationRuntime() -> Response {
        let latitude = storage.readSunEventLatitude()
        let longitude = storage.readSunEventLongitude()
        let locationConfigured = latitude != 0 || longitude != 0

        var sunriseISO: String?
        var sunsetISO: String?

        if locationConfigured {
            let times = SolarCalculator.sunTimes(for: Date(), latitude: latitude, longitude: longitude)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let sr = times.sunrise { sunriseISO = formatter.string(from: sr) }
            if let ss = times.sunset { sunsetISO = formatter.string(from: ss) }
        }

        let cityName = storage.readSunEventCityName()
        let response = AutomationRuntimeResponse(
            sunEvents: .init(
                sunrise: sunriseISO,
                sunset: sunsetISO,
                locationConfigured: locationConfigured,
                cityName: cityName.isEmpty ? nil : cityName
            )
        )

        do {
            let data = try JSONEncoder().encode(response)
            return jsonResponse(data: data)
        } catch {
            return jsonResponse(data: "{}".data(using: .utf8)!, status: .internalServerError)
        }
    }

    private func handleRestGetAutomations(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        let automations = await automationStorageService.getAllAutomations()
        let data = try JSONEncoder.iso8601.encode(automations)
        logRESTCall(method: "GET", path: "/automations", statusCode: 200,
                    resultSummary: "\(automations.count) automations",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestGetAutomation(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let idStr = req.parameters.get("automationId"),
              let automationId = UUID(uuidString: idStr) else {
            logRESTCall(method: "GET", path: "/automations/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid automation ID")
        }

        guard let automation = await automationStorageService.getAutomation(id: automationId) else {
            logRESTCall(method: "GET", path: "/automations/\(idStr)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Automation not found")
        }

        let data = try JSONEncoder.iso8601.encode(automation)
        logRESTCall(method: "GET", path: "/automations/\(idStr)", statusCode: 200,
                    resultSummary: automation.name,
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestCreateAutomation(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let body = req.body.data,
              let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest, reason: "Missing request body")
        }

        let automation: Automation
        do {
            // Try direct decode first
            var dict = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]

            // Set defaults
            if dict["id"] == nil { dict["id"] = UUID().uuidString }
            if dict["isEnabled"] == nil {
                if let enabled = dict["enabled"] as? Bool {
                    dict["isEnabled"] = enabled
                    dict.removeValue(forKey: "enabled")
                } else {
                    dict["isEnabled"] = true
                }
            }
            if dict["continueOnError"] == nil { dict["continueOnError"] = false }
            if dict["triggers"] == nil { dict["triggers"] = [] as [Any] }
            if dict["blocks"] == nil { dict["blocks"] = [] as [Any] }
            let now = ISO8601DateFormatter().string(from: Date())
            if dict["createdAt"] == nil { dict["createdAt"] = now }
            if dict["updatedAt"] == nil { dict["updatedAt"] = now }
            if var meta = dict["metadata"] as? [String: Any] {
                if meta["totalExecutions"] == nil { meta["totalExecutions"] = 0 }
                if meta["consecutiveFailures"] == nil { meta["consecutiveFailures"] = 0 }
                dict["metadata"] = meta
            } else {
                dict["metadata"] = ["totalExecutions": 0, "consecutiveFailures": 0] as [String: Any]
            }

            let normalizedData = try JSONSerialization.data(withJSONObject: dict)
            automation = try JSONDecoder.iso8601.decode(Automation.self, from: normalizedData)
        } catch {
            AppLogger.server.error("Automation JSON parse error: \(error.localizedDescription)")
            logRESTCall(method: "POST", path: "/automations", statusCode: 400, resultSummary: "Parse Error")
            throw Abort(.badRequest, reason: "Invalid automation JSON")
        }

        // Validate characteristic permissions (notify for triggers, write for control blocks)
        if let validationError = await handler.validateAutomationPermissions(automation) {
            logRESTCall(method: "POST", path: "/automations", statusCode: 400, resultSummary: "Validation Error")
            throw Abort(.badRequest, reason: validationError)
        }

        let created = await automationStorageService.createAutomation(automation)
        let data = try JSONEncoder.iso8601.encode(created)
        logRESTCall(method: "POST", path: "/automations", statusCode: 201,
                    resultSummary: "Created: \(created.name)",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data, status: .created)
    }

    private func handleRestUpdateAutomation(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let idStr = req.parameters.get("automationId"),
              let automationId = UUID(uuidString: idStr) else {
            logRESTCall(method: "PUT", path: "/automations/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid automation ID")
        }

        guard let body = req.body.data,
              let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest, reason: "Missing request body")
        }

        guard await automationStorageService.getAutomation(id: automationId) != nil else {
            logRESTCall(method: "PUT", path: "/automations/\(idStr)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Automation not found")
        }

        let updates: [String: Any]
        do {
            updates = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
        } catch {
            throw Abort(.badRequest, reason: "Invalid JSON")
        }

        do {
            // Parse partial updates for triggers/conditions/blocks
            var parsedTriggers: [AutomationTrigger]?
            var parsedConditions: [AutomationCondition]?
            var parsedBlocks: [AutomationBlock]?

            if let triggersArray = updates["triggers"] {
                let data = try JSONSerialization.data(withJSONObject: triggersArray)
                parsedTriggers = try JSONDecoder.iso8601.decode([AutomationTrigger].self, from: data)
            }
            if let conditionsArray = updates["conditions"] {
                let data = try JSONSerialization.data(withJSONObject: conditionsArray)
                parsedConditions = try JSONDecoder.iso8601.decode([AutomationCondition].self, from: data)
            }
            if let blocksArray = updates["blocks"] {
                let data = try JSONSerialization.data(withJSONObject: blocksArray)
                parsedBlocks = try JSONDecoder.iso8601.decode([AutomationBlock].self, from: data)
            }

            // Build a preview of the merged automation for validation
            guard var existing = await automationStorageService.getAutomation(id: automationId) else {
                throw Abort(.notFound, reason: "Automation not found")
            }
            if let name = updates["name"] as? String { existing.name = name }
            if let triggers = parsedTriggers { existing.triggers = triggers }
            if let blocks = parsedBlocks { existing.blocks = blocks }

            // Validate characteristic permissions (notify for triggers, write for control blocks)
            if let validationError = await handler.validateAutomationPermissions(existing) {
                logRESTCall(method: "PUT", path: "/automations/\(idStr)", statusCode: 400, resultSummary: "Validation Error")
                throw Abort(.badRequest, reason: validationError)
            }

            let updated = await automationStorageService.updateAutomation(id: automationId) { automation in
                if let name = updates["name"] as? String { automation.name = name }
                if let desc = updates["description"] as? String { automation.description = desc }
                if let enabled = updates["isEnabled"] as? Bool { automation.isEnabled = enabled }
                if let coe = updates["continueOnError"] as? Bool { automation.continueOnError = coe }
                if let policyStr = updates["retriggerPolicy"] as? String,
                   let policy = ConcurrentExecutionPolicy(rawValue: policyStr) { automation.retriggerPolicy = policy }
                if let triggers = parsedTriggers { automation.triggers = triggers }
                if let conditions = parsedConditions { automation.conditions = conditions }
                if let blocks = parsedBlocks { automation.blocks = blocks }
            }

            guard let updated else {
                throw Abort(.internalServerError, reason: "Failed to update automation")
            }

            let data = try JSONEncoder.iso8601.encode(updated)
            logRESTCall(method: "PUT", path: "/automations/\(idStr)", statusCode: 200,
                        resultSummary: "Updated: \(updated.name)",
                        req: req, responseBody: String(data: data, encoding: .utf8))

            return jsonResponse(data: data)
        } catch let error as Abort {
            throw error
        } catch {
            logRESTCall(method: "PUT", path: "/automations/\(idStr)", statusCode: 400, resultSummary: "Parse Error")
            AppLogger.server.error("Automation update parse error: \(error.localizedDescription)")
            throw Abort(.badRequest, reason: "Failed to parse automation update")
        }
    }

    private func handleRestDeleteAutomation(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let idStr = req.parameters.get("automationId"),
              let automationId = UUID(uuidString: idStr) else {
            logRESTCall(method: "DELETE", path: "/automations/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid automation ID")
        }

        let deleted = await automationStorageService.deleteAutomation(id: automationId)
        if deleted {
            logRESTCall(method: "DELETE", path: "/automations/\(idStr)", statusCode: 200, resultSummary: "Deleted")
            return Response(status: .ok, body: .init(string: "{\"deleted\": true}"))
        } else {
            logRESTCall(method: "DELETE", path: "/automations/\(idStr)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Automation not found")
        }
    }

    private func handleRestTriggerAutomation(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let idStr = req.parameters.get("automationId"),
              let automationId = UUID(uuidString: idStr) else {
            logRESTCall(method: "POST", path: "/automations/:id/trigger", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid automation ID")
        }

        let result = await automationEngine.scheduleTrigger(id: automationId)

        let httpStatus = HTTPStatus(statusCode: Int(result.httpStatusCode))
        let data = try JSONEncoder.iso8601.encode(result)
        logRESTCall(method: "POST", path: "/automations/\(idStr)/trigger", statusCode: UInt(httpStatus.code),
                    resultSummary: result.message,
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data, status: httpStatus)
    }

    private func handleRestGetAutomationLogs(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let idStr = req.parameters.get("automationId"),
              let automationId = UUID(uuidString: idStr) else {
            logRESTCall(method: "GET", path: "/automations/:id/logs", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid automation ID")
        }

        let limit = min(max(req.query[Int.self, at: "limit"] ?? 50, 1), 500)
        var logs = await loggingService.getLogs(forAutomationId: automationId).compactMap(\.automationExecution)
        logs = Array(logs.prefix(limit))

        let data = try JSONEncoder.iso8601.encode(logs)
        logRESTCall(method: "GET", path: "/automations/\(idStr)/logs", statusCode: 200,
                    resultSummary: "\(logs.count) logs",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    private func handleRestWebhookTrigger(_ req: Request) async throws -> Response {
        try guardAutomationsEnabled()
        guard let token = req.parameters.get("token"), token.count >= 32 else {
            logRESTCall(method: "POST", path: "/automations/webhook/:token", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Missing or invalid webhook token")
        }

        // Find all enabled automations with a webhook trigger matching this token
        let allAutomations = await automationStorageService.getEnabledAutomations()
        let matchingAutomations = allAutomations.filter { automation in
            automation.triggers.contains { trigger in
                if case .webhook(let wt) = trigger { return wt.token == token }
                return false
            }
        }

        guard !matchingAutomations.isEmpty else {
            logRESTCall(method: "POST", path: "/automations/webhook/\(token.prefix(8))...", statusCode: 404, resultSummary: "No matching automations")
            throw Abort(.notFound, reason: "No automation found for this webhook token")
        }

        var results: [TriggerResult] = []
        for automation in matchingAutomations {
            // Find the matching webhook trigger to extract its per-trigger guard conditions
            let matchingTrigger = automation.triggers.first { trigger in
                if case .webhook(let wt) = trigger { return wt.token == token }
                return false
            }
            let triggerEvent = TriggerEvent(
                deviceId: nil,
                deviceName: nil,
                serviceName: nil,
                characteristicName: nil,
                roomName: nil,
                oldValue: nil,
                newValue: nil,
                triggerDescription: "Webhook received (token \(String(token.prefix(8)))…)"
            )
            let result = await automationEngine.scheduleTrigger(id: automation.id, triggerEvent: triggerEvent, policy: nil, triggerConditions: matchingTrigger?.conditions)
            results.append(result)
        }

        let data = try JSONEncoder.iso8601.encode(results)
        logRESTCall(method: "POST", path: "/automations/webhook/\(token.prefix(8))...", statusCode: 202,
                    resultSummary: "\(results.filter(\.isAccepted).count)/\(results.count) automations scheduled",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data, status: .accepted)
    }

    // MARK: - AI Automation Generation

    private func handleRestGenerateAutomation(_ req: Request) async throws -> Response {
        guard let aiService = aiAutomationService else {
            logRESTCall(method: "POST", path: "/automations/generate", statusCode: 503, resultSummary: "AI service unavailable")
            throw Abort(.serviceUnavailable, reason: "AI service is not available")
        }

        guard let body = req.body.data,
              let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            logRESTCall(method: "POST", path: "/automations/generate", statusCode: 400, resultSummary: "Missing body")
            throw Abort(.badRequest, reason: "Missing request body")
        }

        struct GenerateRequest: Decodable {
            let prompt: String
            let deviceIds: [String]?
            let sceneIds: [String]?
        }

        let generateReq: GenerateRequest
        do {
            generateReq = try JSONDecoder().decode(GenerateRequest.self, from: bodyData)
        } catch {
            logRESTCall(method: "POST", path: "/automations/generate", statusCode: 400, resultSummary: "Invalid JSON")
            throw Abort(.badRequest, reason: "Request body must contain a \"prompt\" string field")
        }

        guard !generateReq.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logRESTCall(method: "POST", path: "/automations/generate", statusCode: 400, resultSummary: "Empty prompt")
            throw Abort(.badRequest, reason: "Prompt must not be empty")
        }

        let automation: Automation
        do {
            automation = try await aiService.generateAutomation(from: generateReq.prompt, deviceIds: generateReq.deviceIds, sceneIds: generateReq.sceneIds)
        } catch let error as AIAutomationError {
            let statusCode: HTTPResponseStatus
            switch error {
            case .notConfigured:
                statusCode = .serviceUnavailable
            case .vagueprompt:
                statusCode = .unprocessableEntity
            case .modelRefused:
                statusCode = .unprocessableEntity
            case .networkError, .apiError:
                statusCode = .badGateway
            case .parseError, .noJSONFound:
                statusCode = .internalServerError
            }
            let errorMessage = error.errorDescription ?? "AI generation failed"
            logRESTCall(method: "POST", path: "/automations/generate",
                        statusCode: UInt(statusCode.code),
                        resultSummary: "AI Error: \(errorMessage)")
            let errorBody = try JSONSerialization.data(withJSONObject: ["error": errorMessage])
            return jsonResponse(data: errorBody, status: statusCode)
        } catch {
            logRESTCall(method: "POST", path: "/automations/generate", statusCode: 500,
                        resultSummary: "Unexpected error: \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }

        let created = await automationStorageService.createAutomation(automation)

        let generateResponseBody = try JSONSerialization.data(withJSONObject: [
            "id": created.id.uuidString,
            "name": created.name,
            "description": created.description ?? ""
        ])
        logRESTCall(method: "POST", path: "/automations/generate", statusCode: 201,
                    resultSummary: "Generated: \(created.name)",
                    req: req, responseBody: String(data: generateResponseBody, encoding: .utf8))

        return jsonResponse(data: generateResponseBody, status: .created)
    }

    private func handleRestImproveAutomation(_ req: Request) async throws -> Response {
        guard let aiService = aiAutomationService else {
            logRESTCall(method: "POST", path: "/automations/:id/improve", statusCode: 503, resultSummary: "AI service unavailable")
            throw Abort(.serviceUnavailable, reason: "AI service is not available")
        }

        guard let idStr = req.parameters.get("automationId"),
              let automationId = UUID(uuidString: idStr) else {
            logRESTCall(method: "POST", path: "/automations/:id/improve", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid automation ID")
        }

        guard let existing = await automationStorageService.getAutomation(id: automationId) else {
            logRESTCall(method: "POST", path: "/automations/\(idStr)/improve", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Automation not found")
        }

        struct ImproveRequest: Decodable {
            let prompt: String?
        }

        let defaultPrompt = "Review this automation and suggest improvements. Fix any labels that don't match their configuration. Optimize the structure if possible."

        var feedback = defaultPrompt
        if let body = req.body.data,
           let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes),
           let improveReq = try? JSONDecoder().decode(ImproveRequest.self, from: bodyData),
           let prompt = improveReq.prompt,
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            feedback = prompt
        }

        let improved: Automation
        do {
            improved = try await aiService.refineAutomation(existing, feedback: feedback)
        } catch let error as AIAutomationError {
            let statusCode: HTTPResponseStatus
            switch error {
            case .notConfigured:
                statusCode = .serviceUnavailable
            case .vagueprompt:
                statusCode = .unprocessableEntity
            case .modelRefused:
                statusCode = .unprocessableEntity
            case .networkError, .apiError:
                statusCode = .badGateway
            case .parseError, .noJSONFound:
                statusCode = .internalServerError
            }
            let errorMessage = error.errorDescription ?? "AI improvement failed"
            logRESTCall(method: "POST", path: "/automations/\(idStr)/improve",
                        statusCode: UInt(statusCode.code),
                        resultSummary: "AI Error: \(errorMessage)")
            let errorBody = try JSONSerialization.data(withJSONObject: ["error": errorMessage])
            return jsonResponse(data: errorBody, status: statusCode)
        } catch {
            logRESTCall(method: "POST", path: "/automations/\(idStr)/improve", statusCode: 500,
                        resultSummary: "Unexpected error: \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }

        // Preserve identity from the original automation
        let result = Automation(
            id: existing.id,
            name: improved.name,
            description: improved.description,
            isEnabled: improved.isEnabled,
            triggers: improved.triggers,
            conditions: improved.conditions,
            blocks: improved.blocks,
            continueOnError: improved.continueOnError,
            retriggerPolicy: improved.retriggerPolicy,
            metadata: existing.metadata,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )

        let data = try JSONEncoder.iso8601.encode(result)
        logRESTCall(method: "POST", path: "/automations/\(idStr)/improve", statusCode: 200,
                    resultSummary: "Improved: \(result.name)",
                    req: req, responseBody: String(data: data, encoding: .utf8))

        return jsonResponse(data: data)
    }

    // MARK: - Streamable HTTP Transport

    private func handleStreamablePost(_ req: Request) async throws -> Response {
        guard let body = req.body.data,
              let data = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest)
        }

        // Try decoding as a batch (JSON array) first, then fall back to single request.
        let requests: [JSONRPCRequest]
        let isBatch: Bool
        do {
            if let batchRequests = try? JSONDecoder.iso8601.decode([JSONRPCRequest].self, from: data) {
                requests = batchRequests
                isBatch = true
            } else {
                let single = try JSONDecoder.iso8601.decode(JSONRPCRequest.self, from: data)
                requests = [single]
                isBatch = false
            }
        } catch {
            let errorResponse = JSONRPCResponse.error(
                id: nil,
                code: MCPErrorCode.parseError,
                message: "Failed to parse JSON-RPC request"
            )
            return try encodeJSONResponse(errorResponse)
        }

        // Determine if this is an initialize request (exempt from session check).
        let isInitialize = requests.contains { $0.method == "initialize" }

        // Session validation: non-initialize requests must carry a valid Mcp-Session-Id.
        if !isInitialize {
            if let sessionId = req.headers.first(name: "Mcp-Session-Id") {
                let valid = await connectionTracker.hasSession(sessionId)
                if !valid {
                    return Response(status: .notFound)
                }
                await connectionTracker.touchSession(sessionId)
            } else {
                let hasSessions = await connectionTracker.hasAnySessions()
                if hasSessions {
                    return Response(status: .badRequest)
                }
            }
        }

        // Check if all messages are notifications (no id)
        let allNotifications = requests.allSatisfy { $0.id == nil }
        if allNotifications {
            return Response(status: .accepted)
        }

        // Process each request
        var responses: [JSONRPCResponse] = []
        var sessionIdToAttach: String?

        for request in requests {
            // Skip notifications — they don't produce a response
            if request.id == nil { continue }

            let response = await handler.handle(request)
            responses.append(response)

            // If this was an initialize request, create a new session
            if request.method == "initialize" {
                let newSessionId = UUID().uuidString
                await connectionTracker.addSession(newSessionId)
                sessionIdToAttach = newSessionId
            }
        }

        // Encode the response
        let httpResponse: Response
        if isBatch {
            httpResponse = try encodeBatchJSONResponse(responses)
        } else if let single = responses.first {
            httpResponse = try encodeJSONResponse(single)
        } else {
            return Response(status: .accepted)
        }

        // Attach Mcp-Session-Id header on initialize response
        if let sessionId = sessionIdToAttach {
            httpResponse.headers.add(name: "Mcp-Session-Id", value: sessionId)
        }

        return httpResponse
    }

    /// MCP Streamable HTTP spec: GET is reserved for future SSE-based server-initiated notifications.
    /// Currently unsupported — return 405 per spec.
    private func handleStreamableGet(_ req: Request) -> Response {
        return Response(status: .methodNotAllowed)
    }

    private func handleStreamableDelete(_ req: Request) async -> Response {
        guard let sessionId = req.headers.first(name: "Mcp-Session-Id") else {
            return Response(status: .badRequest)
        }

        let removed = await connectionTracker.removeSession(sessionId)
        return removed ? Response(status: .ok) : Response(status: .notFound)
    }

    // MARK: - Legacy SSE Transport (2024-11-05)

    private func handleLegacySSE(_ req: Request) -> Response {
        let connectionId = UUID()
        let tracker = connectionTracker

        let host = req.headers.first(name: .host) ?? "127.0.0.1:\(port)"
        let messagesURL = "http://\(host)/messages?sessionId=\(connectionId.uuidString)"

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/event-stream")
        headers.add(name: .cacheControl, value: "no-cache")
        headers.add(name: .connection, value: "keep-alive")

        let response = Response(
            status: .ok,
            headers: headers,
            body: .init(managedAsyncStream: { [weak self] writer in
                // Register the connection with its writer
                await tracker.addSSEConnection(id: connectionId, writer: writer)
                self?.updateClientCount()

                // Send the endpoint event first
                let endpointEvent = "event: endpoint\ndata: \(messagesURL)\n\n"
                try await writer.writeBuffer(ByteBuffer(string: endpointEvent))

                // Keep the connection alive with periodic keepalive comments
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    guard !Task.isCancelled else { break }
                    do {
                        try await writer.writeBuffer(ByteBuffer(string: ": keepalive\n\n"))
                    } catch {
                        break
                    }
                }

                // Cleanup on disconnect
                await tracker.removeSSEConnection(id: connectionId)
                self?.updateClientCount()
            })
        )

        return response
    }

    private func handleLegacyMessages(_ req: Request) async throws -> Response {
        guard let sessionIdStr = req.query[String.self, at: "sessionId"],
              let sessionId = UUID(uuidString: sessionIdStr) else {
            throw Abort(.badRequest, reason: "Missing or invalid sessionId")
        }

        guard let writer = await connectionTracker.getSSEWriter(for: sessionId) else {
            throw Abort(.notFound, reason: "Session not found")
        }

        guard let body = req.body.data,
              let data = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest)
        }

        let jsonrpcRequest: JSONRPCRequest
        do {
            jsonrpcRequest = try JSONDecoder.iso8601.decode(JSONRPCRequest.self, from: data)
        } catch {
            throw Abort(.badRequest, reason: "Invalid JSON-RPC request")
        }

        // Handle notifications — return 202
        if jsonrpcRequest.id == nil {
            return Response(status: .accepted)
        }

        let jsonrpcResponse = await handler.handle(jsonrpcRequest)

        // Send response on the SSE stream
        let responseData = try JSONEncoder.iso8601.encode(jsonrpcResponse)
        if let responseString = String(data: responseData, encoding: .utf8) {
            let sseEvent = "event: message\ndata: \(responseString)\n\n"
            try? await writer.writeBuffer(ByteBuffer(string: sseEvent))
        }

        return Response(status: .accepted)
    }

    // MARK: - Helpers

    /// Build a 200 OK JSON HTTP response from a `JSONRPCResponse`.
    private func encodeJSONResponse(_ response: JSONRPCResponse) throws -> Response {
        let data = try JSONEncoder.iso8601.encode(response)
        return jsonResponse(data: data)
    }

    /// Build a 200 OK JSON HTTP response from a batch of `JSONRPCResponse` objects.
    private func encodeBatchJSONResponse(_ responses: [JSONRPCResponse]) throws -> Response {
        let data = try JSONEncoder.iso8601.encode(responses)
        return jsonResponse(data: data)
    }

    /// Build an `application/json` response from raw encoded data.
    /// Single source of truth for REST and MCP JSON response construction.
    private func jsonResponse(data: Data, status: HTTPResponseStatus = .ok) -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: status, headers: headers, body: .init(data: data))
    }

    private func updateClientCount() {
        Task {
            let sseCount = await connectionTracker.sseConnectionCount
            let wsCount = await connectionTracker.wsConnectionCount
            await MainActor.run { [weak self] in
                self?.connectedClients = sseCount + wsCount
            }
        }
    }

    private func logRESTCall(method: String, path: String, statusCode: UInt,
                             resultSummary: String, req: Request? = nil,
                             responseBody: String? = nil) {
        guard storage.readLoggingEnabled(), storage.readRestLoggingEnabled() else { return }
        Task {
            var detailedReq: String?
            var detailedResp: String?
            if storage.readRestDetailedLogsEnabled() {
                if let req {
                    let clientIP = req.headers.first(name: "X-Forwarded-For") ?? req.remoteAddress?.ipAddress ?? "unknown"
                    let userAgent = req.headers.first(name: .userAgent) ?? "unknown"
                    let contentType = req.headers.first(name: .contentType) ?? "-"
                    let query = req.url.query.map { "?\($0)" } ?? ""
                    var parts = """
                    Client: \(clientIP)
                    User-Agent: \(userAgent)
                    Content-Type: \(contentType)
                    URL: \(method) \(path)\(query)
                    """
                    if let body = req.body.data,
                       let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes),
                       !bodyData.isEmpty,
                       let bodyStr = String(data: bodyData, encoding: .utf8) {
                        parts += "\n\nBody:\n\(bodyStr)"
                    }
                    detailedReq = parts
                }
                detailedResp = responseBody
            }
            let entry = StateChangeLog.restCall(
                method: "\(method) \(path)",
                summary: "\(method) \(path)",
                result: "\(statusCode) \(resultSummary)",
                detailedRequest: detailedReq,
                detailedResponse: detailedResp
            )
            await loggingService.logEntry(entry)
        }
    }

    private func logServerError(_ message: String) {
        Task {
            let entry = StateChangeLog.serverError(errorDetails: message)
            await loggingService.logEntry(entry)
        }
    }

    // MARK: - OAuth Helpers

    private func tokenResponse(_ token: OAuthToken) -> Response {
        let body: [String: Any] = [
            "access_token": token.accessToken,
            "token_type": "bearer",
            "expires_in": Int(token.expiresAt.timeIntervalSinceNow),
            "refresh_token": token.refreshToken
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return Response(status: .internalServerError)
        }
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: .cacheControl, value: "no-store")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
}

// MARK: - Bearer Auth Middleware

/// Vapor middleware that validates `Authorization: Bearer <token>` on every request.
/// Accepts any token present in the `validTokens` set (multi-client support) or a valid OAuth access token.
private struct BearerAuthMiddleware: AsyncMiddleware {
    let validTokens: Set<String>
    let oauthService: OAuthService

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let authHeader = request.headers.first(name: .authorization) else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Missing Authorization header\"}"))
        }

        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Invalid Authorization scheme. Use Bearer.\"}"))
        }

        let token = String(authHeader.dropFirst(prefix.count))

        // Check static Bearer tokens first
        if validTokens.contains(token) {
            return try await next.respond(to: request)
        }

        // Check OAuth access tokens
        if await oauthService.validateAccessToken(token) != nil {
            request.storage[OAuthAccessTokenKey.self] = token
            return try await next.respond(to: request)
        }

        return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Invalid API token\"}"))
    }
}

/// Request storage key for tracking which OAuth token authenticated the request.
private struct OAuthAccessTokenKey: StorageKey {
    typealias Value = String
}

// MARK: - Connection Tracker

/// Actor that manages SSE connections and Streamable HTTP sessions
/// with TTL-based expiration and idle timeout.
private actor ConnectionTracker {
    private var sseConnections: [UUID: any AsyncBodyStreamWriter] = [:]
    private var wsConnections: [UUID: WebSocket] = [:]

    // OAuth token → connection mapping for revocation
    private var tokenToSSE: [String: Set<UUID>] = [:]
    private var tokenToWS: [String: Set<UUID>] = [:]

    func associateToken(_ token: String, withSSE id: UUID) {
        tokenToSSE[token, default: []].insert(id)
    }

    func associateToken(_ token: String, withWS id: UUID) {
        tokenToWS[token, default: []].insert(id)
    }

    func revokeTokenConnections(_ accessTokens: Set<String>) {
        for token in accessTokens {
            if let sseIds = tokenToSSE.removeValue(forKey: token) {
                for id in sseIds {
                    sseConnections.removeValue(forKey: id)
                }
            }
            if let wsIds = tokenToWS.removeValue(forKey: token) {
                for id in wsIds {
                    if let ws = wsConnections.removeValue(forKey: id) {
                        try? ws.close(code: .policyViolation).wait()
                    }
                }
            }
        }
    }

    func dissociateSSE(id: UUID) {
        for (token, var ids) in tokenToSSE {
            ids.remove(id)
            if ids.isEmpty {
                tokenToSSE.removeValue(forKey: token)
            } else {
                tokenToSSE[token] = ids
            }
        }
    }

    func dissociateWS(id: UUID) {
        for (token, var ids) in tokenToWS {
            ids.remove(id)
            if ids.isEmpty {
                tokenToWS.removeValue(forKey: token)
            } else {
                tokenToWS[token] = ids
            }
        }
    }

    private struct SessionInfo {
        let createdAt: Date
        var lastActivity: Date
    }

    private var activeSessions: [String: SessionInfo] = [:]
    private var cleanupTask: Task<Void, Never>?

    /// Maximum session lifetime (24 hours).
    private let sessionTTL: TimeInterval = 24 * 60 * 60
    /// Idle timeout (1 hour).
    private let idleTimeout: TimeInterval = 60 * 60
    /// Cleanup sweep interval (5 minutes).
    private let cleanupInterval: UInt64 = 5 * 60 * 1_000_000_000

    var sseConnectionCount: Int { sseConnections.count }
    var wsConnectionCount: Int { wsConnections.count }

    // MARK: - SSE Connections

    func addSSEConnection(id: UUID, writer: any AsyncBodyStreamWriter) {
        sseConnections[id] = writer
    }

    func removeSSEConnection(id: UUID) {
        sseConnections.removeValue(forKey: id)
    }

    func getSSEWriter(for id: UUID) -> (any AsyncBodyStreamWriter)? {
        sseConnections[id]
    }

    // MARK: - WebSocket Connections

    func addWSConnection(id: UUID, ws: WebSocket) {
        wsConnections[id] = ws
        startCleanupIfNeeded()
    }

    func removeWSConnection(id: UUID) {
        wsConnections.removeValue(forKey: id)
    }

    /// Send a text message to all connected WebSocket clients.
    func broadcastToWS(_ text: String) {
        for (id, ws) in wsConnections {
            guard !ws.isClosed else {
                wsConnections.removeValue(forKey: id)
                continue
            }
            ws.send(text)
        }
    }

    /// Remove WebSocket connections that have silently closed.
    func sweepStaleWSConnections() {
        let stale = wsConnections.filter { $0.value.isClosed }
        for id in stale.keys {
            wsConnections.removeValue(forKey: id)
        }
    }

    // MARK: - Streamable HTTP Sessions

    func hasSession(_ sessionId: String) -> Bool {
        guard let info = activeSessions[sessionId] else { return false }
        let now = Date()
        if now.timeIntervalSince(info.createdAt) > sessionTTL ||
           now.timeIntervalSince(info.lastActivity) > idleTimeout {
            activeSessions.removeValue(forKey: sessionId)
            return false
        }
        return true
    }

    func hasAnySessions() -> Bool {
        !activeSessions.isEmpty
    }

    func addSession(_ sessionId: String) {
        let now = Date()
        activeSessions[sessionId] = SessionInfo(createdAt: now, lastActivity: now)
        startCleanupIfNeeded()
    }

    func touchSession(_ sessionId: String) {
        activeSessions[sessionId]?.lastActivity = Date()
    }

    func removeSession(_ sessionId: String) -> Bool {
        activeSessions.removeValue(forKey: sessionId) != nil
    }

    func removeAll() {
        sseConnections.removeAll()
        for (_, ws) in wsConnections {
            try? ws.close().wait()
        }
        wsConnections.removeAll()
        activeSessions.removeAll()
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    // MARK: - Session Cleanup

    private func startCleanupIfNeeded() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.cleanupInterval ?? 300_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.sweepExpiredSessions()
            }
        }
    }

    private func sweepExpiredSessions() {
        let now = Date()
        let expired = activeSessions.filter { (_, info) in
            now.timeIntervalSince(info.createdAt) > sessionTTL ||
            now.timeIntervalSince(info.lastActivity) > idleTimeout
        }
        for key in expired.keys {
            activeSessions.removeValue(forKey: key)
        }

        // Also sweep stale WebSocket connections that silently dropped
        sweepStaleWSConnections()

        if activeSessions.isEmpty && wsConnections.isEmpty {
            cleanupTask?.cancel()
            cleanupTask = nil
        }
    }
}
