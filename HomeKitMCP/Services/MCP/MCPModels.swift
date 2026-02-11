import Foundation

// MARK: - JSON-RPC 2.0 Base Types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodable?

    init(method: String, id: JSONRPCId? = nil, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: AnyCodable?
    let error: JSONRPCError?

    static func success(id: JSONRPCId?, result: AnyCodable) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil)
    }

    static func error(id: JSONRPCId?, code: Int, message: String, data: AnyCodable? = nil) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCError(code: code, message: message, data: data))
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

/// JSON-RPC id can be a string or integer.
enum JSONRPCId: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ID must be string or integer")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        }
    }
}

// MARK: - MCP Protocol Constants

enum MCPConstants {
    static let protocolVersion = "2024-11-05"
    static let serverName = "HomeKitMCP"
    static let serverVersion = "1.0.0"
}

// MARK: - MCP Error Codes

enum MCPErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}
