import Foundation

// MARK: - LLM Client Protocol

protocol LLMClient {
    func complete(systemPrompt: String, userMessage: String, apiKey: String, model: String) async throws -> String
}

// MARK: - Claude Client (Anthropic)

struct ClaudeClient: LLMClient {
    func complete(systemPrompt: String, userMessage: String, apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWorkflowError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIWorkflowError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIWorkflowError.parseError("Could not extract text from Claude response")
        }

        return text
    }
}

// MARK: - OpenAI Client

struct OpenAIClient: LLMClient {
    func complete(systemPrompt: String, userMessage: String, apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 4096,
            "temperature": 0.2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWorkflowError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIWorkflowError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIWorkflowError.parseError("Could not extract text from OpenAI response")
        }

        return text
    }
}

// MARK: - Gemini Client (Google)

struct GeminiClient: LLMClient {
    func complete(systemPrompt: String, userMessage: String, apiKey: String, model: String) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw AIWorkflowError.networkError("Invalid Gemini URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userMessage]]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096,
                "temperature": 0.2
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWorkflowError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIWorkflowError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIWorkflowError.parseError("Could not extract text from Gemini response")
        }

        return text
    }
}

// MARK: - AI Workflow Error

enum AIWorkflowError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case parseError(String)
    case noJSONFound
    case vagueprompt(String)
    case modelRefused(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI is not configured. Set an API key in Settings."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .noJSONFound:
            return "The AI response did not contain valid workflow JSON."
        case .vagueprompt(let msg):
            return msg
        case .modelRefused(let msg):
            return msg
        }
    }
}

// MARK: - AI Workflow Service

