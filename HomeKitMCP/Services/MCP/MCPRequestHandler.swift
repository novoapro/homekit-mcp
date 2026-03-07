import Foundation
import HomeKit

/// Handles MCP JSON-RPC method dispatch and builds responses.
/// All stored properties are immutable (`let`), making this class safe to share across isolation domains.
final class MCPRequestHandler: Sendable {
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let storage: StorageService
    private let workflowStorageService: WorkflowStorageService
    private let workflowEngine: WorkflowEngine
    private let registry: DeviceRegistryService?

    init(homeKitManager: HomeKitManager, loggingService: LoggingService, storage: StorageService,
         workflowStorageService: WorkflowStorageService, workflowEngine: WorkflowEngine,
         registry: DeviceRegistryService? = nil) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.storage = storage
        self.workflowStorageService = workflowStorageService
        self.workflowEngine = workflowEngine
        self.registry = registry
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
    private func isCharacteristicExposed(deviceId: String, characteristicType: String, serviceId: String?) async -> Bool {
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType

        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        guard let device else {
            return false
        }

        let targetServices: [ServiceModel]
        if let serviceId {
            targetServices = device.services.filter { $0.id == serviceId }
        } else {
            targetServices = device.services
        }

        for service in targetServices {
            for characteristic in service.characteristics where characteristic.type == resolvedType {
                let settings = registry?.readCharacteristicSettings(forHomeKitCharId: characteristic.id)
                if settings?.enabled ?? true {
                    return true
                }
            }
        }
        return false
    }

    /// Workflow tool names for guard checks when workflows are disabled.
    private static let workflowToolNames: Set<String> = [
        "list_workflows", "get_workflow", "create_workflow", "update_workflow",
        "delete_workflow", "enable_workflow", "get_workflow_logs",
        "trigger_workflow", "trigger_workflow_webhook"
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
        if storage.readWorkflowsEnabled() {
            tools += MCPToolDefinitions.workflowTools
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

        // Block workflow tools when workflows are globally disabled
        if Self.workflowToolNames.contains(toolName) && !storage.readWorkflowsEnabled() {
            return toolResult(
                text: "Workflows are disabled. Enable them in Settings to use workflow tools.",
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
        case "get_device":
            return await handleGetDevice(id: id, arguments: arguments)
        case "control_device":
            return await handleControlDevice(id: id, arguments: arguments)
        case "list_rooms":
            return await handleListRooms(id: id)
        case "get_room_devices":
            return await handleGetRoomDevices(id: id, arguments: arguments)
        case "get_logs":
            return await handleGetLogs(id: id, arguments: arguments)
        case "get_devices_in_rooms":
            return await handleGetDevicesInRooms(id: id, arguments: arguments)
        case "get_devices_by_type":
            return await handleGetDevicesByType(id: id, arguments: arguments)
        case "list_scenes":
            return await handleListScenes(id: id)
        case "execute_scene":
            return await handleExecuteScene(id: id, arguments: arguments)
        case "list_service_types":
            return handleListServiceTypes(id: id)
        case "list_characteristic_types":
            return handleListCharacteristicTypes(id: id)
        case "list_device_categories":
            return handleListDeviceCategories(id: id)
        case "get_workflow_schema":
            return handleGetWorkflowSchema(id: id)
        case "list_workflows":
            return await handleListWorkflows(id: id)
        case "get_workflow":
            return await handleGetWorkflow(id: id, arguments: arguments)
        case "create_workflow":
            return await handleCreateWorkflow(id: id, arguments: arguments)
        case "update_workflow":
            return await handleUpdateWorkflow(id: id, arguments: arguments)
        case "delete_workflow":
            return await handleDeleteWorkflow(id: id, arguments: arguments)
        case "enable_workflow":
            return await handleEnableWorkflow(id: id, arguments: arguments)
        case "get_workflow_logs":
            return await handleGetWorkflowLogs(id: id, arguments: arguments)
        case "trigger_workflow":
            return await handleTriggerWorkflow(id: id, arguments: arguments)
        case "trigger_workflow_webhook":
            return await handleTriggerWorkflowWebhook(id: id, arguments: arguments)
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
              let characteristicType = arguments["characteristic_type"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required arguments: device_id, characteristic_type"
            )
        }

        guard let value = arguments["value"] else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: value"
            )
        }

        let serviceId = arguments["service_id"] as? String

        // Check device/characteristic exposure before allowing control
        let exposed = await isCharacteristicExposed(
            deviceId: deviceId,
            characteristicType: characteristicType,
            serviceId: serviceId
        )
        guard exposed else {
            return toolResult(
                text: "Device or characteristic not found or not exposed for external access.",
                isError: true,
                id: id
            )
        }

        // Validate value against characteristic metadata and check write permission
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType

        // Convert temperature from user's preferred unit back to Celsius for HomeKit
        var effectiveValue = value
        if TemperatureConversion.isFahrenheit && TemperatureConversion.isTemperatureCharacteristic(resolvedType) {
            if let doubleVal = value as? Double {
                effectiveValue = TemperatureConversion.fahrenheitToCelsius(doubleVal)
            } else if let intVal = value as? Int {
                effectiveValue = TemperatureConversion.fahrenheitToCelsius(Double(intVal))
            }
        }

        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        if let device {
            let targetServices = serviceId != nil ? device.services.filter({ $0.id == serviceId }) : device.services
            if let characteristic = targetServices.flatMap(\.characteristics).first(where: { $0.type == resolvedType }) {
                // Check write permission
                guard characteristic.permissions.contains("write") else {
                    return toolResult(
                        text: "Characteristic '\(CharacteristicTypes.displayName(for: resolvedType))' is not writable (permissions: \(characteristic.permissions.joined(separator: ", "))).",
                        isError: true,
                        id: id
                    )
                }
                do {
                    try CharacteristicValidator.validate(value: effectiveValue, against: characteristic)
                } catch let error as CharacteristicValidator.ValidationError {
                    return toolResult(text: error.message, isError: true, id: id)
                } catch {}
            }
        }

        do {
            try await homeKitManager.updateDevice(id: deviceId, characteristicType: characteristicType, value: effectiveValue, serviceId: serviceId)

            let displayName = CharacteristicTypes.displayName(for: resolvedType)

            var message = "Successfully set \(displayName) to \(value) on device \(deviceId)"
            if let serviceId {
                message += " (service: \(serviceId))"
            }
            return toolResult(text: message, id: id)
        } catch {
            AppLogger.general.error("Device control failed: \(error.localizedDescription)")
            return toolResult(text: "Failed to control device: \(error.localizedDescription)", isError: true, id: id)
        }
    }

