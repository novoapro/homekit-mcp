import Foundation

// MARK: - Log Category

enum LogCategory: String, Codable {
    case stateChange = "state_change"
    case webhookError = "webhook_error"
    case webhookCall = "webhook_call"
    case serverError = "server_error"
    case mcpCall = "mcp_call"
    case restCall = "rest_call"
    case automationExecution = "automation_execution"
    case automationError = "automation_error"
    case sceneExecution = "scene_execution"
    case sceneError = "scene_error"
    case backupRestore = "backup_restore"
    case aiInteraction = "ai_interaction"
    case aiInteractionError = "ai_interaction_error"
}

// MARK: - Payload Types

struct DeviceStatePayload: Codable {
    let deviceId: String
    let deviceName: String
    let roomName: String?
    let serviceId: String?
    let serviceName: String?
    let characteristicType: String
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
    let unit: String?
}

struct WebhookLogPayload: Codable {
    let deviceId: String
    let deviceName: String
    let roomName: String?
    let serviceId: String?
    let serviceName: String?
    let characteristicType: String
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
    let unit: String?
    let summary: String
    let result: String
    let errorDetails: String?
    let detailedRequest: String?
}

struct APICallPayload: Codable {
    let method: String
    let summary: String
    let result: String
    let detailedRequest: String?
    let detailedResponse: String?
}

struct ServerErrorPayload: Codable {
    let errorDetails: String
}

struct ScenePayload: Codable {
    let sceneId: String
    let sceneName: String
    let succeeded: Bool
    let summary: String?
    let errorDetails: String?
}

struct BackupRestorePayload: Codable {
    let subtype: String
    let summary: String
}

struct AIInteractionPayload: Codable, Hashable {
    let provider: String
    let model: String
    let operation: String
    let systemPrompt: String
    let userMessage: String
    let rawResponse: String?
    let parsedSuccessfully: Bool
    let errorMessage: String?
    let durationSeconds: Double
}

// MARK: - Log Payload Enum

enum LogPayload {
    case stateChange(DeviceStatePayload)
    case webhookCall(WebhookLogPayload)
    case webhookError(WebhookLogPayload)
    case mcpCall(APICallPayload)
    case restCall(APICallPayload)
    case serverError(ServerErrorPayload)
    /// Automation execution (success/skipped/conditionNotMet). Full execution data is embedded.
    case automationExecution(AutomationExecutionLog)
    /// Automation execution that failed or was cancelled. Full execution data is embedded.
    case automationError(AutomationExecutionLog)
    case sceneExecution(ScenePayload)
    case sceneError(ScenePayload)
    case backupRestore(BackupRestorePayload)
    case aiInteraction(AIInteractionPayload)
    case aiInteractionError(AIInteractionPayload)
}

// MARK: - StateChangeLog

struct StateChangeLog: Identifiable {
    let id: UUID
    let timestamp: Date
    let category: LogCategory
    let payload: LogPayload
}

// MARK: - Factory Methods

