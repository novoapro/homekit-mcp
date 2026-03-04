import Foundation

// MARK: - Log Category

enum LogCategory: String, Codable {
    case stateChange = "state_change"
    case webhookError = "webhook_error"
    case webhookCall = "webhook_call"
    case serverError = "server_error"
    case mcpCall = "mcp_call"
    case restCall = "rest_call"
    case workflowExecution = "workflow_execution"
    case workflowError = "workflow_error"
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
    /// Workflow execution (success/skipped/conditionNotMet). Full execution data is embedded.
    case workflowExecution(WorkflowExecutionLog)
    /// Workflow execution that failed or was cancelled. Full execution data is embedded.
    case workflowError(WorkflowExecutionLog)
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
        newValue: AnyCodable? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .stateChange,
            payload: .stateChange(DeviceStatePayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue
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
                summary: summary, result: result,
                errorDetails: errorDetails, detailedRequest: detailedRequest
            ))
        )
    }

    static func mcpCall(
        method: String,
        summary: String,
        result: String,
        detailedRequest: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .mcpCall,
            payload: .mcpCall(APICallPayload(
                method: method, summary: summary,
                result: result, detailedRequest: detailedRequest
            ))
        )
    }

    static func restCall(
        method: String,
        summary: String,
        result: String,
        detailedRequest: String? = nil
    ) -> StateChangeLog {
        StateChangeLog(
            id: UUID(), timestamp: Date(), category: .restCall,
            payload: .restCall(APICallPayload(
                method: method, summary: summary,
                result: result, detailedRequest: detailedRequest
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

// MARK: - Convenience Accessors

extension StateChangeLog {
    var deviceId: String {
        switch payload {
        case .stateChange(let p): return p.deviceId
        case .webhookCall(let p): return p.deviceId
        case .webhookError(let p): return p.deviceId
        case .mcpCall: return "mcp-rpc"
        case .restCall: return "mcp"
        case .serverError: return "system"
        case .workflowExecution(let e): return e.workflowId.uuidString
        case .workflowError(let e): return e.workflowId.uuidString
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
        case .workflowExecution(let e): return e.workflowName
        case .workflowError(let e): return e.workflowName
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
        case .workflowExecution: return "workflow-execution"
        case .workflowError: return "workflow-error"
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
        case .sceneExecution(let p): return AnyCodable(p.succeeded)
        case .sceneError(let p): return AnyCodable(p.succeeded)
        case .workflowExecution(let e): return AnyCodable(e.status.rawValue)
        case .workflowError(let e): return AnyCodable(e.status.rawValue)
        case .aiInteraction(let p): return AnyCodable(p.parsedSuccessfully)
        case .aiInteractionError(let p): return AnyCodable(p.parsedSuccessfully)
        default: return nil
        }
    }

    var errorDetails: String? {
        switch payload {
        case .webhookError(let p): return p.errorDetails
        case .serverError(let p): return p.errorDetails
        case .workflowExecution(let e): return e.errorMessage
        case .workflowError(let e): return e.errorMessage
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
        case .workflowExecution(let e): return e.triggerEvent?.triggerDescription
        case .workflowError(let e): return e.triggerEvent?.triggerDescription
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

    /// The full workflow execution log; non-nil for `.workflowExecution` and `.workflowError` entries.
    var workflowExecution: WorkflowExecutionLog? {
        switch payload {
        case .workflowExecution(let e): return e
        case .workflowError(let e): return e
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
                summary: p.summary, result: p.result,
                errorDetails: p.errorDetails.map { Self.truncate($0) },
                detailedRequest: p.detailedRequest.map { Self.truncate($0) }
            )
            truncatedPayload = .webhookError(p)
        case .mcpCall(let p):
            truncatedPayload = .mcpCall(APICallPayload(
                method: p.method, summary: p.summary, result: p.result,
                detailedRequest: p.detailedRequest.map { Self.truncate($0) }
            ))
        case .restCall(let p):
            truncatedPayload = .restCall(APICallPayload(
                method: p.method, summary: p.summary, result: p.result,
                detailedRequest: p.detailedRequest.map { Self.truncate($0) }
            ))
        case .serverError(let p):
            truncatedPayload = .serverError(ServerErrorPayload(
                errorDetails: Self.truncate(p.errorDetails)
            ))
        case .workflowExecution, .workflowError:
            // WorkflowExecutionLog has its own field-level truncation; pass through.
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


// MARK: - Codable (flat JSON; workflow entries include full WorkflowExecutionLog)

extension StateChangeLog: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, category
        case deviceId, deviceName, roomName, serviceId, serviceName
        case characteristicType, oldValue, newValue
        case errorDetails, requestBody, responseBody, detailedRequestBody
        case workflowExecution
        case aiInteractionPayload
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(category, forKey: .category)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encodeIfPresent(roomName, forKey: .roomName)
        try container.encodeIfPresent(serviceId, forKey: .serviceId)
        try container.encodeIfPresent(serviceName, forKey: .serviceName)
        try container.encode(characteristicType, forKey: .characteristicType)
        try container.encodeIfPresent(oldValue, forKey: .oldValue)
        try container.encodeIfPresent(newValue, forKey: .newValue)
        try container.encodeIfPresent(errorDetails, forKey: .errorDetails)
        try container.encodeIfPresent(requestBody, forKey: .requestBody)
        try container.encodeIfPresent(responseBody, forKey: .responseBody)
        try container.encodeIfPresent(detailedRequestBody, forKey: .detailedRequestBody)
        // Workflow entries: encode the full execution log for rich API consumers.
        if let execLog = workflowExecution {
            try container.encode(execLog, forKey: .workflowExecution)
        }
        // AI interaction entries: encode the full payload.
        if let aiPayload = aiInteraction {
            try container.encode(aiPayload, forKey: .aiInteractionPayload)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        category = try container.decode(LogCategory.self, forKey: .category)

        let deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        let deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        let roomName = try container.decodeIfPresent(String.self, forKey: .roomName)
        let serviceId = try container.decodeIfPresent(String.self, forKey: .serviceId)
        let serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName)
        let characteristicType = try container.decodeIfPresent(String.self, forKey: .characteristicType) ?? ""
        let oldValue = try container.decodeIfPresent(AnyCodable.self, forKey: .oldValue)
        let newValue = try container.decodeIfPresent(AnyCodable.self, forKey: .newValue)
        let errorDetails = try container.decodeIfPresent(String.self, forKey: .errorDetails)
        let requestBody = try container.decodeIfPresent(String.self, forKey: .requestBody)
        let responseBody = try container.decodeIfPresent(String.self, forKey: .responseBody)
        let detailedRequestBody = try container.decodeIfPresent(String.self, forKey: .detailedRequestBody)

        switch category {
        case .stateChange:
            payload = .stateChange(DeviceStatePayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue
            ))
        case .webhookCall:
            payload = .webhookCall(WebhookLogPayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue,
                summary: requestBody ?? "", result: responseBody ?? "",
                errorDetails: errorDetails, detailedRequest: detailedRequestBody
            ))
        case .webhookError:
            payload = .webhookError(WebhookLogPayload(
                deviceId: deviceId, deviceName: deviceName,
                roomName: roomName,
                serviceId: serviceId, serviceName: serviceName,
                characteristicType: characteristicType,
                oldValue: oldValue, newValue: newValue,
                summary: requestBody ?? "", result: responseBody ?? "",
                errorDetails: errorDetails, detailedRequest: detailedRequestBody
            ))
        case .mcpCall:
            payload = .mcpCall(APICallPayload(
                method: characteristicType,
                summary: requestBody ?? "", result: responseBody ?? "",
                detailedRequest: detailedRequestBody
            ))
        case .restCall:
            payload = .restCall(APICallPayload(
                method: characteristicType,
                summary: requestBody ?? "", result: responseBody ?? "",
                detailedRequest: detailedRequestBody
            ))
        case .serverError:
            payload = .serverError(ServerErrorPayload(
                errorDetails: errorDetails ?? ""
            ))
        case .workflowExecution, .workflowError:
            // Workflow entries are synthesised at query time and should not be persisted
            // in logs.json. If we decode one (stale file), reconstruct from embedded data.
            if let execLog = try? container.decode(WorkflowExecutionLog.self, forKey: .workflowExecution) {
                payload = category == .workflowError ? .workflowError(execLog) : .workflowExecution(execLog)
            } else {
                payload = .serverError(ServerErrorPayload(errorDetails: errorDetails ?? "legacy workflow log"))
            }
        case .sceneExecution:
            let succeeded = (newValue?.value as? Bool) ?? true
            payload = .sceneExecution(ScenePayload(
                sceneId: deviceId, sceneName: deviceName,
                succeeded: succeeded, summary: requestBody,
                errorDetails: errorDetails
            ))
        case .sceneError:
            let succeeded = (newValue?.value as? Bool) ?? false
            payload = .sceneError(ScenePayload(
                sceneId: deviceId, sceneName: deviceName,
                succeeded: succeeded, summary: requestBody,
                errorDetails: errorDetails
            ))
        case .backupRestore:
            payload = .backupRestore(BackupRestorePayload(
                subtype: characteristicType,
                summary: errorDetails ?? ""
            ))
        case .aiInteraction:
            if let aiPayload = try? container.decode(AIInteractionPayload.self, forKey: .aiInteractionPayload) {
                payload = .aiInteraction(aiPayload)
            } else {
                payload = .serverError(ServerErrorPayload(errorDetails: errorDetails ?? "legacy AI interaction log"))
            }
        case .aiInteractionError:
            if let aiPayload = try? container.decode(AIInteractionPayload.self, forKey: .aiInteractionPayload) {
                payload = .aiInteractionError(aiPayload)
            } else {
                payload = .serverError(ServerErrorPayload(errorDetails: errorDetails ?? "legacy AI interaction log"))
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
    let characteristicType: String
    let oldValue: Any?
    let newValue: Any?
    let timestamp: Date

    init(deviceId: String, deviceName: String, roomName: String? = nil, serviceId: String? = nil, serviceName: String? = nil, characteristicType: String, oldValue: Any? = nil, newValue: Any? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.characteristicType = characteristicType
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}