    private func handleListDevices(id: JSONRPCId?, arguments: [String: Any] = [:]) async -> JSONRPCResponse {
        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }

        // Parse optional filters
        let roomFilter = arguments["rooms"] as? [String]
        let serviceTypeFilter = arguments["service_type"] as? String
        let charTypeFilter = arguments["characteristic_type"] as? String
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

            // Service type filter
            if let serviceTypeFilter {
                let resolvedServiceType = ServiceTypes.serviceType(forName: serviceTypeFilter)
                filteredDevices = filteredDevices.filter { device in
                    device.services.contains { service in
                        if let resolved = resolvedServiceType {
                            return service.type == resolved
                        }
                        return service.type.localizedCaseInsensitiveContains(serviceTypeFilter) ||
                               service.displayName.localizedCaseInsensitiveContains(serviceTypeFilter)
                    }
                }
            }

            // Characteristic type filter
            if let charTypeFilter {
                let resolvedCharType = CharacteristicTypes.characteristicType(forName: charTypeFilter)
                filteredDevices = filteredDevices.filter { device in
                    device.services.contains { service in
                        service.characteristics.contains { char in
                            if let resolved = resolvedCharType {
                                return char.type == resolved
                            }
                            let charName = CharacteristicTypes.displayName(for: char.type)
                            return charName.localizedCaseInsensitiveContains(charTypeFilter)
                        }
                    }
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

    private func handleListServiceTypes(id: JSONRPCId?) -> JSONRPCResponse {
        let entries = ServiceTypes.allEntries
        var lines: [String] = ["Known service types (\(entries.count)):"]
        for entry in entries {
            if entry.description.isEmpty {
                lines.append("- \(entry.displayName)")
            } else {
                lines.append("- \(entry.displayName) — \(entry.description)")
            }
        }
        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleListCharacteristicTypes(id: JSONRPCId?) -> JSONRPCResponse {
        let allMappings = CharacteristicTypes.allMappings

        var lines: [String] = ["Known characteristic types (\(allMappings.count)):"]
        for entry in allMappings {
            let name = entry.displayName
            let uuid = entry.uuid

            // Semantic description
            let semanticDesc = CharacteristicTypes.description(for: uuid)

            // Build value description
            var valueDesc = ""

            // Check for enum values
            if let enumMap = CharacteristicInputConfig.enumLabelMaps[uuid] {
                let sorted = enumMap.sorted { $0.key < $1.key }
                let vals = sorted.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                valueDesc = "enum: \(vals)"
            } else {
                // Determine value type from characteristic behavior
                valueDesc = Self.characteristicValueDescription(for: uuid)
            }

            // Get aliases (names that differ from the canonical lowercase display name)
            let aliases = CharacteristicTypes.aliases(for: uuid)
                .filter { $0 != name.lowercased() }

            var line = "- \(name)"
            if !aliases.isEmpty {
                line += " (aliases: \(aliases.joined(separator: ", ")))"
            }
            if let desc = semanticDesc {
                line += " — \(desc)"
            }
            line += " [\(valueDesc)]"
            lines.append(line)
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    /// Returns a human-readable value description for a characteristic type.
    private static func characteristicValueDescription(for uuid: String) -> String {
        switch uuid {
        case HMCharacteristicTypePowerState, HMCharacteristicTypeMotionDetected,
             HMCharacteristicTypeOutletInUse, HMCharacteristicTypeObstructionDetected,
             HMCharacteristicTypeStatusActive:
            return "bool (true=On, false=Off)"
        case HMCharacteristicTypeBrightness, HMCharacteristicTypeSaturation,
             HMCharacteristicTypeBatteryLevel, HMCharacteristicTypeCurrentRelativeHumidity,
             HMCharacteristicTypeTargetRelativeHumidity, HMCharacteristicTypeCurrentPosition,
             HMCharacteristicTypeTargetPosition, HMCharacteristicTypeRotationSpeed:
            return "percentage 0-100%"
        case HMCharacteristicTypeHue:
            return "degrees 0-360°"
        case HMCharacteristicTypeColorTemperature:
            return "integer 140-500K (mireds)"
        case HMCharacteristicTypeCurrentTemperature:
            return "read-only, temperature (°C/°F)"
        case HMCharacteristicTypeTargetTemperature:
            return "temperature (°C/°F, typically 10-38)"
        case HMCharacteristicTypeCurrentLightLevel:
            return "read-only, float (lux)"
        case HMCharacteristicTypeRemainingDuration:
            return "read-only, integer (seconds)"
        case HMCharacteristicTypeSetDuration:
            return "integer (seconds)"
        case HMCharacteristicTypeName:
            return "read-only, string"
        default:
            return "value"
        }
    }

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

    private func handleGetWorkflowSchema(id: JSONRPCId?) -> JSONRPCResponse {
        let schema: [String: Any] = [
            "description": "Schema for creating and updating workflows via create_workflow and update_workflow tools.",
            "topLevelFields": [
                "name": ["type": "string", "required": true, "description": "Workflow name"],
                "description": ["type": "string", "required": false, "description": "Workflow description"],
                "isEnabled": ["type": "boolean", "required": false, "default": true],
                "continueOnError": ["type": "boolean", "required": false, "default": false,
                    "description": "Must be true if using blockResult conditions"],
                "triggers": ["type": "array", "required": true, "description": "Array of trigger objects"],
                "conditions": ["type": "array", "required": false,
                    "description": "Optional guard conditions (AND-ed). Only deviceState, timeCondition allowed (no blockResult)."],
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
                        "condition": ["type": "object", "required": true, "description": "Trigger condition (see triggerConditions)"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false]
                    ] as [String: Any]
                ],
                [
                    "type": "schedule",
                    "fields": [
                        "scheduleType": ["type": "object", "required": true, "description": "See scheduleTypes"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false]
                    ] as [String: Any]
                ],
                [
                    "type": "sunEvent",
                    "fields": [
                        "event": ["type": "string", "required": true, "values": ["sunrise", "sunset"]],
                        "offsetMinutes": ["type": "integer", "required": false, "default": 0,
                            "description": "Negative=before, positive=after, 0=exact"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false]
                    ] as [String: Any]
                ],
                [
                    "type": "webhook",
                    "fields": [
                        "token": ["type": "string", "required": true, "description": "Unique webhook token"],
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false]
                    ] as [String: Any]
                ],
                [
                    "type": "workflow",
                    "description": "Makes this workflow callable by other workflows via executeWorkflow blocks.",
                    "fields": [
                        "name": ["type": "string", "required": false],
                        "retriggerPolicy": ["type": "string", "required": false]
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
                                "description": "Value to set. Use list_characteristic_types for valid values."],
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
                            "condition": ["type": "WorkflowCondition", "required": true],
                            "timeoutSeconds": ["type": "number", "required": true],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ],
                    [
                        "block": "flowControl", "type": "conditional",
                        "fields": [
                            "condition": ["type": "WorkflowCondition", "required": true,
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
                            "condition": ["type": "WorkflowCondition", "required": true,
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
                        "block": "flowControl", "type": "executeWorkflow",
                        "fields": [
                            "targetWorkflowId": ["type": "string", "required": true, "description": "UUID of target workflow"],
                            "executionMode": ["type": "string", "required": true,
                                "values": ["inline", "parallel", "delegate"],
                                "description": "inline=wait, parallel=fire-and-continue, delegate=fire-and-stop-current"],
                            "name": ["type": "string", "required": false]
                        ] as [String: Any]
                    ]
                ] as [[String: Any]]
            ] as [String: Any],
            "conditionTypes": [
                "description": "WorkflowCondition types used in guard conditions, conditional blocks, waitForState, and repeatWhile.",
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
                                "format": "{hour: 0-23, minute: 0-59}", "description": "Required for timeRange"],
                            "endTime": ["type": "object", "required": false,
                                "format": "{hour: 0-23, minute: 0-59}", "description": "Required for timeRange"]
                        ] as [String: Any]
                    ],
                    [
                        "type": "blockResult",
                        "restriction": "ONLY valid inside conditional block conditions. NOT allowed in guard conditions, repeatWhile, or waitForState.",
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
                        "type": "and",
                        "fields": ["conditions": ["type": "array", "description": "Array of WorkflowCondition objects"]]
                    ],
                    [
                        "type": "or",
                        "fields": ["conditions": ["type": "array", "description": "Array of WorkflowCondition objects"]]
                    ],
                    [
                        "type": "not",
                        "fields": ["condition": ["type": "WorkflowCondition", "description": "Single condition to negate"]]
                    ]
                ] as [[String: Any]]
            ] as [String: Any],
            "comparisonOperators": [
                "description": "Comparison types for deviceState conditions",
                "types": [
                    ["type": "equals", "fields": ["value": "any"]],
                    ["type": "notEquals", "fields": ["value": "any"]],
                    ["type": "greaterThan", "fields": ["value": "number"]],
                    ["type": "lessThan", "fields": ["value": "number"]],
                    ["type": "greaterThanOrEqual", "fields": ["value": "number"]],
                    ["type": "lessThanOrEqual", "fields": ["value": "number"]]
                ] as [[String: Any]]
            ] as [String: Any],
            "importantRules": [
                "Always include deviceName and roomName alongside deviceId in triggers, conditions, and blocks.",
                "blockResult conditions are ONLY valid inside conditional block conditions.",
                "Guard-level conditions only support: deviceState, timeCondition, and/or/not.",
                "repeatWhile conditions only support: deviceState, timeCondition, and/or/not (no blockResult).",
                "Set continueOnError=true on the workflow when using blockResult conditions.",
                "Use list_devices to discover device IDs, service IDs, and characteristic IDs.",
                "Use characteristic IDs (not types) in triggers, conditions, and controlDevice actions."
            ]
        ]

        // Encode the schema as formatted JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return toolResult(text: jsonString, id: id)
        }
        return toolResult(text: "Failed to encode workflow schema", isError: true, id: id)
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