extension StateChangeLog {
    static func stateChange(
        deviceId: String,
        deviceName: String,
        roomName: String? = nil,
        serviceId: String? = nil,
        serviceName: String? = nil,
        characteristicType: String,
        oldValue: AnyCodable? = nil,
        newValue: AnyCodable? = nil,
        unit: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .stateChange,
            payload: .stateChange(DeviceStatePayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue,
                unit: unit
            ))
        )
    }

    static func webhookCall(
        deviceId: String,
        deviceName: String,
        roomName: String? = nil,
        serviceId: String? = nil,
        serviceName: String? = nil,
        characteristicType: String,
        oldValue: AnyCodable? = nil,
        newValue: AnyCodable? = nil,
        unit: String? = nil,
        summary: String,
        result: String,
        detailedRequest: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .webhookCall,
            payload: .webhookCall(WebhookLogPayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue,
                unit: unit,
                summary: summary, result: result,
                errorDetails: nil, detailedRequest: detailedRequest
            ))
        )
    }

    static func webhookError(
        deviceId: String,
        deviceName: String,
        roomName: String? = nil,
        serviceId: String? = nil,
        serviceName: String? = nil,
        characteristicType: String,
        oldValue: AnyCodable? = nil,
        newValue: AnyCodable? = nil,
        unit: String? = nil,
        summary: String,
        result: String,
        errorDetails: String,
        detailedRequest: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .webhookError,
            payload: .webhookError(WebhookLogPayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue,
                unit: unit,
                summary: summary, result: result,
                errorDetails: errorDetails, detailedRequest: detailedRequest
            ))
        )
    }

    static func mcpCall(
        method: String,
        summary: String,
        result: String,
        detailedRequest: String? = nil,
        detailedResponse: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .mcpCall,
            payload: .mcpCall(APICallPayload(
                method: method, summary: summary,
                result: result, detailedRequest: detailedRequest,
                detailedResponse: detailedResponse
            ))
        )
    }

    static func restCall(
        method: String,
        summary: String,
        result: String,
        detailedRequest: String? = nil,
        detailedResponse: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .restCall,
            payload: .restCall(APICallPayload(
                method: method, summary: summary,
                result: result, detailedRequest: detailedRequest,
                detailedResponse: detailedResponse
            ))
        )
    }

    static func serverError(errorDetails: String) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .serverError,
            payload: .serverError(ServerErrorPayload(errorDetails: errorDetails))
        )
    }

    static func sceneExecution(
        sceneId: String,
        sceneName: String,
        summary: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .sceneExecution,
            payload: .sceneExecution(ScenePayload(
                sceneId: sceneId, sceneName: sceneName,
                succeeded: true, summary: summary, errorDetails: nil
            ))
        )
    }

    static func sceneError(
        sceneId: String,
        sceneName: String,
        errorDetails: String,
        summary: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .sceneError,
            payload: .sceneError(ScenePayload(
                sceneId: sceneId, sceneName: sceneName,
                succeeded: false, summary: summary, errorDetails: errorDetails
            ))
        )
    }

    static func backupRestore(
        subtype: String,
        summary: String
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .backupRestore,
            payload: .backupRestore(BackupRestorePayload(
                subtype: subtype, summary: summary
            ))
        )
    }

    static func aiInteraction(
        provider: String,
        model: String,
        operation: String,
        systemPrompt: String,
        userMessage: String,
        rawResponse: String?,
        parsedSuccessfully: Bool,
        errorMessage: String?,
        durationSeconds: Double
    ) -> StateChangeLog {
        let p = AIInteractionPayload(
            provider: provider, model: model, operation: operation,
            systemPrompt: systemPrompt, userMessage: userMessage,
            rawResponse: rawResponse, parsedSuccessfully: parsedSuccessfully,
            errorMessage: errorMessage, durationSeconds: durationSeconds
        )
        let category: LogCategory = (errorMessage != nil && !parsedSuccessfully) ? .aiInteractionError : .aiInteraction
        return StateChangeLog(
            id: UUID(), timestamp: Date(), category: category,
            payload: category == .aiInteractionError ? .aiInteractionError(p) : .aiInteraction(p)
        )
    }
}

// MARK: - Convenience Accessors (used by native UI and MCP text formatter; NOT serialized)

extension StateChangeLog {
    var deviceId: String {
        switch payload {
        case .stateChange(let p): return p.deviceId
        case .webhookCall(let p): return p.deviceId
        case .webhookError(let p): return p.deviceId
        case .mcpCall: return "mcp-rpc"
        case .restCall: return "mcp"
        case .serverError: return "system"
        case .automationExecution(let e): return e.automationId.uuidString
        case .automationError(let e): return e.automationId.uuidString
        case .sceneExecution(let p): return p.sceneId
        case .sceneError(let p): return p.sceneId
        case .backupRestore: return "backup-restore"
        case .aiInteraction(let p): return "ai-\(p.provider)"
        case .aiInteractionError(let p): return "ai-\(p.provider)"
        }
    }

