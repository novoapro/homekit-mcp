import Foundation
import Vapor
import NIOCore
import Combine

class MCPServer: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0

    private var app: Application?
    private let homeKitManager: HomeKitManager
    private let port: Int
    private let handler: MCPRequestHandler

    /// Active SSE connections for the legacy transport.
    private var sseConnections: [UUID: SSEConnection] = [:]
    private let lock = NSLock()

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

    init(homeKitManager: HomeKitManager, loggingService: LoggingService = LoggingService(), port: Int = 3000) {
        self.homeKitManager = homeKitManager
        self.port = port
        self.handler = MCPRequestHandler(homeKitManager: homeKitManager, loggingService: loggingService)
    }

    func start() throws {
        let env = Environment(name: "production", arguments: ["serve"])
        let app = Application(env)
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = port
        app.logger.logLevel = .warning

        configureRoutes(app)
        self.app = app

        isRunning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try app.start()
            } catch {
                print("MCP Server failed to start: \(error)")
                DispatchQueue.main.async {
                    self?.isRunning = false
                }
            }
        }
    }

    func stop() {
        app?.shutdown()
        app = nil
        lock.lock()
        sseConnections.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }

    // MARK: - Route Configuration

    private func configureRoutes(_ app: Application) {
        // Streamable HTTP transport: single endpoint supporting POST and GET
        app.on(.POST, "mcp", body: .collect(maxSize: "1mb")) { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return try await self.handleStreamablePost(req)
        }

        app.on(.GET, "mcp") { [weak self] req async throws -> Response in
            guard let self else { throw Abort(.serviceUnavailable) }
            return self.handleStreamableGet(req)
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

        // Health check
        app.on(.GET, "health") { _ -> String in
            return "ok"
        }
    }

    // MARK: - Streamable HTTP Transport

    private func handleStreamablePost(_ req: Request) async throws -> Response {
        guard let body = req.body.data,
              let data = body.getData(at: body.readerIndex, length: body.readableBytes) else {
            throw Abort(.badRequest)
        }

        let jsonrpcRequest: JSONRPCRequest
        do {
            jsonrpcRequest = try Self.decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            let errorResponse = JSONRPCResponse.error(
                id: nil,
                code: MCPErrorCode.parseError,
                message: "Failed to parse JSON-RPC request"
            )
            return try encodeJSONResponse(errorResponse)
        }

        // Handle notifications (no id) — return 202 Accepted
        if jsonrpcRequest.id == nil && jsonrpcRequest.method == "notifications/initialized" {
            return Response(status: .accepted)
        }

        let response = await handler.handle(jsonrpcRequest)
        return try encodeJSONResponse(response)
    }

    private func handleStreamableGet(_ req: Request) -> Response {
        return Response(status: .methodNotAllowed)
    }

    // MARK: - Legacy SSE Transport (2024-11-05)

    private func handleLegacySSE(_ req: Request) -> Response {
        let connectionId = UUID()
        let connection = SSEConnection(id: connectionId)

        lock.lock()
        sseConnections[connectionId] = connection
        lock.unlock()
        updateClientCount()

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
                // Send the endpoint event first
                let endpointEvent = "event: endpoint\ndata: \(messagesURL)\n\n"
                try await writer.writeBuffer(ByteBuffer(string: endpointEvent))

                // Store writer so message handler can send responses on this stream
                connection.writer = writer

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
                self?.lock.lock()
                self?.sseConnections.removeValue(forKey: connectionId)
                self?.lock.unlock()
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

        lock.lock()
        let connection = sseConnections[sessionId]
        lock.unlock()

        guard let connection else {
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
        if let writer = connection.writer {
            let responseData = try Self.encoder.encode(jsonrpcResponse)
            if let responseString = String(data: responseData, encoding: .utf8) {
                let sseEvent = "event: message\ndata: \(responseString)\n\n"
                try? await writer.writeBuffer(ByteBuffer(string: sseEvent))
            }
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

    private func updateClientCount() {
        lock.lock()
        let count = sseConnections.count
        lock.unlock()
        DispatchQueue.main.async {
            self.connectedClients = count
        }
    }
}

// MARK: - SSE Connection

private final class SSEConnection: @unchecked Sendable {
    let id: UUID
    var writer: (any AsyncBodyStreamWriter)?

    init(id: UUID) {
        self.id = id
    }
}
