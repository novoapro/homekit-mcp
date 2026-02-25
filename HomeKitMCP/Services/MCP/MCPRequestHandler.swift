import Foundation

/// Handles MCP JSON-RPC method dispatch and builds responses.
class MCPRequestHandler {
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let configService: DeviceConfigurationService
    private let storage: StorageService
    private let workflowStorageService: WorkflowStorageService
    private let workflowEngine: WorkflowEngine
    private let workflowExecutionLogService: WorkflowExecutionLogService
    private let registry: DeviceRegistryService?

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

    init(homeKitManager: HomeKitManager, loggingService: LoggingService, configService: DeviceConfigurationService, storage: StorageService,
         workflowStorageService: WorkflowStorageService, workflowEngine: WorkflowEngine, workflowExecutionLogService: WorkflowExecutionLogService,
         registry: DeviceRegistryService? = nil) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.configService = configService
        self.storage = storage
        self.workflowStorageService = workflowStorageService
        self.workflowEngine = workflowEngine
        self.workflowExecutionLogService = workflowExecutionLogService
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

        // Single consolidated log entry with both request and response
        let responseSummary = summarizeResponse(response)
        await logMCPCall(method: request.method, request: requestSummary, response: responseSummary,
                         fullRequest: request)

        return response
    }

    // MARK: - MCP Filtering
    
    /// Filters devices to only include characteristics with external access enabled.
    /// Uses a single actor call to fetch all configs at once instead of N individual calls.
    func filterDevicesByConfig(_ devices: [DeviceModel]) async -> [DeviceModel] {
        let allConfigs = await configService.getAllConfigs()
        var result: [DeviceModel] = []
        for device in devices {
            var filteredServices: [ServiceModel] = []
            for service in device.services {
                let filteredChars = service.characteristics.filter { char in
                    // Config keys use HomeKit UUIDs (filtering happens before stable ID transformation)
                    let key = "\(device.id):\(service.id):\(char.id)"
                    return (allConfigs[key] ?? .default).externalAccessEnabled
                }
                if !filteredChars.isEmpty {
                    filteredServices.append(ServiceModel(
                        id: service.id,
                        name: service.name,
                        type: service.type,
                        characteristics: filteredChars
                    ))
                }
            }
            if !filteredServices.isEmpty {
                result.append(DeviceModel(
                    id: device.id,
                    name: device.name,
                    roomName: device.roomName,
                    categoryType: device.categoryType,
                    services: filteredServices,
                    isReachable: device.isReachable,
                    manufacturer: device.manufacturer,
                    model: device.model,
                    serialNumber: device.serialNumber,
                    firmwareRevision: device.firmwareRevision
                ))
            }
        }
        // Transform to stable registry IDs for external consumers
        return toStableIds(result)
    }

    /// Transforms device models to use stable registry IDs for external consumers.
    /// Config filtering must be done BEFORE this transformation (config keys use HomeKit UUIDs).
    private func toStableIds(_ devices: [DeviceModel]) -> [DeviceModel] {
        guard let registry else { return devices }
        return devices.map { registry.withStableIds($0) }
    }

    /// Transforms scene models to use stable registry IDs for external consumers.
    private func toStableIds(_ scenes: [SceneModel]) -> [SceneModel] {
        guard let registry else { return scenes }
        return scenes.map { registry.withStableIds($0) }
    }

    /// Checks whether a specific device + characteristic is exposed for external access.
    private func isCharacteristicExposed(deviceId: String, characteristicType: String, serviceId: String?) async -> Bool {
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType

        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        guard let device else {
            return false
        }

        let allConfigs = await configService.getAllConfigs()

        let targetServices: [ServiceModel]
        if let serviceId {
            targetServices = device.services.filter { $0.id == serviceId }
        } else {
            targetServices = device.services
        }

        for service in targetServices {
            for characteristic in service.characteristics where characteristic.type == resolvedType {
                let key = "\(device.id):\(service.id):\(characteristic.id)"
                if (allConfigs[key] ?? .default).externalAccessEnabled {
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
            let devices = await filterDevicesByConfig(allDevices)
            let restDevices = devices.map { RESTDevice.from($0) }

            guard let jsonData = try? Self.encoder.encode(restDevices),
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
            let scenes = toStableIds(await MainActor.run { homeKitManager.getAllScenes() })
            let restScenes = scenes.map { RESTScene.from($0) }

            guard let jsonData = try? Self.encoder.encode(restScenes),
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
            return await handleListDevices(id: id)
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

        // Validate value against characteristic metadata
        let resolvedType = CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType
        let device: DeviceModel? = await MainActor.run { homeKitManager.getDeviceState(id: deviceId) }
        if let device {
            let targetServices = serviceId != nil ? device.services.filter({ $0.id == serviceId }) : device.services
            if let characteristic = targetServices.flatMap(\.characteristics).first(where: { $0.type == resolvedType }) {
                do {
                    try CharacteristicValidator.validate(value: value, against: characteristic)
                } catch let error as CharacteristicValidator.ValidationError {
                    return toolResult(text: error.message, isError: true, id: id)
                } catch {}
            }
        }

        do {
            try await homeKitManager.updateDevice(id: deviceId, characteristicType: characteristicType, value: value, serviceId: serviceId)

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

    private func handleListDevices(id: JSONRPCId?) async -> JSONRPCResponse {
        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }

        var lines: [String] = []
        for group in groups {
            let filteredDevices = await filterDevicesByConfig(group.devices)
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
                        guard char.isUserFacing else { continue }
                        let charName = CharacteristicTypes.displayName(for: char.type)
                        let val = char.value.map { CharacteristicTypes.formatValue($0.value, characteristicType: char.type) } ?? "--"
                        let hint = Self.metadataHint(for: char)
                        let indent = device.services.count > 1 ? "      " : "    "
                        lines.append("\(indent)\(charName): \(val)\(hint)")
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

        let filteredDevices = await filterDevicesByConfig(group.devices)
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

        let filteredDevices = await filterDevicesByConfig(resultDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }

        guard let jsonData = try? Self.encoder.encode(restDevices),
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

        let filteredDevices = await filterDevicesByConfig(matchingDevices)
        let restDevices = filteredDevices.map { RESTDevice.from($0) }
        return toolResult(encoding: restDevices, id: id)
    }

    private func handleGetLogs(id: JSONRPCId?, arguments: [String: Any]) async -> JSONRPCResponse {
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

        let filtered = await filterDevicesByConfig([device])

        guard let filteredDevice = filtered.first else {
            return toolResult(text: "Device not found: \(deviceId)", isError: true, id: id)
        }

        let restDevice = RESTDevice.from(filteredDevice)
        return toolResult(encoding: restDevice, id: id)
    }

    // MARK: - Scene Tool Handlers

    private func handleListScenes(id: JSONRPCId?) async -> JSONRPCResponse {
        let scenes = toStableIds(await MainActor.run { homeKitManager.getAllScenes() })

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
                merged.triggers = try Self.decoder.decode([WorkflowTrigger].self, from: data)
            }
            if let conditionsArray = updates["conditions"] {
                let data = try JSONSerialization.data(withJSONObject: conditionsArray)
                merged.conditions = try Self.decoder.decode([WorkflowCondition].self, from: data)
            }
            if let blocksArray = updates["blocks"] {
                let data = try JSONSerialization.data(withJSONObject: blocksArray)
                merged.blocks = try Self.decoder.decode([WorkflowBlock].self, from: data)
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
            logs = await workflowExecutionLogService.getLogs(forWorkflow: workflowId)
        } else {
            logs = await workflowExecutionLogService.getLogs()
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
                let triggerLabel = trigger.triggerDescription ?? "\(trigger.deviceName ?? trigger.deviceId ?? "unknown") \(trigger.characteristicType ?? "")"
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
                serviceId: nil,
                characteristicType: nil,
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
        return try Self.decoder.decode(Workflow.self, from: jsonData)
    }

    // MARK: - Metadata Hints

    /// Builds an inline metadata hint string for a characteristic, e.g. ` (int, 0–100, %)`.
    /// Only shown for writable characteristics.
    private static func metadataHint(for char: CharacteristicModel) -> String {
        guard char.permissions.contains("write") else { return "" }

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
        guard let jsonData = try? Self.encoder.encode(value),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return toolResult(text: "Failed to encode response data", isError: true, id: id)
        }
        return toolResult(text: jsonString, isError: isError, id: id)
    }

    // MARK: - MCP Logging Helpers

    private func logMCPCall(method: String, request: String, response: String,
                            fullRequest: JSONRPCRequest? = nil) async {
        var detailedReq: String?

        if storage.readDetailedLogsEnabled() {
            if let fullRequest, let data = try? Self.encoder.encode(fullRequest) {
                detailedReq = String(data: data, encoding: .utf8)
            }
        }

        let entry = StateChangeLog.mcpCall(
            method: method,
            summary: request,
            result: response,
            detailedRequest: detailedReq
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