    var deviceName: String {
        switch payload {
        case .stateChange(let p): return p.deviceName
        case .webhookCall(let p): return p.deviceName
        case .webhookError(let p): return p.deviceName
        case .mcpCall: return "MCP"
        case .restCall: return "MCP Server"
        case .serverError: return "MCP Server"
        case .automationExecution(let e): return e.automationName
        case .automationError(let e): return e.automationName
        case .sceneExecution(let p): return p.sceneName
        case .sceneError(let p): return p.sceneName
        case .backupRestore: return "Backup Restore"
        case .aiInteraction(let p): return "AI (\(p.model))"
        case .aiInteractionError(let p): return "AI (\(p.model))"
        }
    }

    var serviceId: String? {
        switch payload {
        case .stateChange(let p): return p.serviceId
        case .webhookCall(let p): return p.serviceId
        case .webhookError(let p): return p.serviceId
        default: return nil
        }
    }

    var serviceName: String? {
        switch payload {
        case .stateChange(let p): return p.serviceName
        case .webhookCall(let p): return p.serviceName
        case .webhookError(let p): return p.serviceName
        default: return nil
        }
    }

    var roomName: String? {
        switch payload {
        case .stateChange(let p): return p.roomName
        case .webhookCall(let p): return p.roomName
        case .webhookError(let p): return p.roomName
        default: return nil
        }
    }

    var characteristicType: String {
        switch payload {
        case .stateChange(let p): return p.characteristicType
        case .webhookCall(let p): return p.characteristicType
        case .webhookError(let p): return p.characteristicType
        case .mcpCall(let p): return p.method
        case .restCall(let p): return p.method
        case .serverError: return "server"
        case .automationExecution: return "automation-execution"
        case .automationError: return "automation-error"
        case .sceneExecution: return "scene_execution"
        case .sceneError: return "scene_execution"
        case .backupRestore(let p): return p.subtype
        case .aiInteraction(let p): return p.operation
        case .aiInteractionError(let p): return p.operation
        }
    }

    var oldValue: AnyCodable? {
        switch payload {
        case .stateChange(let p): return p.oldValue
        case .webhookCall(let p): return p.oldValue
        case .webhookError(let p): return p.oldValue
        default: return nil
        }
    }

    var newValue: AnyCodable? {
        switch payload {
        case .stateChange(let p): return p.newValue
        case .webhookCall(let p): return p.newValue
        case .webhookError(let p): return p.newValue
        default: return nil
        }
    }

    var errorDetails: String? {
        switch payload {
        case .webhookError(let p): return p.errorDetails
        case .serverError(let p): return p.errorDetails
        case .automationExecution(let e): return e.errorMessage
        case .automationError(let e): return e.errorMessage
        case .sceneError(let p): return p.errorDetails
        case .backupRestore(let p): return p.summary
        case .aiInteractionError(let p): return p.errorMessage
        default: return nil
        }
    }

    var requestBody: String? {
        switch payload {
        case .webhookCall(let p): return p.summary
        case .webhookError(let p): return p.summary
        case .mcpCall(let p): return p.summary
        case .restCall(let p): return p.summary
        case .automationExecution(let e): return e.triggerEvent?.triggerDescription
        case .automationError(let e): return e.triggerEvent?.triggerDescription
        case .sceneExecution(let p): return p.summary
        case .sceneError(let p): return p.summary
        case .aiInteraction(let p): return String(p.userMessage.prefix(200))
        case .aiInteractionError(let p): return String(p.userMessage.prefix(200))
        default: return nil
        }
    }

    var responseBody: String? {
        switch payload {
        case .webhookCall(let p): return p.result
        case .webhookError(let p): return p.result
        case .mcpCall(let p): return p.result
        case .restCall(let p): return p.result
        case .sceneError(let p): return p.errorDetails
        case .aiInteraction(let p): return p.rawResponse
        case .aiInteractionError(let p): return p.rawResponse
        default: return nil
        }
    }

    var detailedRequestBody: String? {
        switch payload {
        case .webhookCall(let p): return p.detailedRequest
        case .webhookError(let p): return p.detailedRequest
        case .mcpCall(let p): return p.detailedRequest
        case .restCall(let p): return p.detailedRequest
        default: return nil
        }
    }