    private func handleGetRoomDevices(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let roomName = arguments["room_name"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: room_name"
            )
        }

        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }

        guard let group = groups.first(where: { $0.roomName.localizedCaseInsensitiveCompare(roomName) == .orderedSame }) else {
            return toolResult(text: "Room not found: \(roomName). Use list_rooms to see available rooms.", isError: true, id: id)
        }

        let filteredDevices = stableDevices(group.devices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }
        return toolResult(encoding: restDevices, id: id)
    }

    private func handleGetDevicesInRooms(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let rooms = arguments["rooms"] as? [String] else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: rooms (array of strings)"
            )
        }

        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }
        var resultDevices: [DeviceModel] = []
        var missingRooms: [String] = []

        for roomName in rooms {
            if let group = groups.first(where: { $0.roomName.localizedCaseInsensitiveCompare(roomName) == .orderedSame }) {
                resultDevices.append(contentsOf: group.devices)
            } else {
                missingRooms.append(roomName)
            }
        }

        let filteredDevices = stableDevices(resultDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }

        guard let jsonData = try? JSONEncoder.iso8601.encode(restDevices),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return toolResult(text: "Failed to encode device data", isError: true, id: id)
        }

        var responseText = jsonString
        if !missingRooms.isEmpty {
            responseText += "\n\nNote: The following rooms were not found: \(missingRooms.joined(separator: ", "))"
        }

        return toolResult(text: responseText, id: id)
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
            let charName = CharacteristicTypes.displayName(for: log.characteristicType)
            let oldVal = log.oldValue.map { CharacteristicTypes.formatValue($0.value, characteristicType: log.characteristicType) } ?? "nil"
            let newVal = log.newValue.map { CharacteristicTypes.formatValue($0.value, characteristicType: log.characteristicType) } ?? "nil"
            let serviceLabel = log.serviceName.map { " [\($0)]" } ?? ""
            lines.append("[\(formatter.string(from: log.timestamp))] \(log.deviceName)\(serviceLabel) — \(charName): \(oldVal) → \(newVal) (\(log.category.rawValue))")
        }

        if logs.isEmpty {
            lines.append("No logs found.")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleGetDevice(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let deviceId = arguments["device_id"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: MCPErrorCode.invalidParams,
                message: "Missing required argument: device_id"
            )
        }

        let device = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }

        guard let device else {
            return toolResult(text: "Device not found: \(deviceId)", isError: true, id: id)
        }

        let filtered = stableDevices([device])

        guard let filteredDevice = filtered.first else {
            return toolResult(text: "Device not found: \(deviceId)", isError: true, id: id)
        }

        let restDevice = RESTDevice.from(filteredDevice)
        return toolResult(encoding: restDevice, id: id)
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

    // MARK: - Workflow Tool Handlers

    private func handleListWorkflows(id: JSONRPCId?) async -> JSONRPCResponse {
        let workflows = await workflowStorageService.getAllWorkflows()

        if workflows.isEmpty {
            return toolResult(text: "No workflows found. Use create_workflow to create one.", id: id)
        }

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        for workflow in workflows {
            let status = workflow.isEnabled ? "✓ enabled" : "✗ disabled"
            let triggers = "\(workflow.triggers.count) trigger\(workflow.triggers.count == 1 ? "" : "s")"
            let blocks = "\(workflow.blocks.count) block\(workflow.blocks.count == 1 ? "" : "s")"
            let execs = "executions: \(workflow.metadata.totalExecutions)"
            let lastTriggered = workflow.metadata.lastTriggeredAt.map { "last: \(formatter.string(from: $0))" } ?? "never triggered"
            let failures = workflow.metadata.consecutiveFailures > 0 ? " ⚠ \(workflow.metadata.consecutiveFailures) consecutive failures" : ""

            lines.append("- **\(workflow.name)** [\(status)] (id: \(workflow.id.uuidString))")
            if let desc = workflow.description {
                lines.append("  \(desc)")
            }
            lines.append("  \(triggers), \(blocks) | \(execs), \(lastTriggered)\(failures)")
            lines.append("")
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    private func handleGetWorkflow(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let workflowIdStr = arguments["workflow_id"] as? String,
              let workflowId = UUID(uuidString: workflowIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid workflow_id (must be a UUID)")
        }

        guard let workflow = await workflowStorageService.getWorkflow(id: workflowId) else {
            return toolResult(text: "Workflow not found: \(workflowIdStr)", isError: true, id: id)
        }

        return toolResult(encoding: workflow, id: id)
    }

    private func handleCreateWorkflow(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let workflowDict = arguments["workflow"] as? [String: Any] else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: workflow (JSON object)")
        }

        do {
            let workflow = try parseWorkflowFromDict(workflowDict)

            // Validate characteristic permissions
            if let validationError = await validateWorkflowPermissions(workflow) {
                return toolResult(text: validationError, isError: true, id: id)
            }

            let created = await workflowStorageService.createWorkflow(workflow)
            return toolResult(text: "Workflow created successfully.\nID: \(created.id.uuidString)\nName: \(created.name)", id: id)
        } catch {
            AppLogger.general.error("Workflow creation failed: \(error.localizedDescription)")
            return toolResult(text: "Failed to create workflow. Check server logs for details.", isError: true, id: id)
        }
    }

    private func handleUpdateWorkflow(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let workflowIdStr = arguments["workflow_id"] as? String,
              let workflowId = UUID(uuidString: workflowIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid workflow_id (must be a UUID)")
        }

        guard let updates = arguments["workflow"] as? [String: Any] else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: workflow (JSON object)")
        }

        guard let existing = await workflowStorageService.getWorkflow(id: workflowId) else {
            return toolResult(text: "Workflow not found: \(workflowIdStr)", isError: true, id: id)
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
                merged.triggers = try JSONDecoder.iso8601.decode([WorkflowTrigger].self, from: data)
            }
            if let conditionsArray = updates["conditions"] {
                let data = try JSONSerialization.data(withJSONObject: conditionsArray)
                merged.conditions = try JSONDecoder.iso8601.decode([WorkflowCondition].self, from: data)
            }
            if let blocksArray = updates["blocks"] {
                let data = try JSONSerialization.data(withJSONObject: blocksArray)
                merged.blocks = try JSONDecoder.iso8601.decode([WorkflowBlock].self, from: data)
            }

            // Validate characteristic permissions
            if let validationError = await validateWorkflowPermissions(merged) {
                return toolResult(text: validationError, isError: true, id: id)
            }

            let updated = await workflowStorageService.updateWorkflow(id: workflowId) { workflow in
                workflow.name = merged.name
                workflow.description = merged.description
                workflow.isEnabled = merged.isEnabled
                workflow.continueOnError = merged.continueOnError
                workflow.retriggerPolicy = merged.retriggerPolicy
                workflow.triggers = merged.triggers
                workflow.conditions = merged.conditions
                workflow.blocks = merged.blocks
            }

            if let updated {
                return toolResult(text: "Workflow updated successfully.\nID: \(updated.id.uuidString)\nName: \(updated.name)", id: id)
            } else {
                return toolResult(text: "Failed to update workflow", isError: true, id: id)
            }
        } catch {
            AppLogger.general.error("Workflow update parse failed: \(error.localizedDescription)")
            return toolResult(text: "Failed to parse workflow update. Check server logs for details.", isError: true, id: id)
        }
    }

    private func handleDeleteWorkflow(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let workflowIdStr = arguments["workflow_id"] as? String,
              let workflowId = UUID(uuidString: workflowIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid workflow_id (must be a UUID)")
        }

        let deleted = await workflowStorageService.deleteWorkflow(id: workflowId)
        if deleted {
            return toolResult(text: "Workflow deleted: \(workflowIdStr)", id: id)
        } else {
            return toolResult(text: "Workflow not found: \(workflowIdStr)", isError: true, id: id)
        }
    }

    private func handleEnableWorkflow(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let workflowIdStr = arguments["workflow_id"] as? String,
              let workflowId = UUID(uuidString: workflowIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid workflow_id (must be a UUID)")
        }

        guard let enabled = arguments["enabled"] as? Bool else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: enabled (boolean)")
        }

        let updated = await workflowStorageService.updateWorkflow(id: workflowId) { workflow in
            workflow.isEnabled = enabled
        }

        if let updated {
            return toolResult(text: "Workflow '\(updated.name)' is now \(enabled ? "enabled" : "disabled")", id: id)
        } else {
            return toolResult(text: "Workflow not found: \(workflowIdStr)", isError: true, id: id)
        }
    }

    private func handleGetWorkflowLogs(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        let limit = arguments["limit"] as? Int ?? 20

        var logs: [WorkflowExecutionLog]
        if let workflowIdStr = arguments["workflow_id"] as? String,
           let workflowId = UUID(uuidString: workflowIdStr) {
            logs = await loggingService.getLogs(forWorkflowId: workflowId).compactMap(\.workflowExecution)
        } else {
            logs = await loggingService.getLogs().compactMap(\.workflowExecution)
        }

        logs = Array(logs.prefix(limit))

        if logs.isEmpty {
            return toolResult(text: "No workflow execution logs found.", id: id)
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

            lines.append("[\(formatter.string(from: log.triggeredAt))] \(log.workflowName) — \(log.status.rawValue) (\(duration))")

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

    private func handleTriggerWorkflow(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let workflowIdStr = arguments["workflow_id"] as? String,
              let workflowId = UUID(uuidString: workflowIdStr) else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing or invalid workflow_id (must be a UUID)")
        }

        let result = await workflowEngine.scheduleTrigger(id: workflowId)
        return toolResult(text: result.message, isError: !result.isAccepted, id: id)
    }

    private func handleTriggerWorkflowWebhook(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
        guard let token = arguments["token"] as? String, !token.isEmpty else {
            return JSONRPCResponse.error(id: id, code: MCPErrorCode.invalidParams, message: "Missing required argument: token")
        }

        let allWorkflows = await workflowStorageService.getEnabledWorkflows()
        let matchingWorkflows = allWorkflows.filter { workflow in
            workflow.triggers.contains { trigger in
                if case .webhook(let wt) = trigger { return wt.token == token }
                return false
            }
        }

        guard !matchingWorkflows.isEmpty else {
            return toolResult(text: "No enabled workflow found for webhook token: \(token.prefix(8))...", isError: true, id: id)
        }

        var lines: [String] = []
        for workflow in matchingWorkflows {
            // Find the specific webhook trigger that matched to get its retrigger policy
            let matchedTrigger = workflow.triggers.first { trigger in
                if case .webhook(let wt) = trigger { return wt.token == token }
                return false
            }
            let policy = matchedTrigger?.retriggerPolicy

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
            let result = await workflowEngine.scheduleTrigger(id: workflow.id, triggerEvent: triggerEvent, policy: policy)
            lines.append("\(workflow.name): \(result.message)")
        }

        if lines.isEmpty {
            return toolResult(text: "Webhook matched \(matchingWorkflows.count) workflow(s) but none were scheduled.", id: id)
        }

        return toolResult(text: lines.joined(separator: "\n"), id: id)
    }

    // MARK: - Workflow JSON Parser

    /// Parses a raw [String: Any] dictionary into a Workflow struct by serializing to JSON and decoding.
    private func parseWorkflowFromDict(_ dict: [String: Any]) throws -> Workflow {
        // Build a complete workflow dict with defaults
        var workflowDict = dict

        // Set defaults if not provided
        if workflowDict["id"] == nil {
            workflowDict["id"] = UUID().uuidString
        }
        if workflowDict["isEnabled"] == nil {
            // Check for "enabled" alias
            if let enabled = workflowDict["enabled"] as? Bool {
                workflowDict["isEnabled"] = enabled
                workflowDict.removeValue(forKey: "enabled")
            } else {
                workflowDict["isEnabled"] = true
            }
        }
        if workflowDict["continueOnError"] == nil {
            workflowDict["continueOnError"] = false
        }
        if workflowDict["triggers"] == nil {
            workflowDict["triggers"] = [] as [[String: Any]]
        }
        if workflowDict["blocks"] == nil {
            workflowDict["blocks"] = [] as [[String: Any]]
        }

        let now = ISO8601DateFormatter().string(from: Date())
        if workflowDict["createdAt"] == nil {
            workflowDict["createdAt"] = now
        }
        if workflowDict["updatedAt"] == nil {
            workflowDict["updatedAt"] = now
        }

        // Provide default metadata if not present
        if workflowDict["metadata"] == nil {
            workflowDict["metadata"] = [
                "totalExecutions": 0,
                "consecutiveFailures": 0
            ] as [String: Any]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: workflowDict, options: [])
        return try JSONDecoder.iso8601.decode(Workflow.self, from: jsonData)
    }

    // MARK: - Workflow Permission Validation

    /// Validates that workflow triggers and blocks reference characteristics with the required permissions.
    /// - deviceStateChange triggers require "notify" permission
    /// - controlDevice actions require "write" permission
    /// Returns nil if valid, or an error message string if invalid.
    func validateWorkflowPermissions(_ workflow: Workflow) async -> String? {
        // Use registry-proxied devices: stable IDs and effective permissions baked in
        let allDevices = await MainActor.run { homeKitManager.getAllDevices() }
        let registryDevices = stableDevices(allDevices)
        let deviceMap = Dictionary(uniqueKeysWithValues: registryDevices.map { ($0.id, $0) })

        // Validate triggers
        for (index, trigger) in workflow.triggers.enumerated() {
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
        if let error = validateBlockPermissions(workflow.blocks, deviceMap: deviceMap) {
            return error
        }

        return nil
    }

    /// Recursively validates block permissions.
    private func validateBlockPermissions(_ blocks: [WorkflowBlock], deviceMap: [String: DeviceModel]) -> String? {
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
        var detailedReq: String?
        var detailedResp: String?

        if storage.readDetailedLogsEnabled() {
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
