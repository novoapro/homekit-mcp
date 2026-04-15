import Foundation
import HomeKit

/// Handles MCP JSON-RPC method dispatch and builds responses.
/// All stored properties are immutable (`let`), making this class safe to share across isolation domains.
final class MCPRequestHandler: Sendable {
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let storage: StorageService
    private let automationStorageService: AutomationStorageService
    private let automationEngine: AutomationEngine
    private let registry: DeviceRegistryService?
    private let aiAutomationService: AIAutomationService?
    private let subscriptionService: SubscriptionService?
    private let stateVariableStorage: StateVariableStorageService?

    init(homeKitManager: HomeKitManager, loggingService: LoggingService, storage: StorageService,
         automationStorageService: AutomationStorageService, automationEngine: AutomationEngine,
         registry: DeviceRegistryService? = nil, aiAutomationService: AIAutomationService? = nil,
         subscriptionService: SubscriptionService? = nil,
         stateVariableStorage: StateVariableStorageService? = nil) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.storage = storage
        self.automationStorageService = automationStorageService
        self.automationEngine = automationEngine
        self.registry = registry
        self.aiAutomationService = aiAutomationService
        self.subscriptionService = subscriptionService
        self.stateVariableStorage = stateVariableStorage
    }

    func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        let requestSummary = summarizeRequest(request)

        let response: JSONRPCResponse
        switch request.method {
        case "initialize":
            response = handleInitialize(id: request.id, params: request.params)
        case "notifications/initialized":
            response = JSONRPCResponse.success(id: request.id, result: AnyCodable([:] as [String: String]))
        case "ping":
            response = JSONRPCResponse.success(id: request.id, result: AnyCodable([:] as [String: String]))
        case "resources/list":
            response = handleResourcesList(id: request.id)
        case "resources/read":
            response = await handleResourcesRead(id: request.id, params: request.params)
        case "tools/list":
            response = handleToolsList(id: request.id)
        case "tools/call":
            response = await handleToolsCall(id: request.id, params: request.params)
        default:
            response = JSONRPCResponse.error(
                id: request.id,
                code: MCPErrorCode.methodNotFound,
                message: "Method not found: \(request.method)"
            )
        }

        // Skip logging for get_logs to avoid noise (polled frequently)
        let isGetLogs = request.method == "tools/call"
            && (request.params?.value as? [String: Any])?["name"] as? String == "get_logs"
        if !isGetLogs {
            let responseSummary = summarizeResponse(response)
            await logMCPCall(method: request.method, request: requestSummary, response: responseSummary,
                             fullRequest: request, fullResponse: response)
        }

        return response
    }

    // MARK: - Registry Helpers

    /// Returns enabled devices with stable IDs and effective permissions.
    func stableDevices(_ devices: [DeviceModel]) -> [DeviceModel] {
        guard let registry else { return devices }
        return registry.stableDevices(devices)
    }

    /// Returns scenes with stable IDs.
    func stableScenes(_ scenes: [SceneModel]) -> [SceneModel] {
        guard let registry else { return scenes }
        return registry.stableScenes(scenes)
    }

    /// Checks whether a specific device + characteristic is exposed (enabled) for external access.
    /// Automation tool names for guard checks when automations are disabled.
    private static let automationToolNames: Set<String> = [
        "list_automations", "get_automation", "create_automation", "update_automation",
        "delete_automation", "enable_automation", "get_automation_logs",
        "trigger_automation", "improve_automation",
        "list_global_values", "get_global_value", "create_global_value",
        "update_global_value", "delete_global_value"
    ]

    // MARK: - Initialize

    private func handleInitialize(id: JSONRPCId?, params: AnyCodable?) -> JSONRPCResponse {
        // Read client info for logging/debugging
        let paramsDict = params?.value as? [String: Any]
        let clientVersion = paramsDict?["protocolVersion"] as? String
        let clientInfo = paramsDict?["clientInfo"] as? [String: Any]

        if let clientInfo {
            let clientName = clientInfo["name"] as? String ?? "unknown"
            let clientVer = clientInfo["version"] as? String ?? "unknown"
            AppLogger.server.info("MCP client connected: \(clientName) v\(clientVer), requested protocol: \(clientVersion ?? "none")")
        }

        // Negotiate protocol version: pick the client's version if we support it,
        // otherwise fall back to our latest.
        let negotiatedVersion: String
        if let clientVersion, MCPConstants.supportedVersions.contains(clientVersion) {
            negotiatedVersion = clientVersion
        } else {
            negotiatedVersion = MCPConstants.protocolVersion
        }

        let result: [String: Any] = [
            "protocolVersion": negotiatedVersion,
            "capabilities": [
                "resources": [
                    "listChanged": false
                ],
                "tools": [
                    "listChanged": false
                ]
            ] as [String: Any],
            "serverInfo": [
                "name": MCPConstants.serverName,
                "version": MCPConstants.serverVersion
            ],
            "instructions": MCPConstants.serverInstructions
        ]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
    }

    // MARK: - Resources

    private func handleResourcesList(id: JSONRPCId?) -> JSONRPCResponse {
        let resources: [[String: Any]] = [
            [
                "uri": "homekit://devices",
                "name": "HomeKit Devices",
                "description": "List of all HomeKit devices and their current states",
                "mimeType": "application/json"
            ],
            [
                "uri": "homekit://scenes",
                "name": "HomeKit Scenes",
                "description": "List of all HomeKit scenes (action sets) and their actions",
                "mimeType": "application/json"
            ]
        ]
        let result: [String: Any] = ["resources": resources]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
    }

    private func handleResourcesRead(id: JSONRPCId?, params: AnyCodable?) async -> JSONRPCResponse {
        guard let paramsDict = params?.value as? [String: Any],
              let uri = paramsDict["uri"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required parameter: uri"
            )
        }

        switch uri {
        case "homekit://devices":
            let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
            let devices = stableDevices(allDevices)
            let restDevices = devices.map { RESTDevice.from($0) }

            guard let jsonData = try? JSONEncoder.iso8601.encode(restDevices),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return JSONRPCResponse.error(
                    id: id,
                    code: MCPErrorCode.internalError,
                    message: "Failed to encode device data"
                )
            }

            let content: [[String: Any]] = [
                [
                    "uri": "homekit://devices",
                    "mimeType": "application/json",
                    "text": jsonString
                ]
            ]
            let result: [String: Any] = ["contents": content]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))

        case "homekit://scenes":
            let scenes = stableScenes(await MainActor.run { homeKitManager.getAllScenes() })
            let restScenes = scenes.map { RESTScene.from($0) }

            guard let jsonData = try? JSONEncoder.iso8601.encode(restScenes),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return JSONRPCResponse.error(
                    id: id,
                    code: MCPErrorCode.internalError,
                    message: "Failed to encode scene data"
                )
            }

            let content: [[String: Any]] = [
                [
                    "uri": "homekit://scenes",
                    "mimeType": "application/json",
                    "text": jsonString
                ]
            ]
            let result: [String: Any] = ["contents": content]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))

        default:
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Unknown resource URI: \(uri)"
            )
        }
    }

    // MARK: - Tools

    private func handleToolsList(id: JSONRPCId?) -> JSONRPCResponse {
        var tools = MCPToolDefinitions.deviceTools
        tools += MCPToolDefinitions.sceneTools
        tools += MCPToolDefinitions.metadataTools
        if storage.readAutomationsEnabled() {
            tools += MCPToolDefinitions.automationTools
            tools += MCPToolDefinitions.stateVariableTools
        }
        let result: [String: Any] = ["tools": tools]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
    }

    private func handleToolsCall(id: JSONRPCId?, params: AnyCodable?) async -> JSONRPCResponse {
        guard let paramsDict = params?.value as? [String: Any],
              let toolName = paramsDict["name"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required parameter: name"
            )
        }

        let arguments = paramsDict["arguments"] as? [String: Any] ?? [:]

        // Block automation tools when automations are globally disabled
        if Self.automationToolNames.contains(toolName) && !storage.readAutomationsEnabled() {
            return toolResult(
                text: "Automations are disabled. Enable them in Settings to use automation tools.",
                isError: true,
                id: id
            )
        }

        // Block automation tools when Pro subscription is required
        if Self.automationToolNames.contains(toolName),
           let sub = subscriptionService, sub.readCurrentTier() != .pro {
            return toolResult(
                text: "Automations require a CompAI - Home Pro subscription. Subscribe in Settings > Subscription.",
                isError: true,
                id: id
            )
        }

        // Block log access when disabled in settings
        if toolName == "get_logs" && !storage.readLogAccessEnabled() {
            return toolResult(
                text: "Log access via API is disabled. Enable it in Settings > General > Logging.",
                isError: true,
                id: id
            )
        }

        switch toolName {
        case "list_devices":
            return await handleListDevices(id: id, arguments: arguments)
        case "get_device_details":
            return await handleGetDeviceDetails(id: id, arguments: arguments)
        case "control_device":
            return await handleControlDevice(id: id, arguments: arguments)
        case "list_rooms":
            return await handleListRooms(id: id)
        case "get_logs":
            return await handleGetLogs(id: id, arguments: arguments)
        case "get_devices_by_type":
            return await handleGetDevicesByType(id: id, arguments: arguments)
        case "list_scenes":
            return await handleListScenes(id: id)
        case "execute_scene":
            return await handleExecuteScene(id: id, arguments: arguments)
        case "list_device_categories":
            return handleListDeviceCategories(id: id)
        case "get_automation_schema":
            return handleGetAutomationSchema(id: id)
        case "list_automations":
            return await handleListAutomations(id: id)
        case "get_automation":
            return await handleGetAutomation(id: id, arguments: arguments)
        case "create_automation":
            return await handleCreateAutomation(id: id, arguments: arguments)
        case "update_automation":
            return await handleUpdateAutomation(id: id, arguments: arguments)
        case "delete_automation":
            return await handleDeleteAutomation(id: id, arguments: arguments)
        case "enable_automation":
            return await handleEnableAutomation(id: id, arguments: arguments)
        case "get_automation_logs":
            return await handleGetAutomationLogs(id: id, arguments: arguments)
        case "trigger_automation":
            return await handleTriggerAutomation(id: id, arguments: arguments)
        case "improve_automation":
            return await handleImproveAutomation(id: id, arguments: arguments)
        case "list_global_values":
            return await handleListStateVariables(id: id)
        case "get_global_value":
            return await handleGetStateVariable(id: id, arguments: arguments)
        case "create_global_value":
            return await handleCreateStateVariable(id: id, arguments: arguments)
        case "update_global_value":
            return await handleUpdateStateVariable(id: id, arguments: arguments)
        case "delete_global_value":
            return await handleDeleteStateVariable(id: id, arguments: arguments)
        default:
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Unknown tool: \(toolName)"
            )
        }
    }

    private func handleControlDevice(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let deviceId = arguments["device_id"] as? String,
              let characteristicId = arguments["characteristic_id"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required arguments: device_id, characteristic_id"
            )
        }

        guard let value = arguments["value"] else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: value"
            )
        }

        // Look up the device and find the characteristic by its stable ID
        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        guard let device else {
            return toolResult(text: "Device not found: \(deviceId)", isError: true, id: id)
        }

        // Find the characteristic and its parent service by characteristic ID
        var matchedCharacteristic: CharacteristicModel?
        var matchedServiceId: String?
        for service in device.services {
            if let char = service.characteristics.first(where: { $0.id == characteristicId }) {
                matchedCharacteristic = char
                matchedServiceId = service.id
                break
            }
        }

        guard let characteristic = matchedCharacteristic else {
            return toolResult(text: "Characteristic not found: \(characteristicId)", isError: true, id: id)
        }

        // Check exposure
        let settings = registry?.readCharacteristicSettings(forHomeKitCharId: characteristic.id)
        guard settings?.enabled ?? true else {
            return toolResult(
                text: "Characteristic not exposed for external access.",
                isError: true,
                id: id
            )
        }

        // Check write permission
        guard characteristic.permissions.contains("write") else {
            let displayName = CharacteristicTypes.displayName(for: characteristic.type)
            return toolResult(
                text: "Characteristic '\(displayName)' is not writable (permissions: \(characteristic.permissions.joined(separator: ", "))).",
                isError: true,
                id: id
            )
        }

        // Convert temperature from user's preferred unit back to Celsius for HomeKit
        var effectiveValue = value
        if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(characteristic.type) {
            if let doubleVal = value as? Double {
                effectiveValue = TemperatureConversion.fahrenheitToCelsius(doubleVal)
            } else if let intVal = value as? Int {
                effectiveValue = TemperatureConversion.fahrenheitToCelsius(Double(intVal))
            }
        }

        // Validate value against characteristic metadata
        do {
            try CharacteristicValidator.validate(value: effectiveValue, against: characteristic)
        } catch let error as CharacteristicValidator.ValidationError {
            return toolResult(text: error.message, isError: true, id: id)
        } catch {}

        do {
            try await homeKitManager.updateDevice(id: deviceId, characteristicType: characteristic.type, value: effectiveValue, serviceId: matchedServiceId)

            let displayName = CharacteristicTypes.displayName(for: characteristic.type)
            return toolResult(text: "Successfully set \(displayName) to \(value) on device \(deviceId)", id: id)
        } catch {
            AppLogger.general.error("Device control failed: \(error.localizedDescription)")
            return toolResult(text: "Failed to control device: \(error.localizedDescription)", isError: true, id: id)
        }
    }

    private func handleListDevices(id: JSONRPCId?, arguments: [String: Any] = [:]) async -> JSONRPCResponse {
        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }

        // Parse optional filters
        let roomFilter = arguments["rooms"] as? [String]
        let categoryFilter = arguments["device_category"] as? String

        var lines: [String] = []
        for group in groups {
            // Room filter: case-insensitive match
            if let roomFilter, !roomFilter.isEmpty {
                let matches = roomFilter.contains { $0.localizedCaseInsensitiveCompare(group.roomName) == .orderedSame }
                if !matches { continue }
            }

            var filteredDevices = stableDevices(group.devices)

            // Device category filter
            if let categoryFilter {
                let resolvedCategory = DeviceCategories.categoryType(forName: categoryFilter)
                filteredDevices = filteredDevices.filter { device in
                    if let resolved = resolvedCategory {
                        return device.categoryType == resolved
                    }
                    return device.categoryType.localizedCaseInsensitiveContains(categoryFilter)
                }
            }

            if filteredDevices.isEmpty { continue }
            lines.append("## \(group.roomName)")
            for device in filteredDevices {
                let status = device.isReachable ? "online" : "offline"
                lines.append("- \(device.name) [\(status)] (id: \(device.id))")
                for service in device.services {
                    // Show service header when the device has multiple services
                    if device.services.count > 1 {
                        lines.append("  ### \(service.effectiveDisplayName) (service_id: \(service.id))")
                    }
                    for char in service.characteristics {
                        let charName = CharacteristicTypes.displayName(for: char.type)
                        let val = char.value.map { CharacteristicTypes.formatValue($0.value, characteristicType: char.type) } ?? "--"
                        let perms = Self.compactPermissions(char.permissions)
                        let hint = Self.metadataHint(for: char)
                        let indent = device.services.count > 1 ? "      " : "    "
                        lines.append("\(indent)\(charName) (id: \(char.id)): \(val) [\(perms)]\(hint)")
                    }
                }
            }
            lines.append("")
        }

        if lines.isEmpty {
            lines.append("No HomeKit devices found.")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    // MARK: - Metadata Tools

    private func handleListDeviceCategories(id: JSONRPCId?) -> JSONRPCResponse {
        let entries = DeviceCategories.allEntries
        var lines: [String] = ["Known device categories (\(entries.count)):"]
        for entry in entries {
            if entry.description.isEmpty {
                lines.append("- \(entry.displayName)")
            } else {
                lines.append("- \(entry.displayName) — \(entry.description)")
            }
        }
        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    /// Cached automation schema JSON string — built once, reused on every call.
    private static let cachedAutomationSchemaJSON: String? = {
        let schema: [String: Any] = [
            "description": "Schema for creating and updating automations via create_automation and update_automation tools.",
            "topLevelFields": [
                "name": ["type": "string", "required": true, "description": "Automation name"],
                "description": ["type": "string", "required": false, "description": "Automation description"],
                "isEnabled": ["type": "boolean", "required": false, "default": true],
                "continueOnError": ["type": "boolean", "required": false, "default": false,
                    "description": "Must be true if using blockResult conditions"],
                "triggers": ["type": "array", "required": true, "description": "Array of trigger objects"],
                "conditions": ["type": "array", "required": false,
                    "description": "Optional execution guards (AND-ed). Evaluated after any trigger fires. Supports deviceState, timeCondition, engineState (no blockResult). Failure logs as conditionNotMet (skipped)."],
                "blocks": ["type": "array", "required": true, "description": "Array of block objects (actions and flow control)"]
            ] as [String: Any],
            "retriggerPolicies": [
                "description": "Per-trigger policy for concurrent execution",
                "values": ["ignoreNew", "cancelAndRestart", "queueAndExecute", "cancelOnly"],
                "default": "ignoreNew"
            ] as [String: Any],
            "triggerTypes": [
                [
                    "type": "deviceStateChange",
                    "fields": [
                        "deviceId": ["type": "string", "required": true, "description": "Stable device ID"],
                        "deviceName": ["type": "string", "required": true, "description": "Device name (for migration)"],
                        "roomName": ["type": "string", "required": true, "description": "Room name (for migration)"],
                        "serviceId": ["type": "string", "required": false, "description": "Service ID (for multi-service devices)"],
                        "characteristicId": ["type": "string", "required": true,
                            "description": "Stable characteristic ID from list_devices."],
                        "matchOperator": ["type": "object", "required": true, "description": "Trigger match operator (see triggerConditions)"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false],
                        "conditions": ["type": "array", "required": false,
                            "description": "Per-trigger guard conditions. Supports deviceState, timeCondition, engineState. If conditions fail, trigger is silently skipped."]
                    ] as [String: Any]
                ],
                [
                    "type": "schedule",
                    "fields": [
                        "scheduleType": ["type": "object", "required": true, "description": "See scheduleTypes"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false],
                        "conditions": ["type": "array", "required": false,
                            "description": "Per-trigger guard conditions. Supports deviceState, timeCondition, engineState. If conditions fail, trigger is silently skipped."]
                    ] as [String: Any]
                ],
                [
                    "type": "sunEvent",
                    "fields": [
                        "event": ["type": "string", "required": true, "values": ["sunrise", "sunset"]],
                        "offsetMinutes": ["type": "integer", "required": false, "default": 0,
                            "description": "Negative=before, positive=after, 0=exact"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false],
                        "conditions": ["type": "array", "required": false,
                            "description": "Per-trigger guard conditions. Supports deviceState, timeCondition, engineState. If conditions fail, trigger is silently skipped."]
                    ] as [String: Any]
                ],
                [
                    "type": "webhook",
                    "fields": [
                        "token": ["type": "string", "required": true, "description": "Unique webhook token"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false],
                        "conditions": ["type": "array", "required": false,
                            "description": "Per-trigger guard conditions. Supports deviceState, timeCondition, engineState. If conditions fail, trigger is silently skipped."]
                    ] as [String: Any]
                ],
                [
                    "type": "automation",
                    "description": "Makes this automation callable by other automations via executeAutomation blocks.",
                    "fields": [
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false],
                        "conditions": ["type": "array", "required": false,
                            "description": "Per-trigger guard conditions. Supports deviceState, timeCondition, engineState. If conditions fail, trigger is silently skipped."]
                    ] as [String: Any]
                ]
            ] as [[String: Any]],
            "triggerConditions": [
                "description": "Condition types for deviceStateChange triggers",
                "types": [
                    ["type": "changed", "fields": [:] as [String: Any], "description": "Fires on any value change"],
                    ["type": "equals", "fields": ["value": "any"], "description": "Fires when value equals"],
                    ["type": "notEquals", "fields": ["value": "any"], "description": "Fires when value does not equal"],
                    ["type": "transitioned", "fields": [
                        "from": ["type": "any", "required": false],
                        "to": ["type": "any", "required": false]
                    ] as [String: Any], "description": "Fires on value transition. At least one of from/to required."],
                    ["type": "greaterThan", "fields": ["value": "number"]],
                    ["type": "lessThan", "fields": ["value": "number"]],
                    ["type": "greaterThanOrEqual", "fields": ["value": "number"]],
                    ["type": "lessThanOrEqual", "fields": ["value": "number"]]
                ] as [[String: Any]]
            ] as [String: Any],
            "scheduleTypes": [
                ["type": "once", "fields": ["date": ["type": "string", "format": "ISO8601"]]],
                ["type": "daily", "fields": ["time": ["type": "object", "format": "{hour: 0-23, minute: 0-59}"]]],
                ["type": "weekly", "fields": [
                    "time": ["type": "object", "format": "{hour: 0-23, minute: 0-59}"],
                    "days": ["type": "array", "description": "1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat"]
                ] as [String: Any]],
                ["type": "interval", "fields": ["seconds": ["type": "number"]]]
            ] as [[String: Any]],
            "blockTypes": [
                "actions": [
                    [
                        "block": "action", "type": "controlDevice",
                        "fields": [
                            "deviceId": ["type": "string", "required": true],
                            "deviceName": ["type": "string", "required": true],
                            "roomName": ["type": "string", "required": true],
                            "serviceId": ["type": "string", "required": false],
                            "characteristicId": ["type": "string", "required": true,
                                "description": "Stable characteristic ID from list_devices."],
                            "value": ["type": "any", "required": true,
                                "description": "Value to set. Also serves as the default fallback when valueRef is used."],
                            "valueRef": ["type": "object", "required": false,
                                "description": "Optional. Reference a global value: {\"type\":\"byName\",\"name\":\"my_value\"}. At runtime the global value is used; if deleted, falls back to the value field. IMPORTANT: The global value type must match the characteristic format — boolean globals for bool characteristics, number globals for numeric characteristics (uint8/uint16/uint32/uint64/int/float), string globals for string characteristics."],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "action", "type": "runScene",
                        "fields": [
                            "sceneId": ["type": "string", "required": true],
                            "sceneName": ["type": "string", "required": false],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "action", "type": "webhook",
                        "fields": [
                            "url": ["type": "string", "required": true],
                            "method": ["type": "string", "required": true, "values": ["GET", "POST", "PUT", "PATCH", "DELETE"]],
                            "headers": ["type": "object", "required": false],
                            "body": ["type": "any", "required": false],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "action", "type": "log",
                        "fields": [
                            "message": ["type": "string", "required": true],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "action", "type": "stateVariable",
                        "description": "Operate on global values (create, remove, set, increment, decrement, multiply, toggle, etc.)",
                        "fields": [
                            "operation": ["type": "object", "required": true, "description": "See stateVariableOperations"],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ]
                ] as [[String: Any]],
                "flowControl": [
                    [
                        "block": "flowControl", "type": "delay",
                        "fields": [
                            "seconds": ["type": "number", "required": true],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "waitForState",
                        "fields": [
                            "condition": ["type": "AutomationCondition", "required": true],
                            "timeoutSeconds": ["type": "number", "required": true],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "conditional",
                        "fields": [
                            "condition": ["type": "AutomationCondition", "required": true,
                                "description": "All condition types allowed here, including blockResult"],
                            "thenBlocks": ["type": "array", "required": true, "description": "Blocks to run if true"],
                            "elseBlocks": ["type": "array", "required": false, "description": "Blocks to run if false"],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "repeat",
                        "fields": [
                            "count": ["type": "integer", "required": true],
                            "blocks": ["type": "array", "required": true],
                            "delayBetweenSeconds": ["type": "number", "required": false],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "repeatWhile",
                        "fields": [
                            "condition": ["type": "AutomationCondition", "required": true,
                                "description": "No blockResult allowed here"],
                            "blocks": ["type": "array", "required": true],
                            "maxIterations": ["type": "integer", "required": true],
                            "delayBetweenSeconds": ["type": "number", "required": false],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "group",
                        "fields": [
                            "label": ["type": "string", "required": false],
                            "blocks": ["type": "array", "required": true],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "return",
                        "fields": [
                            "outcome": ["type": "string", "required": true, "values": ["success", "error", "cancelled"]],
                            "message": ["type": "string", "required": false],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "executeAutomation",
                        "fields": [
                            "targetAutomationId": ["type": "string", "required": true, "description": "UUID of target automation"],
                            "executionMode": ["type": "string", "required": true,
                                "values": ["inline", "parallel", "delegate"],
                                "description": "inline=wait, parallel=fire-and-continue, delegate=fire-and-stop-current"],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ]
                ] as [[String: Any]]
            ] as [String: Any],
            "conditionTypes": [
                "description": "AutomationCondition types used in execution guards, per-trigger guards, conditional blocks, waitForState, and repeatWhile.",
                "types": [
                    [
                        "type": "deviceState",
                        "fields": [
                            "deviceId": ["type": "string", "required": true],
                            "deviceName": ["type": "string", "required": true],
                            "roomName": ["type": "string", "required": true],
                            "serviceId": ["type": "string", "required": false],
                            "characteristicId": ["type": "string", "required": true,
                                "description": "Stable characteristic ID from list_devices."],
                            "comparison": ["type": "object", "required": true, "description": "See comparisonOperators"]
                        ] as [String: Any]
                    ],
                    [
                        "type": "timeCondition",
                        "fields": [
                            "mode": ["type": "string", "required": true,
                                "values": ["beforeSunrise", "afterSunrise", "beforeSunset", "afterSunset",
                                           "daytime", "nighttime", "timeRange"]],
                            "startTime": ["type": "object", "required": false,
                                "format": "TimePoint: {type:'fixed',hour:0-23,minute:0-59} or {type:'marker',marker:'midnight'|'noon'|'sunrise'|'sunset'}",
                                "description": "Required for timeRange. Supports fixed times or named markers. Legacy {hour,minute} without type field also accepted."],
                            "endTime": ["type": "object", "required": false,
                                "format": "TimePoint: {type:'fixed',hour:0-23,minute:0-59} or {type:'marker',marker:'midnight'|'noon'|'sunrise'|'sunset'}",
                                "description": "Required for timeRange. Supports fixed times or named markers. Legacy {hour,minute} without type field also accepted."]
                        ] as [String: Any]
                    ],
                    [
                        "type": "blockResult",
                        "restriction": "ONLY valid inside conditional block conditions. NOT allowed in execution guards, per-trigger guards, repeatWhile, or waitForState.",
                        "fields": [
                            "scope": ["type": "string", "required": true,
                                "values": ["specific", "all", "any"],
                                "description": "specific requires blockId of a previously-executed block"],
                            "blockId": ["type": "string", "required": false, "description": "Required when scope is 'specific'"],
                            "expectedStatus": ["type": "string", "required": true,
                                "values": ["success", "failure", "cancelled", "skipped", "conditionNotMet"]]
                        ] as [String: Any]
                    ],
                    [
                        "type": "engineState",
                        "description": "Compare a global value's current value. Use list_global_values to discover available values.",
                        "fields": [
                            "variableRef": ["type": "object", "required": true,
                                "description": "Reference: {\"type\":\"byName\",\"name\":\"my_counter\"}"],
                            "comparison": ["type": "object", "required": true,
                                "description": "ComparisonOperator. For booleans: equals/notEquals only. For strings: equals/notEquals. For numbers: all operators."],
                            "compareToStateRef": ["type": "object", "required": false,
                                "description": "Optional. When set, compare against another global value instead of a literal."],
                            "dynamicDateValue": ["type": "string", "required": false,
                                "description": "For datetime comparisons: a sentinel resolved at evaluation time. Values: '__now__', '__now-24h__', '__now+7d__', '__now-30m__', etc. Units: s (seconds), m (minutes), h (hours), d (days)."]
                        ] as [String: Any]
                    ],
                    [
                        "type": "and",
                        "fields": ["conditions": ["type": "array", "description": "Array of AutomationCondition objects"]]
                    ],
                    [
                        "type": "or",
                        "fields": ["conditions": ["type": "array", "description": "Array of AutomationCondition objects"]]
                    ],
                    [
                        "type": "not",
                        "fields": ["condition": ["type": "AutomationCondition", "description": "Single condition to negate"]]
                    ]
                ] as [[String: Any]]
            ] as [String: Any],
            "comparisonOperators": [
                "description": "Comparison types for deviceState and engineState conditions. Boolean: equals/notEquals. String: equals/notEquals/isEmpty/isNotEmpty/contains. Number: all numeric operators.",
                "types": [
                    ["type": "equals", "fields": ["value": "any"], "description": "All types"],
                    ["type": "notEquals", "fields": ["value": "any"], "description": "All types"],
                    ["type": "greaterThan", "fields": ["value": "number"], "description": "Numbers only"],
                    ["type": "lessThan", "fields": ["value": "number"], "description": "Numbers only"],
                    ["type": "greaterThanOrEqual", "fields": ["value": "number"], "description": "Numbers only"],
                    ["type": "lessThanOrEqual", "fields": ["value": "number"], "description": "Numbers only"],
                    ["type": "isEmpty", "fields": [:] as [String: Any], "description": "Strings only. No value field needed."],
                    ["type": "isNotEmpty", "fields": [:] as [String: Any], "description": "Strings only. No value field needed."],
                    ["type": "contains", "fields": ["value": "string"], "description": "Strings only. Case-insensitive substring match."]
                ] as [[String: Any]]
            ] as [String: Any],
            "stateVariableOperations": [
                "description": "Operations for the stateVariable action block. Use list_global_values to discover available values and their types.",
                "variableRef": "{\"type\":\"byName\",\"name\":\"value_name\"} — identifies the target global value",
                "operations": [
                    ["operation": "create", "fields": ["name": "string", "variableType": "number|string|boolean", "initialValue": "any"],
                        "description": "Create a new global value"],
                    ["operation": "remove", "fields": ["variableRef": "object"], "description": "Delete a global value"],
                    ["operation": "set", "fields": ["variableRef": "object", "value": "any"], "description": "Set value (any type)"],
                    ["operation": "increment", "fields": ["variableRef": "object", "by": "number"], "description": "Add to number value"],
                    ["operation": "decrement", "fields": ["variableRef": "object", "by": "number"], "description": "Subtract from number value"],
                    ["operation": "multiply", "fields": ["variableRef": "object", "by": "number"], "description": "Multiply number value"],
                    ["operation": "addState", "fields": ["variableRef": "object", "otherRef": "object"], "description": "Add another global value (numbers)"],
                    ["operation": "subtractState", "fields": ["variableRef": "object", "otherRef": "object"], "description": "Subtract another global value (numbers)"],
                    ["operation": "toggle", "fields": ["variableRef": "object"], "description": "Flip boolean value"],
                    ["operation": "andState", "fields": ["variableRef": "object", "otherRef": "object"], "description": "Boolean AND with another value"],
                    ["operation": "orState", "fields": ["variableRef": "object", "otherRef": "object"], "description": "Boolean OR with another value"],
                    ["operation": "notState", "fields": ["variableRef": "object"], "description": "Boolean NOT"],
                    ["operation": "setToNow", "fields": ["variableRef": "object"], "description": "Set a datetime global value to the current date/time"],
                    ["operation": "addTime", "fields": ["variableRef": "object", "amount": "number", "unit": "seconds|minutes|hours|days"], "description": "Add time to a datetime global value"],
                    ["operation": "subtractTime", "fields": ["variableRef": "object", "amount": "number", "unit": "seconds|minutes|hours|days"], "description": "Subtract time from a datetime global value"],
                    ["operation": "setFromCharacteristic", "fields": ["variableRef": "object", "deviceId": "string", "characteristicId": "string", "serviceId": "string (optional)"], "description": "Read a device characteristic's current value into a global value. The characteristic format must match the global value type: bool→boolean, uint8/uint16/uint32/uint64/int/float→number, string→string. Not usable with datetime."]
                ] as [[String: Any]]
            ] as [String: Any],
            "importantRules": [
                "Always include deviceName and roomName alongside deviceId in triggers, conditions, and blocks.",
                "blockResult conditions are ONLY valid inside conditional block conditions.",
                "Guard-level conditions support: deviceState, timeCondition, engineState, and/or/not.",
                "repeatWhile conditions support: deviceState, timeCondition, engineState, and/or/not (no blockResult).",
                "Set continueOnError=true on the automation when using blockResult conditions.",
                "Use list_devices to discover device IDs, service IDs, and characteristic IDs.",
                "Use characteristic IDs (not types) in triggers, conditions, and controlDevice actions.",
                "Use list_global_values to discover global values before using stateVariable blocks or engineState conditions.",
                "Global value names are lowercase identifiers (a-z, 0-9, _). Use stateVariable blocks to create/modify them.",
                "For engineState conditions: boolean values support equals/notEquals; string values support equals/notEquals/isEmpty/isNotEmpty/contains; number values support all numeric comparison operators.",
                "isEmpty and isNotEmpty comparisons have no value field. contains takes a string value for case-insensitive substring matching.",
                "Global value and characteristic type matching: when using valueRef in controlDevice or setFromCharacteristic in stateVariable, types MUST match. Boolean globals only with bool characteristics. Number globals only with numeric characteristics (uint8, uint16, uint32, uint64, int, float). String globals only with string characteristics. Datetime globals cannot be used with characteristics. Use list_devices to check characteristic formats and list_global_values to check global value types before linking them.",
                "Datetime global values: store ISO 8601 date strings. Supported operations: set (ISO 8601 string), setToNow, addTime/subtractTime (with amount and unit: seconds/minutes/hours/days). For engineState conditions, datetime values support equals/notEquals/greaterThan (after)/lessThan (before)/greaterThanOrEqual/lessThanOrEqual. Use dynamicDateValue for runtime-resolved comparisons: '__now__' (current server time), '__now-24h__' (24 hours ago), '__now+7d__' (7 days from now), '__now-30m__' (30 minutes ago). Units: s/m/h/d. The dynamicDateValue field is resolved at evaluation time, not save time."
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return nil
    }()

    private func handleGetAutomationSchema(id: JSONRPCId?) -> JSONRPCResponse {
        if let cached = Self.cachedAutomationSchemaJSON {
            return toolResult(text: cached, id: id)
        }
        return toolResult(text: "Failed to encode automation schema", isError: true, id: id)
    }

    private func handleListRooms(id: JSONRPCId?) async -> JSONRPCResponse {
        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }

        var lines: [String] = []
        for group in groups {
            lines.append("- \(group.roomName) (\(group.devices.count) device\(group.devices.count == 1 ? "" : "s"))")
        }

        if lines.isEmpty {
            lines.append("No rooms found.")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleGetDevicesByType(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let types = arguments["types"] as? [String] else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: types (array of strings)"
            )
        }

        let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
        
        // Filter devices that have at least one service matching one of the requested types
        let matchingDevices = allDevices.filter { device in
            device.services.contains { service in
                types.contains { type in
                    service.type.localizedCaseInsensitiveContains(type) ||
                    service.displayName.localizedCaseInsensitiveContains(type)
                }
            }
        }

        let filteredDevices = stableDevices(matchingDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }
        return toolResult(encoding: restDevices, id: id)
    }

    private func handleGetLogs(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        // All log types are now in the unified LoggingService.
        var logs = await loggingService.getLogs()
        let allCount = logs.count

        // Category filtering
        if let categoryStrings = arguments["categories"] as? [String] {
            let categories = categoryStrings.compactMap { LogCategory(rawValue: $0) }
            if !categories.isEmpty {
                let categorySet = Set(categories)
                logs = logs.filter { categorySet.contains($0.category) }
            }
        }

        // Device name filtering
        if let deviceName = arguments["device_name"] as? String {
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

        if let dateString = arguments["date"] as? String {
            guard let date = dateOnly.date(from: dateString) ?? iso8601.date(from: dateString) ?? iso8601NoFrac.date(from: dateString) else {
                return toolResult(text: "Invalid date format: '\(dateString)'. Use 'yyyy-MM-dd' or ISO 8601.", isError: true, id: id)
            }
            let startOfDay = Calendar.current.startOfDay(for: date)
            guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                return toolResult(text: "Failed to compute date range.", isError: true, id: id)
            }
            logs = logs.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        } else {
            if let fromString = arguments["from"] as? String {
                guard let fromDate = dateOnly.date(from: fromString) ?? iso8601.date(from: fromString) ?? iso8601NoFrac.date(from: fromString) else {
                    return toolResult(text: "Invalid 'from' date format: '\(fromString)'. Use 'yyyy-MM-dd' or ISO 8601.", isError: true, id: id)
                }
                logs = logs.filter { $0.timestamp >= fromDate }
            }
            if let toString = arguments["to"] as? String {
                guard let toDate = dateOnly.date(from: toString) ?? iso8601.date(from: toString) ?? iso8601NoFrac.date(from: toString) else {
                    return toolResult(text: "Invalid 'to' date format: '\(toString)'. Use 'yyyy-MM-dd' or ISO 8601.", isError: true, id: id)
                }
                logs = logs.filter { $0.timestamp <= toDate }
            }
        }

        // Pagination
        let total = logs.count
        let offset = arguments["offset"] as? Int ?? 0
        let limit = arguments["limit"] as? Int ?? 50
        logs = Array(logs.dropFirst(offset).prefix(limit))

        // Format output
        var lines: [String] = []
        lines.append("Showing \(offset + 1)-\(offset + logs.count) of \(total) logs (filtered from \(allCount) total)")

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        for log in logs {
            let time = formatter.string(from: log.timestamp)
            let cat = log.category.rawValue
            let line: String
            switch log.payload {
            case .stateChange(let p):
                let charName = CharacteristicTypes.displayName(for: p.characteristicType)
                let oldVal = p.oldValue.map { CharacteristicTypes.formatValue($0.value, characteristicType: p.characteristicType) } ?? "nil"
                let newVal = p.newValue.map { CharacteristicTypes.formatValue($0.value, characteristicType: p.characteristicType) } ?? "nil"
                let serviceLabel = p.serviceName.map { " [\($0)]" } ?? ""
                line = "[\(time)] \(p.deviceName)\(serviceLabel) — \(charName): \(oldVal) → \(newVal) (\(cat))"
            case .webhookCall(let p), .webhookError(let p):
                let charName = CharacteristicTypes.displayName(for: p.characteristicType)
                line = "[\(time)] Webhook \(p.deviceName) — \(charName): \(p.summary) → \(p.result) (\(cat))"
            case .mcpCall(let p):
                line = "[\(time)] MCP \(p.method) — \(p.result) (\(cat))"
            case .restCall(let p):
                line = "[\(time)] REST \(p.method) — \(p.result) (\(cat))"
            case .serverError(let p):
                line = "[\(time)] Server Error: \(p.errorDetails) (\(cat))"
            case .automationExecution(let e), .automationError(let e):
                let trigger = e.triggerEvent?.triggerDescription ?? ""
                let triggerSuffix = trigger.isEmpty ? "" : " ← \(trigger)"
                line = "[\(time)] Automation \"\(e.automationName)\" — \(e.status.rawValue)\(triggerSuffix) (\(cat))"
            case .sceneExecution(let p), .sceneError(let p):
                let status = p.succeeded ? "succeeded" : "failed"
                let detail = p.errorDetails ?? p.summary ?? ""
                let detailSuffix = detail.isEmpty ? "" : " — \(detail)"
                line = "[\(time)] Scene \"\(p.sceneName)\" \(status)\(detailSuffix) (\(cat))"
            case .backupRestore(let p):
                line = "[\(time)] Backup \(p.subtype) — \(p.summary) (\(cat))"
            case .aiInteraction(let p), .aiInteractionError(let p):
                let status = p.errorMessage != nil ? "error" : "ok"
                line = "[\(time)] AI \(p.operation) (\(p.provider)/\(p.model)) — \(String(format: "%.1fs", p.durationSeconds)) \(status) (\(cat))"
            }
            lines.append(line)
        }

        if logs.isEmpty {
            lines.append("No logs found.")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleGetDeviceDetails(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let deviceIds = arguments["device_ids"] as? [String], !deviceIds.isEmpty else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: device_ids (array of strings)"
            )
        }

        var restDevices: [RESTDevice] = []
        var notFound: [String] = []

        for deviceId in deviceIds {
            if let device = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) },
               let filteredDevice = stableDevices([device]).first {
                restDevices.append(RESTDevice.from(filteredDevice))
            } else {
                notFound.append(deviceId)
            }
        }

        guard let jsonData = try? JSONEncoder.iso8601.encode(restDevices),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return toolResult(text: "Failed to encode device data", isError: true, id: id)
        }

        var responseText = jsonString
        if !notFound.isEmpty {
            responseText += "\n\nNote: The following device IDs were not found: \(notFound.joined(separator: ", "))"
        }

        return toolResult(text: responseText, id: id)
    }

    // MARK: - Scene Tool Handlers

    private func handleListScenes(id: JSONRPCId?) async -> JSONRPCResponse {
        let scenes = stableScenes(await MainActor.run { homeKitManager.getAllScenes() })

        var lines: [String] = []
        for scene in scenes {
            let status = scene.isExecuting ? " [executing]" : ""
            lines.append("- \(scene.name) [\(scene.type)]\(status) (\(scene.actions.count) action\(scene.actions.count == 1 ? "" : "s")) (id: \(scene.id))")
            for action in scene.actions {
                let val = CharacteristicTypes.formatValue(action.targetValue.value, characteristicType: CharacteristicTypes.characteristicType(forName: action.characteristicType) ?? action.characteristicType)
                lines.append("    \(action.deviceName) — \(action.characteristicType): \(val)")
            }
        }

        if lines.isEmpty {
            lines.append("No HomeKit scenes found.")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleExecuteScene(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let sceneId = arguments["scene_id"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: scene_id"
            )
        }

        do {
            try await homeKitManager.executeScene(id: sceneId)
            let scene = await MainActor.run { homeKitManager.getScene(id: sceneId) }
            let sceneName = scene?.name ?? sceneId
            return toolResult(text: "Successfully executed scene: \(sceneName)", id: id)
        } catch {
            AppLogger.scene.error("Scene execution failed via MCP: \(error.localizedDescription)")
            return toolResult(text: "Failed to execute scene: \(error.localizedDescription)", isError: true, id: id)
        }
    }

    // MARK: - Automation Tool Handlers

    private func handleListAutomations(id: JSONRPCId?) async -> JSONRPCResponse {
        let automations = await automationStorageService.getAllAutomations()

        if automations.isEmpty {
            return toolResult(text: "No automations found. Use create_automation to create one.", id: id)
        }

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        for automation in automations {
            let status = automation.isEnabled ? "✓ enabled" : "✗ disabled"
            let triggers = "\(automation.triggers.count) trigger\(automation.triggers.count == 1 ? "" : "s")"
            let blocks = "\(automation.blocks.count) block\(automation.blocks.count == 1 ? "" : "s")"
            let execs = "executions: \(automation.metadata.totalExecutions)"
            let lastTriggered = automation.metadata.lastTriggeredAt.map { "last: \(formatter.string(from: $0))" } ?? "never triggered"
            let failures = automation.metadata.consecutiveFailures > 0 ? " ⚠ \(automation.metadata.consecutiveFailures) consecutive failures" : ""

            lines.append("- **\(automation.name)** [\(status)] (id: \(automation.id.uuidString))")
            if let desc = automation.description {
                lines.append("  \(desc)")
            }
            lines.append("  \(triggers), \(blocks) | \(execs), \(lastTriggered)\(failures)")
            lines.append("")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleGetAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let automationIdStr = arguments["automation_id"] as? String,
              let automationId = UUID(uuidString: automationIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid automation_id (must be a UUID)")
        }

        guard let automation = await automationStorageService.getAutomation(id: automationId) else {
            return toolResult(text: "Automation not found: \(automationIdStr)", isError: true, id: id)
        }

        return toolResult(encoding: automation, id: id)
    }

    private func handleCreateAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let automationDict = arguments["automation"] as? [String: Any] else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: automation (JSON object)")
        }

        do {
            let automation = try parseAutomationFromDict(automationDict)

            // Validate characteristic permissions
            if let validationError = await validateAutomationPermissions(automation) {
                return toolResult(text: validationError, isError: true, id: id)
            }

            let created = await automationStorageService.createAutomation(automation)
            return toolResult(text: "Automation created successfully.\nID: \(created.id.uuidString)\nName: \(created.name)", id: id)
        } catch {
            AppLogger.general.error("Automation creation failed: \(error.localizedDescription)")
            return toolResult(text: "Failed to create automation. Check server logs for details.", isError: true, id: id)
        }
    }

    private func handleUpdateAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let automationIdStr = arguments["automation_id"] as? String,
              let automationId = UUID(uuidString: automationIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid automation_id (must be a UUID)")
        }

        guard let updates = arguments["automation"] as? [String: Any] else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: automation (JSON object)")
        }

        guard let existing = await automationStorageService.getAutomation(id: automationId) else {
            return toolResult(text: "Automation not found: \(automationIdStr)", isError: true, id: id)
        }

        do {
            // Merge: start from existing, apply updates
            var merged = existing
            if let name = updates["name"] as? String { merged.name = name }
            if let desc = updates["description"] as? String { merged.description = desc }
            if let enabled = updates["isEnabled"] as? Bool { merged.isEnabled = enabled }
            if let coe = updates["continueOnError"] as? Bool { merged.continueOnError = coe }
            if let policyStr = updates["retriggerPolicy"] as? String,
               let policy = ConcurrentExecutionPolicy(rawValue: policyStr) { merged.retriggerPolicy = policy }

            // For triggers/conditions/blocks, re-parse from JSON if provided
            if let triggersArray = updates["triggers"] {
                let data = try JSONSerialization.data(withJSONObject: triggersArray)
                merged.triggers = try JSONDecoder.iso8601.decode([AutomationTrigger].self, from: data)
            }
            if let conditionsArray = updates["conditions"] {
                let data = try JSONSerialization.data(withJSONObject: conditionsArray)
                merged.conditions = try JSONDecoder.iso8601.decode([AutomationCondition].self, from: data)
            }
            if let blocksArray = updates["blocks"] {
                let data = try JSONSerialization.data(withJSONObject: blocksArray)
                merged.blocks = try JSONDecoder.iso8601.decode([AutomationBlock].self, from: data)
            }

            // Validate characteristic permissions
            if let validationError = await validateAutomationPermissions(merged) {
                return toolResult(text: validationError, isError: true, id: id)
            }

            let updated = await automationStorageService.updateAutomation(id: automationId) { automation in
                automation.name = merged.name
                automation.description = merged.description
                automation.isEnabled = merged.isEnabled
                automation.continueOnError = merged.continueOnError
                automation.retriggerPolicy = merged.retriggerPolicy
                automation.triggers = merged.triggers
                automation.conditions = merged.conditions
                automation.blocks = merged.blocks
            }

            if let updated {
                return toolResult(text: "Automation updated successfully.\nID: \(updated.id.uuidString)\nName: \(updated.name)", id: id)
            } else {
                return toolResult(text: "Failed to update automation", isError: true, id: id)
            }
        } catch {
            AppLogger.general.error("Automation update parse failed: \(error.localizedDescription)")
            return toolResult(text: "Failed to parse automation update. Check server logs for details.", isError: true, id: id)
        }
    }

    private func handleDeleteAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let automationIdStr = arguments["automation_id"] as? String,
              let automationId = UUID(uuidString: automationIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid automation_id (must be a UUID)")
        }

        let deleted = await automationStorageService.deleteAutomation(id: automationId)
        if deleted {
            return toolResult(text: "Automation deleted: \(automationIdStr)", id: id)
        } else {
            return toolResult(text: "Automation not found: \(automationIdStr)", isError: true, id: id)
        }
    }

    private func handleEnableAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let automationIdStr = arguments["automation_id"] as? String,
              let automationId = UUID(uuidString: automationIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid automation_id (must be a UUID)")
        }

        guard let enabled = arguments["enabled"] as? Bool else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: enabled (boolean)")
        }

        let updated = await automationStorageService.updateAutomation(id: automationId) { automation in
            automation.isEnabled = enabled
        }

        if let updated {
            return toolResult(text: "Automation '\(updated.name)' is now \(enabled ? "enabled" : "disabled")", id: id)
        } else {
            return toolResult(text: "Automation not found: \(automationIdStr)", isError: true, id: id)
        }
    }

    private func handleGetAutomationLogs(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        let limit = arguments["limit"] as? Int ?? 20

        var logs: [AutomationExecutionLog]
        if let automationIdStr = arguments["automation_id"] as? String,
           let automationId = UUID(uuidString: automationIdStr) {
            logs = await loggingService.getLogs(forAutomationId: automationId).compactMap(\.automationExecution)
        } else {
            logs = await loggingService.getLogs().compactMap(\.automationExecution)
        }

        logs = Array(logs.prefix(limit))

        if logs.isEmpty {
            return toolResult(text: "No automation execution logs found.", id: id)
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        var lines: [String] = []
        for log in logs {
            let duration: String
            if let completed = log.completedAt {
                let ms = completed.timeIntervalSince(log.triggeredAt) * 1000
                duration = String(format: "%.0fms", ms)
            } else {
                duration = "running"
            }

            lines.append("[\(formatter.string(from: log.triggeredAt))] \(log.automationName) — \(log.status.rawValue) (\(duration))")

            if let trigger = log.triggerEvent {
                let triggerLabel = trigger.triggerDescription ?? "\(trigger.deviceName ?? trigger.deviceId ?? "unknown") \(trigger.characteristicName ?? "")"
                lines.append("  Trigger: \(triggerLabel)")
            }

            if let error = log.errorMessage {
                lines.append("  Error: \(error)")
            }

            let blockSummary = log.blockResults.map { "\($0.blockType):\($0.status.rawValue)" }.joined(separator: ", ")
            if !blockSummary.isEmpty {
                lines.append("  Blocks: \(blockSummary)")
            }
            lines.append("")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleTriggerAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let automationIdStr = arguments["automation_id"] as? String,
              let automationId = UUID(uuidString: automationIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid automation_id (must be a UUID)")
        }

        let result = await automationEngine.scheduleTrigger(id: automationId)
        return toolResult(text: result.message, isError: !result.isAccepted, id: id)
    }

    private func handleImproveAutomation(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let aiService = aiAutomationService else {
            return toolResult(text: "AI service is not configured. Set up an AI provider in Settings.", isError: true, id: id)
        }

        guard let automationIdStr = arguments["automation_id"] as? String,
              let automationId = UUID(uuidString: automationIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid automation_id (must be a UUID)")
        }

        guard let existing = await automationStorageService.getAutomation(id: automationId) else {
            return toolResult(text: "Automation not found: \(automationIdStr)", isError: true, id: id)
        }

        let prompt = arguments["prompt"] as? String
        let defaultPrompt = "Review this automation and suggest improvements. Fix any labels that don't match their configuration. Optimize the structure if possible."
        let feedback = (prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? defaultPrompt : prompt!

        do {
            let improved = try await aiService.refineAutomation(existing, feedback: feedback)
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

            let data = try JSONEncoder.iso8601Pretty.encode(result)
            let jsonString = String(data: data, encoding: .utf8) ?? "{}"
            return toolResult(text: "Improved automation (NOT saved yet). Review and use update_automation to apply:\n\n\(jsonString)", id: id)
        } catch let error as AIAutomationError {
            return toolResult(text: "AI improvement failed: \(error.errorDescription ?? error.localizedDescription)", isError: true, id: id)
        } catch {
            return toolResult(text: "Unexpected error: \(error.localizedDescription)", isError: true, id: id)
        }
    }

    // MARK: - Automation JSON Parser

    /// Parses a raw [String: Any] dictionary into a Automation struct by serializing to JSON and decoding.
    private func parseAutomationFromDict(_ dict: [String: Any]) throws -> Automation {
        // Build a complete automation dict with defaults
        var automationDict = dict

        // Set defaults if not provided
        if automationDict["id"] == nil {
            automationDict["id"] = UUID().uuidString
        }
        if automationDict["isEnabled"] == nil {
            // Check for "enabled" alias
            if let enabled = automationDict["enabled"] as? Bool {
                automationDict["isEnabled"] = enabled
                automationDict.removeValue(forKey: "enabled")
            } else {
                automationDict["isEnabled"] = true
            }
        }
        if automationDict["continueOnError"] == nil {
            automationDict["continueOnError"] = false
        }
        if automationDict["triggers"] == nil {
            automationDict["triggers"] = [] as [[String: Any]]
        }
        if automationDict["blocks"] == nil {
            automationDict["blocks"] = [] as [[String: Any]]
        }

        let now = ISO8601DateFormatter().string(from: Date())
        if automationDict["createdAt"] == nil {
            automationDict["createdAt"] = now
        }
        if automationDict["updatedAt"] == nil {
            automationDict["updatedAt"] = now
        }

        // Provide default metadata if not present
        if automationDict["metadata"] == nil {
            automationDict["metadata"] = [
                "totalExecutions": 0,
                "consecutiveFailures": 0
            ] as [String: Any]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: automationDict, options: [])
        return try JSONDecoder.iso8601.decode(Automation.self, from: jsonData)
    }

    // MARK: - Automation Permission Validation

    /// Validates that automation triggers and blocks reference characteristics with the required permissions.
    /// - deviceStateChange triggers require "notify" permission
    /// - controlDevice actions require "write" permission
    /// Returns nil if valid, or an error message string if invalid.
    func validateAutomationPermissions(_ automation: Automation) async -> String? {
        // Use registry-proxied devices: stable IDs and effective permissions baked in
        let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
        let registryDevices = stableDevices(allDevices)
        let deviceMap = Dictionary(uniqueKeysWithValues: registryDevices.map { ($0.id, $0) })

        // Validate triggers
        for (index, trigger) in automation.triggers.enumerated() {
            if case .deviceStateChange(let t) = trigger {
                if let error = checkCharacteristicPermission(
                    deviceId: t.deviceId, characteristicId: t.characteristicId,
                    requiredPermission: "notify", context: "Trigger \(index + 1)",
                    deviceMap: deviceMap
                ) {
                    return error
                }
            }
        }

        // Validate blocks (recursive)
        if let error = validateBlockPermissions(automation.blocks, deviceMap: deviceMap) {
            return error
        }

        return nil
    }

    /// Recursively validates block permissions.
    private func validateBlockPermissions(_ blocks: [AutomationBlock], deviceMap: [String: DeviceModel]) -> String? {
        for block in blocks {
            switch block {
            case .action(let action, _):
                if case .controlDevice(let ctrl) = action {
                    if let error = checkCharacteristicPermission(
                        deviceId: ctrl.deviceId, characteristicId: ctrl.characteristicId,
                        requiredPermission: "write", context: "Control Device block",
                        deviceMap: deviceMap
                    ) {
                        return error
                    }
                }
            case .flowControl(let fc, _):
                // Recurse into nested blocks
                switch fc {
                case .conditional(let c):
                    if let error = validateBlockPermissions(c.thenBlocks, deviceMap: deviceMap) { return error }
                    if let error = validateBlockPermissions(c.elseBlocks ?? [], deviceMap: deviceMap) { return error }
                case .repeat(let r):
                    if let error = validateBlockPermissions(r.blocks, deviceMap: deviceMap) { return error }
                case .repeatWhile(let r):
                    if let error = validateBlockPermissions(r.blocks, deviceMap: deviceMap) { return error }
                case .group(let g):
                    if let error = validateBlockPermissions(g.blocks, deviceMap: deviceMap) { return error }
                default:
                    break
                }
            }
        }
        return nil
    }

    /// Checks if a characteristic has the required permission.
    private func checkCharacteristicPermission(
        deviceId: String, characteristicId: String,
        requiredPermission: String, context: String,
        deviceMap: [String: DeviceModel]
    ) -> String? {
        guard let device = deviceMap[deviceId] else {
            return "\(context): device '\(deviceId)' not found or not enabled."
        }
        for service in device.services {
            if let char = service.characteristics.first(where: { $0.id == characteristicId }) {
                if !char.permissions.contains(requiredPermission) {
                    let charName = CharacteristicTypes.displayName(for: char.type)
                    return "\(context): characteristic '\(charName)' on device '\(device.name)' does not have '\(requiredPermission)' permission (has: \(char.permissions.joined(separator: ", "))). " +
                        (requiredPermission == "notify"
                         ? "Device state change triggers require characteristics that are observed."
                         : "Control device actions require writable characteristics.")
                }
                return nil // Found and has permission
            }
        }
        return "\(context): characteristic '\(characteristicId)' not found on device '\(device.name)'."
    }

    // MARK: - Metadata Hints

    /// Builds an inline metadata hint string for a characteristic, e.g. ` (int, 0–100, %)`.
    /// Only shown for writable characteristics.
    private static func compactPermissions(_ permissions: [String]) -> String {
        var parts: [String] = []
        if permissions.contains("read") { parts.append("r") }
        if permissions.contains("write") { parts.append("w") }
        if permissions.contains("notify") { parts.append("n") }
        return parts.joined(separator: "/")
    }

    private static func metadataHint(for char: CharacteristicModel) -> String {
        // Enum-style characteristics with valid values
        if let validValues = char.validValues, !validValues.isEmpty {
            let options = CharacteristicInputConfig.buildPickerOptions(for: char.type, values: validValues)
            let labels = options.map(\.label).joined(separator: "|")
            return " (enum: \(labels))"
        }

        var parts: [String] = []
        parts.append(char.format)

        if let min = char.minValue, let max = char.maxValue {
            let minStr = min == min.rounded() ? "\(Int(min))" : "\(min)"
            let maxStr = max == max.rounded() ? "\(Int(max))" : "\(max)"
            parts.append("\(minStr)–\(maxStr)")
        }

        if let units = char.units {
            parts.append(units)
        }

        return " (\(parts.joined(separator: ", ")))"
    }

    // MARK: - Global Value Tool Handlers

    private func resolveStateVariable(arguments: [String: Any]) async -> StateVariable? {
        guard let storage = stateVariableStorage else { return nil }
        if let idStr = arguments["variable_id"] as? String, let id = UUID(uuidString: idStr) {
            return await storage.get(id: id)
        }
        if let name = arguments["name"] as? String {
            return await storage.getByName(name)
        }
        return nil
    }

    private func handleListStateVariables(id: JSONRPCId?) async -> JSONRPCResponse {
        guard let storage = stateVariableStorage else {
            return toolResult(text: "Global value storage not available.", isError: true, id: id)
        }
        let variables = await storage.getAll()
        if variables.isEmpty {
            return toolResult(text: "No global values found. Use create_global_value to create one.", id: id)
        }
        return toolResult(encoding: variables, id: id)
    }

    private func handleGetStateVariable(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let variable = await resolveStateVariable(arguments: arguments) else {
            return toolResult(text: "Global value not found. Provide a valid variable_id or name.", isError: true, id: id)
        }
        return toolResult(encoding: variable, id: id)
    }

    private func handleCreateStateVariable(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let storage = stateVariableStorage else {
            return toolResult(text: "Global value storage not available.", isError: true, id: id)
        }
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return toolResult(text: "Missing required argument: name", isError: true, id: id)
        }
        guard let typeStr = arguments["type"] as? String,
              let varType = StateVariableType(rawValue: typeStr) else {
            return toolResult(text: "Missing or invalid type. Must be: number, string, or boolean", isError: true, id: id)
        }
        guard let rawValue = arguments["value"] else {
            return toolResult(text: "Missing required argument: value", isError: true, id: id)
        }
        if await storage.getByName(name) != nil {
            return toolResult(text: "A global value named '\(name)' already exists.", isError: true, id: id)
        }
        let variable = StateVariable(name: name, type: varType, value: AnyCodable(rawValue))
        let created = await storage.create(variable)
        return toolResult(text: "Global value created.\nID: \(created.id.uuidString)\nName: \(created.name)\nType: \(created.type.rawValue)\nValue: \(created.displayValue)", id: id)
    }

    private func handleUpdateStateVariable(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let storage = stateVariableStorage else {
            return toolResult(text: "Global value storage not available.", isError: true, id: id)
        }
        guard let variable = await resolveStateVariable(arguments: arguments) else {
            return toolResult(text: "Global value not found. Provide a valid variable_id or name.", isError: true, id: id)
        }
        guard let rawValue = arguments["value"] else {
            return toolResult(text: "Missing required argument: value", isError: true, id: id)
        }
        guard let updated = await storage.update(id: variable.id, value: AnyCodable(rawValue)) else {
            return toolResult(text: "Failed to update global value.", isError: true, id: id)
        }
        return toolResult(text: "Global value updated.\nID: \(updated.id.uuidString)\nName: \(updated.name)\nValue: \(updated.displayValue)", id: id)
    }

    private func handleDeleteStateVariable(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let storage = stateVariableStorage else {
            return toolResult(text: "Global value storage not available.", isError: true, id: id)
        }
        guard let variable = await resolveStateVariable(arguments: arguments) else {
            return toolResult(text: "Global value not found. Provide a valid variable_id or name.", isError: true, id: id)
        }
        let deleted = await storage.delete(id: variable.id)
        if deleted {
            return toolResult(text: "Global value '\(variable.name)' deleted.", id: id)
        } else {
            return toolResult(text: "Failed to delete global value.", isError: true, id: id)
        }
    }

    // MARK: - Tool Result Builders

    private func toolResult(text: String, isError: Bool = false, id: JSONRPCId?) -> JSONRPCResponse {
        let content: [[String: Any]] = [["type": "text", "text": text]]
        let result: [String: Any] = ["content": content, "isError": isError]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
    }

    private func toolResult<T: Encodable>(encoding value: T, isError: Bool = false, id: JSONRPCId?) -> JSONRPCResponse {
        guard let jsonData = try? JSONEncoder.iso8601.encode(value),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return toolResult(text: "Failed to encode response data", isError: true, id: id)
        }
        return toolResult(text: jsonString, isError: isError, id: id)
    }

    // MARK: - MCP Logging Helpers

    private func logMCPCall(method: String, request: String, response: String,
                            fullRequest: JSONRPCRequest? = nil,
                            fullResponse: JSONRPCResponse? = nil) async {
        guard storage.readLoggingEnabled(), storage.readMcpLoggingEnabled() else { return }

        var detailedReq: String?
        var detailedResp: String?

        if storage.readMcpDetailedLogsEnabled() {
            if let fullRequest, let data = try? JSONEncoder.iso8601.encode(fullRequest) {
                detailedReq = String(data: data, encoding: .utf8)
            }
            if let fullResponse, let data = try? JSONEncoder.iso8601.encode(fullResponse) {
                detailedResp = String(data: data, encoding: .utf8)
            }
        }

        let entry = StateChangeLog.mcpCall(
            method: method,
            summary: request,
            result: response,
            detailedRequest: detailedReq,
            detailedResponse: detailedResp
        )
        await loggingService.logEntry(entry)
    }

    private func summarizeRequest(_ request: JSONRPCRequest) -> String {
        var parts = ["method: \(request.method)"]
        if let id = request.id {
            switch id {
            case .int(let v): parts.append("id: \(v)")
            case .string(let v): parts.append("id: \(v)")
            }
        }
        if let params = request.params,
           let dict = params.value as? [String: Any] {
            // For tools/call, show the tool name and arguments
            if let toolName = dict["name"] as? String {
                parts.append("tool: \(toolName)")
            }
            if let args = dict["arguments"] as? [String: Any] {
                let argSummary = args.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                let truncated = argSummary.prefix(200)
                parts.append("args: {\(truncated)}")
            }
            // For resources/read, show the URI
            if let uri = dict["uri"] as? String {
                parts.append("uri: \(uri)")
            }
        }
        return parts.joined(separator: " | ")
    }

    private func summarizeResponse(_ response: JSONRPCResponse) -> String {
        if let error = response.error {
            return "ERROR [\(error.code)]: \(error.message)"
        }
        if let result = response.result,
           let dict = result.value as? [String: Any] {
            // For tool call results, show isError and truncated content
            if let isError = dict["isError"] as? Bool,
               let content = dict["content"] as? [[String: Any]],
               let firstText = content.first?["text"] as? String {
                let truncated = String(firstText.prefix(300))
                return "isError: \(isError) | \(truncated)"
            }
            // For other responses, show top-level keys
            let keys = dict.keys.sorted().joined(separator: ", ")
            return "keys: [\(keys)]"
        }
        return "empty result"
    }
}

// MARK: - Parameter Extraction Helpers

extension MCPRequestHandler {
    /// Typed parameter extractor for MCP tool arguments.
    /// Replaces the 28+ repeated `guard let x = args["key"] as? T else { return errorResponse }` patterns.
    ///
    /// Usage:
    /// ```swift
    /// let deviceId: String = try required("device_id", from: arguments)
    /// ```
    func required<T>(_ key: String, from args: [String: Any]) throws -> T {
        guard let raw = args[key] else {
            throw MCPParameterError.missing(key: key, expectedType: String(describing: T.self))
        }
        guard let typed = raw as? T else {
            throw MCPParameterError.typeMismatch(key: key, expectedType: String(describing: T.self), actualType: String(describing: type(of: raw)))
        }
        return typed
    }

    /// Optional typed extractor — returns nil if the key is absent; throws if present but wrong type.
    func optional<T>(_ key: String, from args: [String: Any]) throws -> T? {
        guard let raw = args[key] else { return nil }
        guard let typed = raw as? T else {
            throw MCPParameterError.typeMismatch(key: key, expectedType: String(describing: T.self), actualType: String(describing: type(of: raw)))
        }
        return typed
    }
}

/// Parameter extraction errors for MCP tool handlers.
enum MCPParameterError: Error, LocalizedError {
    case missing(key: String, expectedType: String)
    case typeMismatch(key: String, expectedType: String, actualType: String)

    var errorDescription: String? {
        switch self {
        case .missing(let key, let type):
            return "Missing required parameter '\(key)' (expected \(type))"
        case .typeMismatch(let key, let expected, let actual):
            return "Parameter '\(key)' has wrong type: expected \(expected), got \(actual)"
        }
    }
}