    var detailedResponseBody: String? {
        switch payload {
        case .mcpCall(let p): return p.detailedResponse
        case .restCall(let p): return p.detailedResponse
        default: return nil
        }
    }

    /// The full automation execution log; non-nil for `.automationExecution` and `.automationError` entries.
    var automationExecution: AutomationExecutionLog? {
        switch payload {
        case .automationExecution(let e): return e
        case .automationError(let e): return e
        default: return nil
        }
    }

    /// The AI interaction payload; non-nil for `.aiInteraction` and `.aiInteractionError` entries.
    var aiInteraction: AIInteractionPayload? {
        switch payload {
        case .aiInteraction(let p): return p
        case .aiInteractionError(let p): return p
        default: return nil
        }
    }
}

// MARK: - Truncation

extension StateChangeLog {
    private static let maxFieldLength = 10_000

    func truncatingLargeFields() -> StateChangeLog {
        let truncatedPayload: LogPayload
        switch payload {
        case .stateChange:
            truncatedPayload = payload
        case .webhookCall(var p):
            p = WebhookLogPayload(
                deviceId: p.deviceId, deviceName: p.deviceName,
                roomName: p.roomName,
                serviceId: p.serviceId, serviceName: p.serviceName,
                characteristicType: p.characteristicType,
                oldValue: p.oldValue, newValue: p.newValue,
                unit: p.unit,
                summary: p.summary, result: p.result,
                errorDetails: p.errorDetails.map { Self.truncate($0) },
                detailedRequest: p.detailedRequest.map { Self.truncate($0) }
            )
            truncatedPayload = .webhookCall(p)
        case .webhookError(var p):
            p = WebhookLogPayload(
                deviceId: p.deviceId, deviceName: p.deviceName,
                roomName: p.roomName,
                serviceId: p.serviceId, serviceName: p.serviceName,
                characteristicType: p.characteristicType,
                oldValue: p.oldValue, newValue: p.newValue,
                unit: p.unit,
                summary: p.summary, result: p.result,
                errorDetails: p.errorDetails.map { Self.truncate($0) },
                detailedRequest: p.detailedRequest.map { Self.truncate($0) }
            )
            truncatedPayload = .webhookError(p)
        case .mcpCall(let p):
            truncatedPayload = .mcpCall(APICallPayload(
                method: p.method, summary: p.summary, result: p.result,
                detailedRequest: p.detailedRequest.map { Self.truncate($0) },
                detailedResponse: p.detailedResponse.map { Self.truncate($0) }
            ))
        case .restCall(let p):
            truncatedPayload = .restCall(APICallPayload(
                method: p.method, summary: p.summary, result: p.result,
                detailedRequest: p.detailedRequest.map { Self.truncate($0) },
                detailedResponse: p.detailedResponse.map { Self.truncate($0) }
            ))
        case .serverError(let p):
            truncatedPayload = .serverError(ServerErrorPayload(
                errorDetails: Self.truncate(p.errorDetails)
            ))
        case .automationExecution, .automationError:
            // AutomationExecutionLog has its own field-level truncation; pass through.
            truncatedPayload = payload
        case .sceneExecution:
            truncatedPayload = payload
        case .sceneError(let p):
            truncatedPayload = .sceneError(ScenePayload(
                sceneId: p.sceneId, sceneName: p.sceneName,
                succeeded: p.succeeded, summary: p.summary,
                errorDetails: p.errorDetails.map { Self.truncate($0) }
            ))
        case .backupRestore(let p):
            truncatedPayload = .backupRestore(BackupRestorePayload(
                subtype: p.subtype, summary: Self.truncate(p.summary)
            ))
        case .aiInteraction(let p):
            truncatedPayload = .aiInteraction(AIInteractionPayload(
                provider: p.provider, model: p.model, operation: p.operation,
                systemPrompt: Self.truncate(p.systemPrompt),
                userMessage: Self.truncate(p.userMessage),
                rawResponse: p.rawResponse.map { Self.truncate($0) },
                parsedSuccessfully: p.parsedSuccessfully,
                errorMessage: p.errorMessage.map { Self.truncate($0) },
                durationSeconds: p.durationSeconds
            ))
        case .aiInteractionError(let p):
            truncatedPayload = .aiInteractionError(AIInteractionPayload(
                provider: p.provider, model: p.model, operation: p.operation,
                systemPrompt: Self.truncate(p.systemPrompt),
                userMessage: Self.truncate(p.userMessage),
                rawResponse: p.rawResponse.map { Self.truncate($0) },
                parsedSuccessfully: p.parsedSuccessfully,
                errorMessage: p.errorMessage.map { Self.truncate($0) },
                durationSeconds: p.durationSeconds
            ))
        }
        return StateChangeLog(id: id, timestamp: timestamp, category: category, payload: truncatedPayload)
    }

