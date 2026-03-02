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
    private let workflowStorageService: WorkflowStorageService
    private let workflowEngine: WorkflowEngine
    private let workflowExecutionLogService: WorkflowExecutionLogService
    private let keychainService: KeychainService
    private let registry: DeviceRegistryService?
    private let aiWorkflowService: AIWorkflowService?
    private var wsCancellables = Set<AnyCancellable>()
    private var serverTask: Task<Void, Never>?

    init(
        homeKitManager: HomeKitManager,
        loggingService: LoggingService,
        storage: StorageService,
        workflowStorageService: WorkflowStorageService,
        workflowEngine: WorkflowEngine,
        workflowExecutionLogService: WorkflowExecutionLogService,
        keychainService: KeychainService,
        registry: DeviceRegistryService? = nil,
        aiWorkflowService: AIWorkflowService? = nil,
        port: Int = 3000,
        handler: MCPRequestHandler? = nil
    ) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.storage = storage
        self.port = port
        self.workflowStorageService = workflowStorageService
        self.workflowEngine = workflowEngine
        self.workflowExecutionLogService = workflowExecutionLogService
        self.keychainService = keychainService
        self.registry = registry
        self.aiWorkflowService = aiWorkflowService
        self.handler = handler ?? MCPRequestHandler(
            homeKitManager: homeKitManager,
            loggingService: loggingService,
            storage: storage,
            workflowStorageService: workflowStorageService,
            workflowEngine: workflowEngine,
            workflowExecutionLogService: workflowExecutionLogService,
            registry: registry
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

        // Broadcast new state-change log entries
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
                }
            }
            .store(in: &wsCancellables)

        // Broadcast new workflow execution logs
        workflowExecutionLogService.logAddedSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] entry in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    self?.broadcastWorkflowLog(entry, type: "workflow_log", tracker: tracker)
                }
            }
            .store(in: &wsCancellables)

        // Broadcast updated workflow execution logs
        workflowExecutionLogService.logUpdatedSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] entry in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    self?.broadcastWorkflowLog(entry, type: "workflow_log_updated", tracker: tracker)
                }
            }
            .store(in: &wsCancellables)

        // Broadcast logs_cleared when either log store is cleared
        loggingService.logsClearedSubject
            .merge(with: workflowExecutionLogService.logsClearedSubject)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { _ in
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    let msg = "{\"type\":\"logs_cleared\"}"
                    await tracker.broadcastToWS(msg)
                }
            }
            .store(in: &wsCancellables)

        // Broadcast workflow definition changes (create/update/delete/enable/disable)
        workflowStorageService.workflowsSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] workflows in
                guard self != nil else { return }
                Task {
                    guard await tracker.wsConnectionCount > 0 else { return }
                    do {
                        let data = try JSONEncoder.iso8601.encode(workflows)
                        if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                            let msg: [String: Any] = ["type": "workflows_updated", "data": json]
                            let msgData = try JSONSerialization.data(withJSONObject: msg)
                            if let text = String(data: msgData, encoding: .utf8) {
                                await tracker.broadcastToWS(text)
                            }
                        }
                    } catch {
                        AppLogger.server.error("Failed to encode workflows for WS broadcast: \(error)")
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
                            let encoded = try? JSONEncoder.iso8601.encode(AnyCodable(v))
                            valueJson = encoded.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) ?? v
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

    private func broadcastWorkflowLog(_ entry: WorkflowExecutionLog, type: String, tracker: ConnectionTracker) {
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
                AppLogger.server.error("Failed to encode workflow log for WS broadcast: \(error)")
            }
        }
    }

    // MARK: - Route Configuration

    private func configureRoutes(_ app: Application) {
        let validTokens = keychainService.getValidTokenStrings()
        let authMiddleware = BearerAuthMiddleware(validTokens: validTokens)

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
                guard let token = req.query[String.self, at: "token"],
                      validTokens.contains(token) else {
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

                await tracker.removeWSConnection(id: connectionId)
                self.updateClientCount()
                AppLogger.server.info("WebSocket client disconnected: \(connectionId)")
            }
        }

        // All routes require bearer token auth
        let protected = app.grouped(authMiddleware)

        // Webhook trigger endpoint — requires Bearer auth + webhook token in URL path.
        protected.on(.POST, "workflows", "webhook", ":token", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
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

        // Workflow REST Endpoints
        protected.on(.GET, "workflows") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetWorkflows(req)
        }

        protected.on(.GET, "workflows", ":workflowId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetWorkflow(req)
        }

        protected.on(.POST, "workflows", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestCreateWorkflow(req)
        }

        protected.on(.PUT, "workflows", ":workflowId", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestUpdateWorkflow(req)
        }

        protected.on(.DELETE, "workflows", ":workflowId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestDeleteWorkflow(req)
        }

        protected.on(.POST, "workflows", ":workflowId", "trigger", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestTriggerWorkflow(req)
        }

        protected.on(.GET, "workflows", ":workflowId", "logs") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            return try await self.handleRestGetWorkflowLogs(req)
        }

        // AI Workflow Generation
        protected.on(.POST, "workflows", "generate", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            try self.guardWorkflowsEnabled()
            try self.guardAIEnabled()
            return try await self.handleRestGenerateWorkflow(req)
        }

        // Clear all logs (state-change logs + workflow execution logs)
        protected.on(.DELETE, "logs") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            try self.guardRestApiEnabled()
            guard self.storage.readLogAccessEnabled() else { throw Abort(.notFound) }
            await self.loggingService.clearLogs()
            await self.workflowExecutionLogService.clearLogs()
            let body = try JSONSerialization.data(withJSONObject: ["cleared": true])
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: body))
        }
    }
    
    // MARK: - REST Helpers

    private func guardWorkflowsEnabled() throws {
        guard storage.readWorkflowsEnabled() else {
            throw Abort(.notFound, reason: "Workflows are not enabled. Enable them in the app settings.")
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

    // MARK: - REST Handlers

    private func handleRestGetDevices(_ req: Request) async throws -> Response {
        let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
        let filteredDevices = handler.stableDevices(allDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }

        let data = try JSONEncoder.iso8601.encode(restDevices)
        logRESTCall(method: "GET", path: "/devices", statusCode: 200,
                    resultSummary: "\(restDevices.count) devices",
                    req: req)

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
                    req: req)

        return jsonResponse(data: data)
    }

    private func handleRestRenameService(_ req: Request) async throws -> Response {
        guard let serviceId = req.parameters.get("serviceId") else {
            logRESTCall(method: "PATCH", path: "/services/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest)
        }

        struct RenameBody: Codable { let name: String? }
        let body = try req.content.decode(RenameBody.self)

        await registry?.setServiceCustomName(stableServiceId: serviceId, customName: body.name)

        logRESTCall(method: "PATCH", path: "/services/\(serviceId)", statusCode: 200,
                    resultSummary: body.name ?? "(cleared)",
                    req: req)
        return jsonResponse(data: try JSONEncoder().encode(["success": true]))
    }

    // MARK: - Log REST Handler

    private func handleRestGetLogs(_ req: Request) async throws -> Response {
        // Fetch both log sources
        let stateChangeLogs = await loggingService.getLogs()
        let workflowExecLogs = await workflowExecutionLogService.getLogs()

        // Convert all workflow execution logs (including running ones) on-the-fly and merge.
        // WorkflowExecutionLogService is the single source for workflow logs; LoggingService
        // no longer persists workflow entries.
        let convertedWorkflowLogs = workflowExecLogs.map { $0.toStateChangeLog() }

        var logs = (stateChangeLogs + convertedWorkflowLogs)
            .sorted { $0.timestamp > $1.timestamp }

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
        let offset = req.query[Int.self, at: "offset"] ?? 0
        let limit = req.query[Int.self, at: "limit"] ?? 50
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
                    req: req)

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
                    req: req)

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

            logRESTCall(method: "POST", path: "/scenes/\(sceneId)/execute", statusCode: 200,
                        resultSummary: "Executed: \(sceneName)")

            let result: [String: Any] = ["success": true, "scene": sceneName]
            let data = try JSONSerialization.data(withJSONObject: result)
            return jsonResponse(data: data)
        } catch {
            logRESTCall(method: "POST", path: "/scenes/\(sceneId)/execute", statusCode: 500,
                        resultSummary: "Error: \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }
    }

    // MARK: - Workflow REST Handlers

    private func handleRestGetWorkflows(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        let workflows = await workflowStorageService.getAllWorkflows()
        let data = try JSONEncoder.iso8601.encode(workflows)
        logRESTCall(method: "GET", path: "/workflows", statusCode: 200,
                    resultSummary: "\(workflows.count) workflows",
                    req: req)

        return jsonResponse(data: data)
    }

    private func handleRestGetWorkflow(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let idStr = req.parameters.get("workflowId"),
              let workflowId = UUID(uuidString: idStr) else {
            logRESTCall(method: "GET", path: "/workflows/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid workflow ID")
        }

        guard let workflow = await workflowStorageService.getWorkflow(id: workflowId) else {
            logRESTCall(method: "GET", path: "/workflows/\(idStr)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Workflow not found")
        }

        let data = try JSONEncoder.iso8601.encode(workflow)
        logRESTCall(method: "GET", path: "/workflows/\(idStr)", statusCode: 200,
                    resultSummary: workflow.name,
                    req: req)

        return jsonResponse(data: data)
    }

    private func handleRestCreateWorkflow(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let body = req.body.data,
              let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest, reason: "Missing request body")
        }

        let workflow: Workflow
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
            workflow = try JSONDecoder.iso8601.decode(Workflow.self, from: normalizedData)
        } catch {
            AppLogger.server.error("Workflow JSON parse error: \(error.localizedDescription)")
            logRESTCall(method: "POST", path: "/workflows", statusCode: 400, resultSummary: "Parse Error")
            throw Abort(.badRequest, reason: "Invalid workflow JSON")
        }

        // Validate characteristic permissions (notify for triggers, write for control blocks)
        if let validationError = await handler.validateWorkflowPermissions(workflow) {
            logRESTCall(method: "POST", path: "/workflows", statusCode: 400, resultSummary: "Validation Error")
            throw Abort(.badRequest, reason: validationError)
        }

        let created = await workflowStorageService.createWorkflow(workflow)
        let data = try JSONEncoder.iso8601.encode(created)
        logRESTCall(method: "POST", path: "/workflows", statusCode: 201,
                    resultSummary: "Created: \(created.name)",
                    req: req)

        return jsonResponse(data: data, status: .created)
    }

    private func handleRestUpdateWorkflow(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let idStr = req.parameters.get("workflowId"),
              let workflowId = UUID(uuidString: idStr) else {
            logRESTCall(method: "PUT", path: "/workflows/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid workflow ID")
        }

        guard let body = req.body.data,
              let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest, reason: "Missing request body")
        }

        guard await workflowStorageService.getWorkflow(id: workflowId) != nil else {
            logRESTCall(method: "PUT", path: "/workflows/\(idStr)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Workflow not found")
        }

        let updates: [String: Any]
        do {
            updates = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
        } catch {
            throw Abort(.badRequest, reason: "Invalid JSON")
        }

        do {
            // Parse partial updates for triggers/conditions/blocks
            var parsedTriggers: [WorkflowTrigger]?
            var parsedConditions: [WorkflowCondition]?
            var parsedBlocks: [WorkflowBlock]?

            if let triggersArray = updates["triggers"] {
                let data = try JSONSerialization.data(withJSONObject: triggersArray)
                parsedTriggers = try JSONDecoder.iso8601.decode([WorkflowTrigger].self, from: data)
            }
            if let conditionsArray = updates["conditions"] {
                let data = try JSONSerialization.data(withJSONObject: conditionsArray)
                parsedConditions = try JSONDecoder.iso8601.decode([WorkflowCondition].self, from: data)
            }
            if let blocksArray = updates["blocks"] {
                let data = try JSONSerialization.data(withJSONObject: blocksArray)
                parsedBlocks = try JSONDecoder.iso8601.decode([WorkflowBlock].self, from: data)
            }

            // Build a preview of the merged workflow for validation
            guard var existing = await workflowStorageService.getWorkflow(id: workflowId) else {
                throw Abort(.notFound, reason: "Workflow not found")
            }
            if let name = updates["name"] as? String { existing.name = name }
            if let triggers = parsedTriggers { existing.triggers = triggers }
            if let blocks = parsedBlocks { existing.blocks = blocks }

            // Validate characteristic permissions (notify for triggers, write for control blocks)
            if let validationError = await handler.validateWorkflowPermissions(existing) {
                logRESTCall(method: "PUT", path: "/workflows/\(idStr)", statusCode: 400, resultSummary: "Validation Error")
                throw Abort(.badRequest, reason: validationError)
            }

            let updated = await workflowStorageService.updateWorkflow(id: workflowId) { workflow in
                if let name = updates["name"] as? String { workflow.name = name }
                if let desc = updates["description"] as? String { workflow.description = desc }
                if let enabled = updates["isEnabled"] as? Bool { workflow.isEnabled = enabled }
                if let coe = updates["continueOnError"] as? Bool { workflow.continueOnError = coe }
                if let policyStr = updates["retriggerPolicy"] as? String,
                   let policy = ConcurrentExecutionPolicy(rawValue: policyStr) { workflow.retriggerPolicy = policy }
                if let triggers = parsedTriggers { workflow.triggers = triggers }
                if let conditions = parsedConditions { workflow.conditions = conditions }
                if let blocks = parsedBlocks { workflow.blocks = blocks }
            }

            guard let updated else {
                throw Abort(.internalServerError, reason: "Failed to update workflow")
            }

            let data = try JSONEncoder.iso8601.encode(updated)
            logRESTCall(method: "PUT", path: "/workflows/\(idStr)", statusCode: 200,
                        resultSummary: "Updated: \(updated.name)",
                        req: req)

            return jsonResponse(data: data)
        } catch let error as Abort {
            throw error
        } catch {
            logRESTCall(method: "PUT", path: "/workflows/\(idStr)", statusCode: 400, resultSummary: "Parse Error")
            AppLogger.server.error("Workflow update parse error: \(error.localizedDescription)")
            throw Abort(.badRequest, reason: "Failed to parse workflow update")
        }
    }

    private func handleRestDeleteWorkflow(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let idStr = req.parameters.get("workflowId"),
              let workflowId = UUID(uuidString: idStr) else {
            logRESTCall(method: "DELETE", path: "/workflows/:id", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid workflow ID")
        }

        let deleted = await workflowStorageService.deleteWorkflow(id: workflowId)
        if deleted {
            logRESTCall(method: "DELETE", path: "/workflows/\(idStr)", statusCode: 200, resultSummary: "Deleted")
            return Response(status: .ok, body: .init(string: "{\"deleted\": true}"))
        } else {
            logRESTCall(method: "DELETE", path: "/workflows/\(idStr)", statusCode: 404, resultSummary: "Not Found")
            throw Abort(.notFound, reason: "Workflow not found")
        }
    }

    private func handleRestTriggerWorkflow(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let idStr = req.parameters.get("workflowId"),
              let workflowId = UUID(uuidString: idStr) else {
            logRESTCall(method: "POST", path: "/workflows/:id/trigger", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid workflow ID")
        }

        let result = await workflowEngine.scheduleTrigger(id: workflowId)

        let httpStatus = HTTPStatus(statusCode: Int(result.httpStatusCode))
        let data = try JSONEncoder.iso8601.encode(result)
        logRESTCall(method: "POST", path: "/workflows/\(idStr)/trigger", statusCode: UInt(httpStatus.code),
                    resultSummary: result.message,
                    req: req)

        return jsonResponse(data: data, status: httpStatus)
    }

    private func handleRestGetWorkflowLogs(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let idStr = req.parameters.get("workflowId"),
              let workflowId = UUID(uuidString: idStr) else {
            logRESTCall(method: "GET", path: "/workflows/:id/logs", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Invalid workflow ID")
        }

        let limit = req.query[Int.self, at: "limit"] ?? 50
        var logs = await workflowExecutionLogService.getLogs(forWorkflow: workflowId)
        logs = Array(logs.prefix(limit))

        let data = try JSONEncoder.iso8601.encode(logs)
        logRESTCall(method: "GET", path: "/workflows/\(idStr)/logs", statusCode: 200,
                    resultSummary: "\(logs.count) logs",
                    req: req)

        return jsonResponse(data: data)
    }

    private func handleRestWebhookTrigger(_ req: Request) async throws -> Response {
        try guardWorkflowsEnabled()
        guard let token = req.parameters.get("token"), token.count >= 32 else {
            logRESTCall(method: "POST", path: "/workflows/webhook/:token", statusCode: 400, resultSummary: "Bad Request")
            throw Abort(.badRequest, reason: "Missing or invalid webhook token")
        }

        // Find all enabled workflows with a webhook trigger matching this token
        let allWorkflows = await workflowStorageService.getEnabledWorkflows()
        let matchingWorkflows = allWorkflows.filter { workflow in
            workflow.triggers.contains { trigger in
                if case .webhook(let wt) = trigger { return wt.token == token }
                return false
            }
        }

        guard !matchingWorkflows.isEmpty else {
            logRESTCall(method: "POST", path: "/workflows/webhook/\(token.prefix(8))...", statusCode: 404, resultSummary: "No matching workflows")
            throw Abort(.notFound, reason: "No workflow found for this webhook token")
        }

        var results: [TriggerResult] = []
        for workflow in matchingWorkflows {
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
            let result = await workflowEngine.scheduleTrigger(id: workflow.id, triggerEvent: triggerEvent)
            results.append(result)
        }

        let data = try JSONEncoder.iso8601.encode(results)
        logRESTCall(method: "POST", path: "/workflows/webhook/\(token.prefix(8))...", statusCode: 202,
                    resultSummary: "\(results.filter(\.isAccepted).count)/\(results.count) workflows scheduled",
                    req: req)

        return jsonResponse(data: data, status: .accepted)
    }

    // MARK: - AI Workflow Generation

    private func handleRestGenerateWorkflow(_ req: Request) async throws -> Response {
        guard let aiService = aiWorkflowService else {
            logRESTCall(method: "POST", path: "/workflows/generate", statusCode: 503, resultSummary: "AI service unavailable")
            throw Abort(.serviceUnavailable, reason: "AI service is not available")
        }

        guard let body = req.body.data,
              let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            logRESTCall(method: "POST", path: "/workflows/generate", statusCode: 400, resultSummary: "Missing body")
            throw Abort(.badRequest, reason: "Missing request body")
        }

        struct GenerateRequest: Decodable {
            let prompt: String
        }

        let generateReq: GenerateRequest
        do {
            generateReq = try JSONDecoder().decode(GenerateRequest.self, from: bodyData)
        } catch {
            logRESTCall(method: "POST", path: "/workflows/generate", statusCode: 400, resultSummary: "Invalid JSON")
            throw Abort(.badRequest, reason: "Request body must contain a \"prompt\" string field")
        }

        guard !generateReq.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logRESTCall(method: "POST", path: "/workflows/generate", statusCode: 400, resultSummary: "Empty prompt")
            throw Abort(.badRequest, reason: "Prompt must not be empty")
        }

        let workflow: Workflow
        do {
            workflow = try await aiService.generateWorkflow(from: generateReq.prompt)
        } catch let error as AIWorkflowError {
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
            logRESTCall(method: "POST", path: "/workflows/generate",
                        statusCode: UInt(statusCode.code),
                        resultSummary: "AI Error: \(errorMessage)")
            let errorBody = try JSONSerialization.data(withJSONObject: ["error": errorMessage])
            return jsonResponse(data: errorBody, status: statusCode)
        } catch {
            logRESTCall(method: "POST", path: "/workflows/generate", statusCode: 500,
                        resultSummary: "Unexpected error: \(error.localizedDescription)")
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }

        let created = await workflowStorageService.createWorkflow(workflow)

        let responseBody = try JSONSerialization.data(withJSONObject: [
            "id": created.id.uuidString,
            "name": created.name,
            "description": created.description ?? ""
        ])
        logRESTCall(method: "POST", path: "/workflows/generate", statusCode: 201,
                    resultSummary: "Generated: \(created.name)",
                    req: req)

        return jsonResponse(data: responseBody, status: .created)
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
                             resultSummary: String, req: Request? = nil) {
        Task {
            var detailedReq: String?
            if storage.readDetailedLogsEnabled(), let req {
                let clientIP = req.headers.first(name: "X-Forwarded-For") ?? req.remoteAddress?.ipAddress ?? "unknown"
                let userAgent = req.headers.first(name: .userAgent) ?? "unknown"
                let contentType = req.headers.first(name: .contentType) ?? "-"
                let query = req.url.query.map { "?\($0)" } ?? ""
                detailedReq = """
                Client: \(clientIP)
                User-Agent: \(userAgent)
                Content-Type: \(contentType)
                URL: \(method) \(path)\(query)
                """
            }
            let entry = StateChangeLog.restCall(
                method: "\(method) \(path)",
                summary: "\(method) \(path)",
                result: "\(statusCode) \(resultSummary)",
                detailedRequest: detailedReq
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
}

// MARK: - Bearer Auth Middleware

/// Vapor middleware that validates `Authorization: Bearer <token>` on every request.
/// Accepts any token present in the `validTokens` set (multi-client support).
private struct BearerAuthMiddleware: AsyncMiddleware {
    let validTokens: Set<String>

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let authHeader = request.headers.first(name: .authorization) else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Missing Authorization header\"}"))
        }

        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Invalid Authorization scheme. Use Bearer.\"}"))
        }

        let token = String(authHeader.dropFirst(prefix.count))
        guard validTokens.contains(token) else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Invalid API token\"}"))
        }

        return try await next.respond(to: request)
    }
}

// MARK: - Connection Tracker

/// Actor that manages SSE connections and Streamable HTTP sessions
/// with TTL-based expiration and idle timeout.
private actor ConnectionTracker {
    private var sseConnections: [UUID: any AsyncBodyStreamWriter] = [:]
    private var wsConnections: [UUID: WebSocket] = [:]

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