actor AIWorkflowService {
    private let storage: StorageService
    private let homeKitManager: HomeKitManager
    private let keychainService: KeychainService
    let interactionLog: AIInteractionLogService

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(storage: StorageService, homeKitManager: HomeKitManager, keychainService: KeychainService, interactionLog: AIInteractionLogService) {
        self.storage = storage
        self.homeKitManager = homeKitManager
        self.keychainService = keychainService
        self.interactionLog = interactionLog
    }

    /// Generate a Workflow from a natural language description.
    func generateWorkflow(from description: String) async throws -> Workflow {
        let (client, apiKey, model) = try getClientConfig()
        let provider = storage.readAIProvider()

        // Validate the prompt references known devices, scenes, or HomeKit concepts
        try await validatePrompt(description)

        let systemPrompt = buildSystemPrompt()
        let userMessage = await buildUserMessage(description: "Create a HomeKit automation workflow for the following:\n\n\(description)")
        let startTime = CFAbsoluteTimeGetCurrent()

        let response: String
        do {
            response = try await client.complete(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey, model: model)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            await interactionLog.log(AIInteractionLog(
                id: UUID(), timestamp: Date(),
                provider: provider.rawValue, model: model,
                operation: "generate",
                systemPrompt: systemPrompt, userMessage: userMessage,
                rawResponse: nil, parsedSuccessfully: false,
                errorMessage: error.localizedDescription,
                durationSeconds: duration
            ))
            throw error
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        do {
            let workflow = try parseWorkflowFromResponse(response)
            await interactionLog.log(AIInteractionLog(
                id: UUID(), timestamp: Date(),
                provider: provider.rawValue, model: model,
                operation: "generate",
                systemPrompt: systemPrompt, userMessage: userMessage,
                rawResponse: response, parsedSuccessfully: true,
                errorMessage: nil, durationSeconds: duration
            ))
            return workflow
        } catch {
            await interactionLog.log(AIInteractionLog(
                id: UUID(), timestamp: Date(),
                provider: provider.rawValue, model: model,
                operation: "generate",
                systemPrompt: systemPrompt, userMessage: userMessage,
                rawResponse: response, parsedSuccessfully: false,
                errorMessage: error.localizedDescription,
                durationSeconds: duration
            ))
            throw error
        }
    }

    /// Refine an existing workflow based on user feedback.
    func refineWorkflow(_ workflow: Workflow, feedback: String) async throws -> Workflow {
        let (client, apiKey, model) = try getClientConfig()
        let provider = storage.readAIProvider()
        let systemPrompt = buildSystemPrompt()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let workflowJSON = String(data: try encoder.encode(workflow), encoding: .utf8) ?? "{}"

        let userMessage = await buildRefinementMessage(workflowJSON: workflowJSON, feedback: feedback)

        let startTime = CFAbsoluteTimeGetCurrent()

        let response: String
        do {
            response = try await client.complete(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey, model: model)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            await interactionLog.log(AIInteractionLog(
                id: UUID(), timestamp: Date(),
                provider: provider.rawValue, model: model,
                operation: "refine",
                systemPrompt: systemPrompt, userMessage: userMessage,
                rawResponse: nil, parsedSuccessfully: false,
                errorMessage: error.localizedDescription,
                durationSeconds: duration
            ))
            throw error
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        do {
            let refined = try parseWorkflowFromResponse(response)
            await interactionLog.log(AIInteractionLog(
                id: UUID(), timestamp: Date(),
                provider: provider.rawValue, model: model,
                operation: "refine",
                systemPrompt: systemPrompt, userMessage: userMessage,
                rawResponse: response, parsedSuccessfully: true,
                errorMessage: nil, durationSeconds: duration
            ))
            return refined
        } catch {
            await interactionLog.log(AIInteractionLog(
                id: UUID(), timestamp: Date(),
                provider: provider.rawValue, model: model,
                operation: "refine",
                systemPrompt: systemPrompt, userMessage: userMessage,
                rawResponse: response, parsedSuccessfully: false,
                errorMessage: error.localizedDescription,
                durationSeconds: duration
            ))
            throw error
        }
    }

    /// Test the AI connection with a simple prompt.
    func testConnection() async throws -> String {
        let (client, apiKey, model) = try getClientConfig()
        let response = try await client.complete(
            systemPrompt: "You are a helpful assistant. Respond briefly.",
            userMessage: "Say 'Connection successful' and nothing else.",
            apiKey: apiKey,
            model: model
        )
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    /// Validates that the user's description is specific enough to produce a meaningful workflow.
    /// Checks that it references at least one known device, room, scene, or common HomeKit keyword.
    private func validatePrompt(_ description: String) async throws {
        let (devices, scenes) = await MainActor.run {
            (homeKitManager.cachedDevices, homeKitManager.cachedScenes)
        }

        let lowered = description.lowercased()

        // Check if the description references any known device name
        let matchesDevice = devices.contains { device in
            lowered.contains(device.name.lowercased())
        }

        // Check if it references any known room name
        let matchesRoom = devices.contains { device in
            if let room = device.roomName {
                return lowered.contains(room.lowercased())
            }
            return false
        }

        // Check if it references any known scene name
        let matchesScene = scenes.contains { scene in
            lowered.contains(scene.name.lowercased())
        }

        // Check for common HomeKit action/concept keywords
        let homekitKeywords = [
            "light", "lights", "lamp", "lamps", "bulb",
            "switch", "switches", "outlet", "plug",
            "thermostat", "temperature", "heating", "cooling", "hvac", "climate",
            "lock", "unlock", "door", "garage", "window", "blind", "blinds", "shade", "shades", "curtain",
            "fan", "humidifier", "dehumidifier",
            "sensor", "motion", "occupancy", "contact", "leak", "smoke", "carbon",
            "camera", "security", "alarm",
            "speaker", "tv", "television",
            "brightness", "color", "hue", "saturation",
            "turn on", "turn off", "set", "dim", "open", "close",
            "sunrise", "sunset", "schedule", "every day", "every morning", "every night", "every evening",
            "when", "trigger", "if", "then", "wait", "delay", "after",
            "scene", "webhook"
        ]
        let matchesKeyword = homekitKeywords.contains { keyword in
            lowered.contains(keyword)
        }

        if matchesDevice || matchesRoom || matchesScene || matchesKeyword {
            return // Prompt is specific enough
        }

        // Build a helpful error message
        var hint = "Your description doesn't seem to reference any of your HomeKit devices, rooms, or scenes."
        if !devices.isEmpty {
            let deviceNames = devices.prefix(5).map { $0.name }
            let nameList = deviceNames.joined(separator: ", ")
            hint += " Try mentioning specific devices like: \(nameList)."
        } else {
            hint += " No HomeKit devices are currently available — make sure they are paired and reachable."
        }
        throw AIWorkflowError.vagueprompt(hint)
    }

    private func getClientConfig() throws -> (LLMClient, String, String) {
        guard storage.readAIEnabled() else {
            throw AIWorkflowError.notConfigured
        }

        guard let apiKey = keychainService.read(key: KeychainService.Keys.aiApiKey), !apiKey.isEmpty else {
            throw AIWorkflowError.notConfigured
        }

        let provider = storage.readAIProvider()
        let customModel = storage.readAIModelId()
        let model = customModel.isEmpty ? provider.defaultModel : customModel

        let client: LLMClient
        switch provider {
        case .claude: client = ClaudeClient()
        case .openai: client = OpenAIClient()
        case .gemini: client = GeminiClient()
        }

        return (client, apiKey, model)
    }

    // MARK: - Default System Prompt

    static let defaultSystemPrompt: String = """
        You are a HomeKit automation workflow builder. Given a natural language description, \
        generate a valid workflow JSON object.

        ## Output Format

        Return ONLY a JSON code block. Do not include any explanation before or after the JSON. \
        The JSON must be wrapped in ```json ... ``` markers.

        ## CRITICAL: Anti-Hallucination Rules

        - Do NOT invent device IDs, scene IDs, or characteristic types that are not listed in the \
        available devices/scenes provided with the user message.
        - If the user's description is ambiguous, too vague, or does not clearly specify what \
        devices to control and what actions to take, do NOT guess. Instead, return an error JSON \
        (see Error Format below).
        - If the user references a device or scene that does not exist in the provided lists, \
        return an error JSON explaining which device or scene could not be found.
        - Never fabricate UUIDs or placeholder IDs.

        ## Error Format

        When you cannot confidently generate a workflow, return ONLY a JSON code block with:
        ```json
        {
          "error": true,
          "message": "Human-readable explanation of what is unclear or missing"
        }
        ```

        Examples of when to return an error:
        - "Turn on the thing" (which device?)
        - "Make it comfortable" (what action on what device?)
        - User references "kitchen light" but no such device exists in the available list
        - The description has no clear trigger or action

        ## Workflow Schema

        ```json
        {
          "name": "string (required)",
          "description": "string (optional)",
          "isEnabled": true,
          "continueOnError": false,
          "retriggerPolicy": "ignoreNew",
          "triggers": [ ... ],
          "conditions": [ ... ],
          "blocks": [ ... ]
        }
        ```

        ### retriggerPolicy (optional, defaults to "ignoreNew")
        Controls what happens if the workflow is triggered while already running:
        - "ignoreNew": ignore the new trigger
        - "cancelAndRestart": cancel the running execution and restart
        - "queueAndExecute": queue the trigger for after the current run

        ## Trigger Types

        ### deviceStateChange
        ```json
        {
          "type": "deviceStateChange",
          "name": "optional label",
          "deviceId": "device-uuid",
          "serviceId": "optional-service-uuid",
          "characteristicType": "Power",
          "condition": { "type": "equals", "value": true }
        }
        ```
        Condition types: "changed" (no value needed), "equals", "notEquals", \
        "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual" (with "value"), \
        "transitioned" (with required "to" and optional "from").

        ### schedule
        ```json
        { "type": "schedule", "name": "optional label", "scheduleType": { ... } }
        ```
        Schedule type formats:
        - Once: `{ "type": "once", "date": "2025-01-15T08:00:00Z" }`
        - Daily: `{ "type": "daily", "time": { "hour": 7, "minute": 30 } }`
        - Weekly: `{ "type": "weekly", "time": { "hour": 7, "minute": 30 }, "days": [2, 3, 4, 5, 6] }`
          (1=Sunday, 2=Monday, 3=Tuesday, 4=Wednesday, 5=Thursday, 6=Friday, 7=Saturday)
        - Interval: `{ "type": "interval", "seconds": 300 }`

        ### sunEvent
        ```json
        { "type": "sunEvent", "name": "optional label", "event": "sunrise", "offsetMinutes": -15 }
        ```
        Events: "sunrise", "sunset". offsetMinutes: negative = before, positive = after, 0 = exact.

        ### compound
        Combines multiple triggers with AND/OR logic:
        ```json
        { "type": "compound", "name": "optional label", "operator": "and", "triggers": [ ... ] }
        ```
        Note: the JSON key is "operator" (not "logicOperator").

        ### webhook
        ```json
        { "type": "webhook", "name": "optional label", "token": "unique-token-string" }
        ```

        ### workflow
        Makes this workflow callable from other workflows:
        ```json
        { "type": "workflow", "name": "optional label" }
        ```

        ## Block Types

        ### Action Blocks

        ```json
        { "block": "action", "type": "controlDevice", "name": "optional", "deviceId": "...", "serviceId": "optional-service-uuid", "characteristicType": "Power", "value": true }
        { "block": "action", "type": "runScene", "name": "optional", "sceneId": "scene-uuid" }
        { "block": "action", "type": "webhook", "name": "optional", "url": "https://...", "method": "POST", "headers": {}, "body": {} }
        { "block": "action", "type": "log", "name": "optional", "message": "Something happened" }
        ```

        ### Flow Control Blocks

        ```json
        { "block": "flowControl", "type": "delay", "name": "optional", "seconds": 5.0 }
        { "block": "flowControl", "type": "waitForState", "name": "optional", "deviceId": "...", "serviceId": "optional", "characteristicType": "Power", "condition": { "type": "equals", "value": true }, "timeoutSeconds": 60 }
        { "block": "flowControl", "type": "conditional", "name": "optional", "condition": { ... }, "thenBlocks": [ ... ], "elseBlocks": [ ... ] }
        { "block": "flowControl", "type": "repeat", "name": "optional", "count": 3, "blocks": [ ... ], "delayBetweenSeconds": 1.0 }
        { "block": "flowControl", "type": "repeatWhile", "name": "optional", "condition": { ... }, "blocks": [ ... ], "maxIterations": 10, "delayBetweenSeconds": 1.0 }
        { "block": "flowControl", "type": "group", "name": "optional", "label": "Group label", "blocks": [ ... ] }
        { "block": "flowControl", "type": "stop", "name": "optional", "outcome": "success", "message": "optional reason" }
        { "block": "flowControl", "type": "executeWorkflow", "name": "optional", "targetWorkflowId": "workflow-uuid", "executionMode": "inline" }
        ```
        stop outcomes: "success", "error", "cancelled".
        executeWorkflow modes: "inline" (wait for it), "parallel" (fire and continue), "delegate" (fire and stop this workflow).
        delayBetweenSeconds is optional on repeat and repeatWhile blocks.

        ### Compound conditions in conditional and repeatWhile blocks
        The "condition" field in conditional and repeatWhile blocks accepts compound conditions \
        using the same format as guard conditions: {"type":"and","conditions":[...]}, \
        {"type":"or","conditions":[...]}, {"type":"not","condition":{...}}. These can be nested \
        to any depth. For example, a conditional block could use \
        {"type":"and","conditions":[{"type":"deviceState",...},{"type":"sunEvent",...}]} to check \
        multiple conditions together.

        ### waitForState condition format
        The "condition" in waitForState uses ComparisonOperator: "equals", "notEquals", \
        "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual" with a "value" field. \
        "changed" and "transitioned" are NOT valid here.

        ## Guard Condition Types (workflow-level "conditions" array)

        Guard conditions are checked before the workflow runs. If any fail, the workflow is skipped.

        ```json
        { "type": "deviceState", "deviceId": "...", "serviceId": "optional", "characteristicType": "Power", "comparison": { "type": "equals", "value": true } }
        { "type": "sunEvent", "event": "sunrise", "sunComparison": "after" }
        { "type": "sceneActive", "sceneId": "scene-uuid", "isActive": true }
        { "type": "and", "conditions": [ ... ] }
        { "type": "or", "conditions": [ ... ] }
        { "type": "not", "condition": { ... } }
        ```
        The "comparison" in deviceState uses ComparisonOperator: "equals", "notEquals", \
        "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual" with "value".
        sunComparison values: "before", "after".

        ## Trigger Condition Types (for deviceStateChange triggers only)
        - "changed": fires on any value change (no "value" field needed)
        - "equals": fires when value equals the specified value
        - "notEquals": fires when value does not equal the specified value
        - "transitioned": fires on specific state transition, with required "to" and optional "from"
        - "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual": numeric comparisons

        ## Important Rules
        - Use the exact deviceId and sceneId values from the device and scene lists provided with the user message
        - Use human-readable characteristic names (e.g. "Power", "Brightness", "Current Temperature")
        - For boolean characteristics like Power, use true/false values
        - For percentage characteristics like Brightness, use 0-100
        - Always include at least one trigger and one block
        - Generate a descriptive name for the workflow
        - Blocks and triggers can optionally include a "name" field for readability. \
        Use short, descriptive names like "Turn on lamp", "Wait for door", "Check temperature"
        - The "serviceId" field is optional; use it only for devices with multiple services of the same type
        - Do not include "id", "createdAt", "updatedAt", or "metadata" — they are auto-generated
        """

    // MARK: - Prompt Construction

    private func buildSystemPrompt() -> String {
        let custom = storage.readAISystemPrompt()
        return custom.isEmpty ? Self.defaultSystemPrompt : custom
    }

    private func buildUserMessage(description: String) async -> String {
        let (devices, scenes) = await MainActor.run {
            (homeKitManager.cachedDevices, homeKitManager.cachedScenes)
        }
        let deviceContext = buildDeviceContext(devices)
        let sceneContext = buildSceneContext(scenes)

        return """
            \(description)

            ## Available Devices

            \(deviceContext)

            ## Available Scenes

            \(sceneContext)
            """
    }

    private func buildRefinementMessage(workflowJSON: String, feedback: String) async -> String {
        let (devices, scenes) = await MainActor.run {
            (homeKitManager.cachedDevices, homeKitManager.cachedScenes)
        }
        let deviceContext = buildDeviceContext(devices)
        let sceneContext = buildSceneContext(scenes)

        return """
            Here is the current workflow JSON:

            ```json
            \(workflowJSON)
            ```

            Please modify this workflow based on the following feedback:

            \(feedback)

            Return the complete updated workflow JSON.

            ## Available Devices

            \(deviceContext)

            ## Available Scenes

            \(sceneContext)
            """
    }

    private func buildDeviceContext(_ devices: [DeviceModel]) -> String {
        if devices.isEmpty {
            return "No devices available. Use placeholder device IDs."
        }

        var lines: [String] = []
        for device in devices {
            let room = device.roomName ?? "No Room"
            let reachable = device.isReachable ? "online" : "offline"
            lines.append("### \(device.name) [\(reachable)]")
            lines.append("  - ID: \(device.id)")
            lines.append("  - Room: \(room)")
            for service in device.services {
                lines.append("  - Service: \(service.effectiveDisplayName) (id: \(service.id))")
                for char in service.characteristics {
                    guard char.isUserFacing else { continue }
                    let name = CharacteristicTypes.displayName(for: char.type)
                    let val = char.value.map { "\($0.value)" } ?? "nil"
                    lines.append("    - \(name) (type: \(char.type)) = \(val)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func buildSceneContext(_ scenes: [SceneModel]) -> String {
        if scenes.isEmpty {
            return "No scenes available."
        }

        var lines: [String] = []
        for scene in scenes {
            lines.append("### \(scene.name)")
            lines.append("  - ID: \(scene.id)")
            lines.append("  - Type: \(scene.type)")
            for action in scene.actions {
                let charName = CharacteristicTypes.displayName(for: action.characteristicType)
                lines.append("  - Action: Set \(charName) = \(action.targetValue.value) on \(action.deviceName)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func parseWorkflowFromResponse(_ response: String) throws -> Workflow {
        // Extract JSON from markdown code block
        let jsonString: String
        if let range = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: range.upperBound..<response.endIndex) {
            jsonString = String(response[range.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let range = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: range.upperBound..<response.endIndex) {
            jsonString = String(response[range.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if response.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            // Raw JSON without code block markers
            jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw AIWorkflowError.noJSONFound
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIWorkflowError.parseError("Could not convert response to data")
        }

        // Check for model-refused error pattern before attempting workflow decode
        if let errorDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let isError = errorDict["error"] as? Bool,
           isError {
            let message = errorDict["message"] as? String ?? "The AI could not generate a workflow from your description."
            throw AIWorkflowError.modelRefused(message)
        }

        // Normalize with defaults (same as MCP create_workflow)
        var dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]

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
        if dict["retriggerPolicy"] == nil { dict["retriggerPolicy"] = "ignoreNew" }
        if dict["triggers"] == nil { dict["triggers"] = [] as [Any] }
        if dict["blocks"] == nil { dict["blocks"] = [] as [Any] }
        let now = ISO8601DateFormatter().string(from: Date())
        if dict["createdAt"] == nil { dict["createdAt"] = now }
        if dict["updatedAt"] == nil { dict["updatedAt"] = now }
        if dict["metadata"] == nil {
            dict["metadata"] = ["totalExecutions": 0, "consecutiveFailures": 0] as [String: Any]
        }

        let normalizedData = try JSONSerialization.data(withJSONObject: dict)
        return try Self.decoder.decode(Workflow.self, from: normalizedData)
    }
}