    private static func truncate(_ s: String) -> String {
        guard s.count > maxFieldLength else { return s }
        return String(s.prefix(maxFieldLength)) + "… [truncated]"
    }
}


// MARK: - Codable (polymorphic: each category encodes only its relevant fields)

extension StateChangeLog: Codable {
    private enum CodingKeys: String, CodingKey {
        // Common
        case id, timestamp, category
        // Device-related (stateChange, webhook)
        case deviceId, deviceName, roomName, serviceId, serviceName
        case characteristicType, oldValue, newValue, unit
        // API calls (mcpCall, restCall)
        case method, summary, result, detailedRequest, detailedResponse
        // Errors
        case errorDetails
        // Scenes
        case sceneId, sceneName, succeeded
        // Backup
        case subtype
        // Rich payloads
        case automationExecution
        case aiInteractionPayload
        // Legacy keys (read-only, for backwards compatibility)
        case requestBody, responseBody, detailedRequestBody, detailedResponseBody
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(category, forKey: .category)

        switch payload {
        case .stateChange(let p):
            try c.encode(p.deviceId, forKey: .deviceId)
            try c.encode(p.deviceName, forKey: .deviceName)
            try c.encodeIfPresent(p.roomName, forKey: .roomName)
            try c.encodeIfPresent(p.serviceId, forKey: .serviceId)
            try c.encodeIfPresent(p.serviceName, forKey: .serviceName)
            try c.encode(p.characteristicType, forKey: .characteristicType)
            try c.encodeIfPresent(p.oldValue, forKey: .oldValue)
            try c.encodeIfPresent(p.newValue, forKey: .newValue)
            try c.encodeIfPresent(p.unit, forKey: .unit)

        case .webhookCall(let p), .webhookError(let p):
            try c.encode(p.deviceId, forKey: .deviceId)
            try c.encode(p.deviceName, forKey: .deviceName)
            try c.encodeIfPresent(p.roomName, forKey: .roomName)
            try c.encodeIfPresent(p.serviceId, forKey: .serviceId)
            try c.encodeIfPresent(p.serviceName, forKey: .serviceName)
            try c.encode(p.characteristicType, forKey: .characteristicType)
            try c.encodeIfPresent(p.oldValue, forKey: .oldValue)
            try c.encodeIfPresent(p.newValue, forKey: .newValue)
            try c.encodeIfPresent(p.unit, forKey: .unit)
            try c.encode(p.summary, forKey: .summary)
            try c.encode(p.result, forKey: .result)
            try c.encodeIfPresent(p.errorDetails, forKey: .errorDetails)
            try c.encodeIfPresent(p.detailedRequest, forKey: .detailedRequest)

        case .mcpCall(let p), .restCall(let p):
            try c.encode(p.method, forKey: .method)
            try c.encode(p.summary, forKey: .summary)
            try c.encode(p.result, forKey: .result)
            try c.encodeIfPresent(p.detailedRequest, forKey: .detailedRequest)
            try c.encodeIfPresent(p.detailedResponse, forKey: .detailedResponse)

        case .serverError(let p):
            try c.encode(p.errorDetails, forKey: .errorDetails)

        case .automationExecution(let e), .automationError(let e):
            try c.encode(e, forKey: .automationExecution)

        case .sceneExecution(let p), .sceneError(let p):
            try c.encode(p.sceneId, forKey: .sceneId)
            try c.encode(p.sceneName, forKey: .sceneName)
            try c.encode(p.succeeded, forKey: .succeeded)
            try c.encodeIfPresent(p.summary, forKey: .summary)
            try c.encodeIfPresent(p.errorDetails, forKey: .errorDetails)

        case .backupRestore(let p):
            try c.encode(p.subtype, forKey: .subtype)
            try c.encode(p.summary, forKey: .summary)

        case .aiInteraction(let p), .aiInteractionError(let p):
            try c.encode(p, forKey: .aiInteractionPayload)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        category = try c.decode(LogCategory.self, forKey: .category)

        switch category {
        case .stateChange:
            payload = .stateChange(DeviceStatePayload(
                deviceId: try c.decodeIfPresent(String.self, forKey: .deviceId) ?? "",
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName) ?? "",
                roomName: try c.decodeIfPresent(String.self, forKey: .roomName),
                serviceId: try c.decodeIfPresent(String.self, forKey: .serviceId),
                serviceName: try c.decodeIfPresent(String.self, forKey: .serviceName),
                characteristicType: try c.decodeIfPresent(String.self, forKey: .characteristicType) ?? "",
                oldValue: try c.decodeIfPresent(AnyCodable.self, forKey: .oldValue),
                newValue: try c.decodeIfPresent(AnyCodable.self, forKey: .newValue),
                unit: try c.decodeIfPresent(String.self, forKey: .unit)
            ))

        case .webhookCall, .webhookError:
            // New format uses summary/result; legacy uses requestBody/responseBody
            let summary = try c.decodeIfPresent(String.self, forKey: .summary)
                ?? c.decodeIfPresent(String.self, forKey: .requestBody) ?? ""
            let result = try c.decodeIfPresent(String.self, forKey: .result)
                ?? c.decodeIfPresent(String.self, forKey: .responseBody) ?? ""
            let detailedReq = try c.decodeIfPresent(String.self, forKey: .detailedRequest)
                ?? c.decodeIfPresent(String.self, forKey: .detailedRequestBody)
            let p = WebhookLogPayload(
                deviceId: try c.decodeIfPresent(String.self, forKey: .deviceId) ?? "",
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName) ?? "",
                roomName: try c.decodeIfPresent(String.self, forKey: .roomName),
                serviceId: try c.decodeIfPresent(String.self, forKey: .serviceId),
                serviceName: try c.decodeIfPresent(String.self, forKey: .serviceName),
                characteristicType: try c.decodeIfPresent(String.self, forKey: .characteristicType) ?? "",
                oldValue: try c.decodeIfPresent(AnyCodable.self, forKey: .oldValue),
                newValue: try c.decodeIfPresent(AnyCodable.self, forKey: .newValue),
                unit: try c.decodeIfPresent(String.self, forKey: .unit),
                summary: summary, result: result,
                errorDetails: try c.decodeIfPresent(String.self, forKey: .errorDetails),
                detailedRequest: detailedReq
            )
            payload = category == .webhookError ? .webhookError(p) : .webhookCall(p)

