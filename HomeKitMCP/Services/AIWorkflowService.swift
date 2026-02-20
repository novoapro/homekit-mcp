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
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw AIWorkflowError.networkError("Invalid Gemini URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        }
    }
}

// MARK: - AI Workflow Service

actor AIWorkflowService {
    private let storage: StorageService
    private let homeKitManager: HomeKitManager
    private let keychainService: KeychainService

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(storage: StorageService, homeKitManager: HomeKitManager, keychainService: KeychainService) {
        self.storage = storage
        self.homeKitManager = homeKitManager
        self.keychainService = keychainService
    }

    /// Generate a Workflow from a natural language description.
    func generateWorkflow(from description: String) async throws -> Workflow {
        let (client, apiKey, model) = try getClientConfig()
        let systemPrompt = await buildSystemPrompt()
        let userMessage = "Create a HomeKit automation workflow for the following:\n\n\(description)"

        let response = try await client.complete(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey, model: model)
        return try parseWorkflowFromResponse(response)
    }

    /// Refine an existing workflow based on user feedback.
    func refineWorkflow(_ workflow: Workflow, feedback: String) async throws -> Workflow {
        let (client, apiKey, model) = try getClientConfig()
        let systemPrompt = await buildSystemPrompt()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let workflowJSON = String(data: try encoder.encode(workflow), encoding: .utf8) ?? "{}"

        let userMessage = """
            Here is the current workflow JSON:

            ```json
            \(workflowJSON)
            ```

            Please modify this workflow based on the following feedback:

            \(feedback)

            Return the complete updated workflow JSON.
            """

        let response = try await client.complete(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey, model: model)
        return try parseWorkflowFromResponse(response)
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

    private func buildSystemPrompt() async -> String {
        let devices = await MainActor.run { homeKitManager.cachedDevices }
        let deviceContext = buildDeviceContext(devices)

        return """
            You are a HomeKit automation workflow builder. Given a natural language description, \
            generate a valid workflow JSON object.

            ## Output Format

            Return ONLY a JSON code block with the workflow. Do not include any explanation before \
            or after the JSON. The JSON must be wrapped in ```json ... ``` markers.

            ## Workflow Schema

            ```json
            {
              "name": "string (required)",
              "description": "string (optional)",
              "isEnabled": true,
              "continueOnError": false,
              "triggers": [
                {
                  "type": "deviceStateChange",
                  "deviceId": "device-uuid",
                  "characteristicType": "characteristic-name-or-uuid",
                  "condition": { "type": "equals|notEquals|changed|greaterThan|lessThan|transitioned", "value": ... }
                }
              ],
              "conditions": [
                {
                  "type": "deviceState",
                  "deviceId": "device-uuid",
                  "characteristicType": "characteristic-name-or-uuid",
                  "comparison": { "type": "equals|notEquals|greaterThan|lessThan", "value": ... }
                }
              ],
              "blocks": [
                { "block": "action", "type": "controlDevice", "deviceId": "...", "characteristicType": "...", "value": ... },
                { "block": "action", "type": "webhook", "url": "...", "method": "POST" },
                { "block": "action", "type": "log", "message": "..." },
                { "block": "flowControl", "type": "delay", "seconds": 5.0 },
                { "block": "flowControl", "type": "waitForState", "deviceId": "...", "characteristicType": "...", "condition": {...}, "timeoutSeconds": 60 },
                { "block": "flowControl", "type": "conditional", "condition": {...}, "thenBlocks": [...], "elseBlocks": [...] },
                { "block": "flowControl", "type": "repeat", "count": 3, "blocks": [...] },
                { "block": "flowControl", "type": "repeatWhile", "condition": {...}, "blocks": [...], "maxIterations": 10 },
                { "block": "flowControl", "type": "group", "label": "...", "blocks": [...] }
              ]
            }
            ```

            ## Trigger Condition Types
            - "changed": fires on any value change
            - "equals": fires when value equals the specified value
            - "notEquals": fires when value does not equal the specified value
            - "transitioned": fires on value transition, with optional "from" and required "to" fields
            - "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual": numeric comparisons

            ## Guard Condition Types
            - "deviceState": check current device state with a comparison operator
            - "and": array of sub-conditions, all must be true
            - "or": array of sub-conditions, any must be true
            - "not": negate a single condition

            ## Important Rules
            - Use the exact deviceId values from the device list below
            - Use human-readable characteristic names (e.g. "Power", "Brightness", "Current Temperature")
            - For boolean characteristics like Power, use true/false values
            - For percentage characteristics like Brightness, use 0-100
            - Always include at least one trigger and one block
            - Generate a descriptive name for the workflow

            ## Available Devices

            \(deviceContext)
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
                lines.append("  - Service: \(service.displayName) (id: \(service.id))")
                for char in service.characteristics {
                    let name = CharacteristicTypes.displayName(for: char.type)
                    let val = char.value.map { "\($0.value)" } ?? "nil"
                    lines.append("    - \(name) (type: \(char.type)) = \(val)")
                }
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
