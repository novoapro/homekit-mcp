import Foundation
import Vapor
import NIOCore
import Combine

class MCPServer: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var lastError: String?

    private var app: Application?
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let port: Int
    private let handler: MCPRequestHandler
    private let connectionTracker = ConnectionTracker()

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

    init(homeKitManager: HomeKitManager, loggingService: LoggingService, configService: DeviceConfigurationService, port: Int = 3000) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.port = port
        self.handler = MCPRequestHandler(homeKitManager: homeKitManager, loggingService: loggingService, configService: configService)
    }

    func start() throws {
        // Stop any existing instance first
        if app != nil {
            stopSync()
        }

        let env = Environment(name: "production", arguments: ["serve"])

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let app = try await Application.make(env)
                app.http.server.configuration.hostname = "0.0.0.0"
                app.http.server.configuration.port = self.port
                app.http.server.configuration.reuseAddress = true
                app.logger.logLevel = .warning

                self.configureRoutes(app)
                self.app = app

                do {
                    try await app.startup()
                } catch {
                    let message = "MCP Server failed to start on port \(self.port): \(error.localizedDescription)"
                    AppLogger.server.error("\(message)")
                    self.logServerError(message)
                    await MainActor.run {
                        self.isRunning = false
                        self.lastError = message
                    }
                }
            } catch {
                let message = "MCP Server failed to initialize Application: \(error.localizedDescription)"
                AppLogger.server.error("\(message)")
                self.logServerError(message)
                await MainActor.run {
                    self.isRunning = false
                    self.lastError = message
                }
            }
        }

        // Give Vapor a moment to bind, then verify
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let running = self.app != nil
            DispatchQueue.main.async {
                self.isRunning = running
                if running {
                    self.lastError = nil
                }
            }
        }
    }

    func stop() {
        stopSync()
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }

    private func stopSync() {
        Task { await connectionTracker.removeAll() }
        app?.shutdown()
        app = nil
    }

    // MARK: - Route Configuration

    private func configureRoutes(_ app: Application) {
        // Streamable HTTP transport: single endpoint supporting POST, GET, and DELETE
        app.on(.POST, "mcp", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return try await self.handleStreamablePost(req)
        }

        app.on(.GET, "mcp") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return self.handleStreamableGet(req)
        }

        app.on(.DELETE, "mcp") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return await self.handleStreamableDelete(req)
        }

        // Legacy SSE transport (2024-11-05): separate /sse and /messages endpoints
        app.on(.GET, "sse") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return self.handleLegacySSE(req)
        }

        app.on(.POST, "messages", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return try await self.handleLegacyMessages(req)
        }

        // REST Endpoints
        app.on(.GET, "devices") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return try await self.handleRestGetDevices(req)
        }
        
        app.on(.GET, "devices", ":deviceId") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return try await self.handleRestGetDevice(req)
        }

        // Health check
        app.on(.GET, "health") { _ -> String in
            return "ok"
        }
    }
    
    // MARK: - REST Handlers
    
    private func handleRestGetDevices(_ req: Request) async throws -> Response {
        let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
        let filteredDevices = await handler.filterDevicesByConfig(allDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }
        
        let data = try Self.encoder.encode(restDevices)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }
    
    private func handleRestGetDevice(_ req: Request) async throws -> Response {
        guard let deviceId = req.parameters.get("deviceId") else {
            throw Abort(.badRequest)
        }
        
        let device = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        
        guard let device else {
            throw Abort(.notFound, reason: "Device not found")
        }
        
        let filtered = await handler.filterDevicesByConfig([device])
        
        guard let filteredDevice = filtered.first else {
             throw Abort(.notFound, reason: "Device not found or not exposed")
        }
        
        let restDevice = RESTDevice.from(filteredDevice)
        let data = try Self.encoder.encode(restDevice)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
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
            if let batchRequests = try? Self.decoder.decode([JSONRPCRequest].self, from: data) {
                requests = batchRequests
                isBatch = true
            } else {
                let single = try Self.decoder.decode(JSONRPCRequest.self, from: data)
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
            jsonrpcRequest = try Self.decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            throw Abort(.badRequest, reason: "Invalid JSON-RPC request")
        }

        // Handle notifications — return 202
        if jsonrpcRequest.id == nil {
            return Response(status: .accepted)
        }

        let jsonrpcResponse = await handler.handle(jsonrpcRequest)

        // Send response on the SSE stream
        let responseData = try Self.encoder.encode(jsonrpcResponse)
        if let responseString = String(data: responseData, encoding: .utf8) {
            let sseEvent = "event: message\ndata: \(responseString)\n\n"
            try? await writer.writeBuffer(ByteBuffer(string: sseEvent))
        }

        return Response(status: .accepted)
    }

    // MARK: - Helpers

    private func encodeJSONResponse(_ response: JSONRPCResponse) throws -> Response {
        let data = try Self.encoder.encode(response)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }

    private func encodeBatchJSONResponse(_ responses: [JSONRPCResponse]) throws -> Response {
        let data = try Self.encoder.encode(responses)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }

    private func updateClientCount() {
        Task {
            let count = await connectionTracker.sseConnectionCount
            await MainActor.run { [weak self] in
                self?.connectedClients = count
            }
        }
    }

    private func logServerError(_ message: String) {
        Task {
            let entry = StateChangeLog(
                id: UUID(),
                timestamp: Date(),
                deviceId: "system",
                deviceName: "MCP Server",
                characteristicType: "server",
                oldValue: nil,
                newValue: nil,
                category: .serverError,
                errorDetails: message
            )
            await loggingService.logEntry(entry)
        }
    }
}

// MARK: - Connection Tracker

/// Actor that manages SSE connections and Streamable HTTP sessions,
/// replacing the previous @unchecked Sendable + NSLock pattern.
private actor ConnectionTracker {
    private var sseConnections: [UUID: any AsyncBodyStreamWriter] = [:]
    private var activeSessions: Set<String> = []

    var sseConnectionCount: Int { sseConnections.count }

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

    // MARK: - Streamable HTTP Sessions

    func hasSession(_ sessionId: String) -> Bool {
        activeSessions.contains(sessionId)
    }

    func hasAnySessions() -> Bool {
        !activeSessions.isEmpty
    }

    func addSession(_ sessionId: String) {
        activeSessions.insert(sessionId)
    }

    func removeSession(_ sessionId: String) -> Bool {
        activeSessions.remove(sessionId) != nil
    }

    func removeAll() {
        sseConnections.removeAll()
        activeSessions.removeAll()
    }
}