        case .mcpCall, .restCall:
            // New format uses method; legacy uses characteristicType
            let method = try c.decodeIfPresent(String.self, forKey: .method)
                ?? c.decodeIfPresent(String.self, forKey: .characteristicType) ?? ""
            let summary = try c.decodeIfPresent(String.self, forKey: .summary)
                ?? c.decodeIfPresent(String.self, forKey: .requestBody) ?? ""
            let result = try c.decodeIfPresent(String.self, forKey: .result)
                ?? c.decodeIfPresent(String.self, forKey: .responseBody) ?? ""
            let detailedReq = try c.decodeIfPresent(String.self, forKey: .detailedRequest)
                ?? c.decodeIfPresent(String.self, forKey: .detailedRequestBody)
            let detailedResp = try c.decodeIfPresent(String.self, forKey: .detailedResponse)
                ?? c.decodeIfPresent(String.self, forKey: .detailedResponseBody)
            let p = APICallPayload(
                method: method, summary: summary, result: result,
                detailedRequest: detailedReq, detailedResponse: detailedResp
            )
            payload = category == .mcpCall ? .mcpCall(p) : .restCall(p)

        case .serverError:
            payload = .serverError(ServerErrorPayload(
                errorDetails: try c.decodeIfPresent(String.self, forKey: .errorDetails) ?? ""
            ))

