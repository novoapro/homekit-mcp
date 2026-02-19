import Foundation

/// Handles MCP JSON-RPC method dispatch and builds responses.
class MCPRequestHandler {
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService
    private let configService: DeviceConfigurationService

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(homeKitManager: HomeKitManager, loggingService: LoggingService, configService: DeviceConfigurationService) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
        self.configService = configService
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
        await logMCPCall(method: request.method, request: requestSummary, response: responseSummary)

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
                    isReachable: device.isReachable
                ))
            }
        }
        return result
    }

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
        let tools: [[String: Any]] = [
            [
                "name": "list_devices",
                "description": "List all HomeKit devices with their current states, grouped by room.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "get_device",
                "description": "Get the current state of a specific HomeKit device by its ID.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "device_id": [
                            "type": "string",
                            "description": "Unique device identifier (UUID from the devices list)"
                        ]
                    ] as [String: Any],
                    "required": ["device_id"]
                ] as [String: Any]
            ],
            [
                "name": "control_device",
                "description": "Control a HomeKit device by setting a characteristic value. For devices with multiple components (e.g. a ceiling fan with both fan and light), use service_id to target a specific service.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "device_id": [
                            "type": "string",
                            "description": "Unique device identifier (UUID from the devices list)"
                        ],
                        "characteristic_type": [
                            "type": "string",
                            "description": "Characteristic to control. Use human-readable names: power, brightness, hue, saturation, color_temperature, target_temperature, target_position, lock_state, rotation_speed"
                        ],
                        "value": [
                            "description": "Value to set. Type depends on characteristic: bool for power/lock, int 0-100 for brightness/saturation/position, int 0-360 for hue, float for temperature"
                        ],
                        "service_id": [
                            "type": "string",
                            "description": "Optional service UUID to target a specific component. Required when a device has multiple services with the same characteristic (e.g. separate power controls for fan and light). Get service IDs from list_devices or get_device."
                        ]
                    ] as [String: Any],
                    "required": ["device_id", "characteristic_type", "value"]
                ] as [String: Any]
            ],
            [
                "name": "list_rooms",
                "description": "List all rooms in the HomeKit home with the number of devices in each.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "get_room_devices",
                "description": "Get all devices in a specific room by room name.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "room_name": [
                            "type": "string",
                            "description": "Name of the room (e.g. 'Living Room', 'Bedroom')"
                        ]
                    ] as [String: Any],
                    "required": ["room_name"]
                ] as [String: Any]
            ],
            [
                "name": "get_logs",
                "description": "Get recent state change logs for HomeKit devices. Optionally filter by device name.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "device_name": [
                            "type": "string",
                            "description": "Optional device name to filter logs by"
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of log entries to return (default 50)"
                        ]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "get_devices_in_rooms",
                "description": "Get all devices in specific rooms. Filter by a list of room names. Returns devices for found rooms and optionally reports missing rooms.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "rooms": [
                            "type": "array",
                            "items": [
                                "type": "string"
                            ],
                            "description": "List of room names to fetch devices for."
                        ]
                    ] as [String: Any],
                    "required": ["rooms"]
                ] as [String: Any]
            ],
            [
                "name": "get_devices_by_type",
                "description": "Get all devices that contain specific service types (e.g. 'Lightbulb', 'Switch', 'Outlet'). Filters devices to only include those matching the requested types.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "types": [
                            "type": "array",
                            "items": [
                                "type": "string"
                            ],
                            "description": "List of service types to filter by (e.g. ['Lightbulb', 'Switch'])."
                        ]
                    ] as [String: Any],
                    "required": ["types"]
                ] as [String: Any]
            ]
        ]
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

        do {
            try await homeKitManager.updateDevice(id: deviceId, characteristicType: characteristicType, value: value, serviceId: serviceId)

            let displayName = CharacteristicTypes.displayName(
                for: CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType
            )

            var message = "Successfully set \(displayName) to \(value) on device \(deviceId)"
            if let serviceId {
                message += " (service: \(serviceId))"
            }
            return toolResult(text: message, id: id)
        } catch {
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
                        lines.append("  ### \(service.name) (service_id: \(service.id))")
                    }
                    for char in service.characteristics {
                        let name = CharacteristicTypes.displayName(for: char.type)
                        let val = char.value.map { CharacteristicTypes.formatValue($0.value, characteristicType: char.type) } ?? "--"
                        let indent = device.services.count > 1 ? "      " : "    "
                        lines.append("\(indent)\(name): \(val)")
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
        return toolResult(encoding: filteredDevices, id: id)
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

        if let deviceName = arguments["device_name"] as? String {
            logs = logs.filter { $0.deviceName.localizedCaseInsensitiveContains(deviceName) }
        }

        let limit = arguments["limit"] as? Int ?? 50
        logs = Array(logs.prefix(limit))

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        for log in logs {
            let charName = CharacteristicTypes.displayName(for: log.characteristicType)
            let oldVal = log.oldValue.map { CharacteristicTypes.formatValue($0.value, characteristicType: log.characteristicType) } ?? "nil"
            let newVal = log.newValue.map { CharacteristicTypes.formatValue($0.value, characteristicType: log.characteristicType) } ?? "nil"
            let serviceLabel = log.serviceName.map { " [\($0)]" } ?? ""
            lines.append("[\(formatter.string(from: log.timestamp))] \(log.deviceName)\(serviceLabel) — \(charName): \(oldVal) → \(newVal)")
        }

        if lines.isEmpty {
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

    private func logMCPCall(method: String, request: String, response: String) async {
        let entry = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            deviceId: "mcp",
            deviceName: "MCP Server",
            characteristicType: method,
            oldValue: nil,
            newValue: nil,
            category: .mcpCall,
            requestBody: request,
            responseBody: response
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