        case .automationExecution, .automationError:
            if let execLog = try? c.decode(AutomationExecutionLog.self, forKey: .automationExecution) {
                payload = category == .automationError ? .automationError(execLog) : .automationExecution(execLog)
            } else {
                let err = try c.decodeIfPresent(String.self, forKey: .errorDetails) ?? "legacy automation log"
                payload = .serverError(ServerErrorPayload(errorDetails: err))
            }

        case .sceneExecution, .sceneError:
            // New format uses sceneId/sceneName; legacy uses deviceId/deviceName
            let sceneId = try c.decodeIfPresent(String.self, forKey: .sceneId)
                ?? c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
            let sceneName = try c.decodeIfPresent(String.self, forKey: .sceneName)
                ?? c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
            let succeeded: Bool
            if let s = try? c.decodeIfPresent(Bool.self, forKey: .succeeded) {
                succeeded = s
            } else {
                // Legacy: succeeded was stored as newValue bool
                let nv = try c.decodeIfPresent(AnyCodable.self, forKey: .newValue)
                succeeded = (nv?.value as? Bool) ?? (category == .sceneExecution)
            }
            let summary = try c.decodeIfPresent(String.self, forKey: .summary)
                ?? c.decodeIfPresent(String.self, forKey: .requestBody)
            let p = ScenePayload(
                sceneId: sceneId, sceneName: sceneName,
                succeeded: succeeded, summary: summary,
                errorDetails: try c.decodeIfPresent(String.self, forKey: .errorDetails)
            )
            payload = category == .sceneError ? .sceneError(p) : .sceneExecution(p)

        case .backupRestore:
            // New format uses subtype/summary; legacy uses characteristicType/errorDetails
            let subtype = try c.decodeIfPresent(String.self, forKey: .subtype)
                ?? c.decodeIfPresent(String.self, forKey: .characteristicType) ?? ""
            let summary = try c.decodeIfPresent(String.self, forKey: .summary)
                ?? c.decodeIfPresent(String.self, forKey: .errorDetails) ?? ""
            payload = .backupRestore(BackupRestorePayload(subtype: subtype, summary: summary))

        case .aiInteraction:
            if let aiPayload = try? c.decode(AIInteractionPayload.self, forKey: .aiInteractionPayload) {
                payload = .aiInteraction(aiPayload)
            } else {
                let err = try c.decodeIfPresent(String.self, forKey: .errorDetails) ?? "legacy AI interaction log"
                payload = .serverError(ServerErrorPayload(errorDetails: err))
            }

        case .aiInteractionError:
            if let aiPayload = try? c.decode(AIInteractionPayload.self, forKey: .aiInteractionPayload) {
                payload = .aiInteractionError(aiPayload)
            } else {
                let err = try c.decodeIfPresent(String.self, forKey: .errorDetails) ?? "legacy AI interaction log"
                payload = .serverError(ServerErrorPayload(errorDetails: err))
            }
        }
    }
}

// MARK: - StateChange (runtime helper for device state changes)

struct StateChange {
    let deviceId: String
    let deviceName: String
    let roomName: String?
    let serviceId: String?
    let serviceName: String?
    let characteristicId: String?
    let characteristicType: String
    let oldValue: Any?
    let newValue: Any?
    let timestamp: Date

    init(deviceId: String, deviceName: String, roomName: String? = nil, serviceId: String? = nil, serviceName: String? = nil, characteristicId: String? = nil, characteristicType: String, oldValue: Any? = nil, newValue: Any? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.characteristicId = characteristicId
        self.characteristicType = characteristicType
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}
