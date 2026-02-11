import Foundation

/// Handles MCP JSON-RPC method dispatch and builds responses.
class MCPRequestHandler {
    private let homeKitManager: HomeKitManager
    private let loggingService: LoggingService

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(homeKitManager: HomeKitManager, loggingService: LoggingService) {
        self.homeKitManager = homeKitManager
        self.loggingService = loggingService
    }

    func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(id: request.id)
        case "notifications/initialized":
            // This is a notification, no response needed — but if we get it as a request, acknowledge
            return JSONRPCResponse.success(id: request.id, result: AnyCodable([:] as [String: String]))
        case "ping":
            return JSONRPCResponse.success(id: request.id, result: AnyCodable([:] as [String: String]))
        case "resources/list":
            return handleResourcesList(id: request.id)
        case "resources/read":
            return await handleResourcesRead(id: request.id, params: request.params)
        case "tools/list":
            return handleToolsList(id: request.id)
        case "tools/call":
            return await handleToolsCall(id: request.id, params: request.params)
        default:
            return JSONRPCResponse.error(
                id: request.id,
                code: MCPErrorCode.methodNotFound,
                message: "Method not found: \(request.method)"
            )
        }
    }

    // MARK: - Initialize

    private func handleInitialize(id: JSONRPCId?) -> JSONRPCResponse {
        let result: [String: Any] = [
            "protocolVersion": MCPConstants.protocolVersion,
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
            ]
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
            let devices = await MainActor.run { homeKitManager.getAllDevices() }

            // Encode devices to JSON string for the resource content
            guard let jsonData = try? Self.encoder.encode(devices),
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
                "description": "Control a HomeKit device by setting a characteristic value.",
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

        do {
            try await MainActor.run {
                // updateDevice is async, but we need to call it from the main actor
                // since HomeKitManager is on the main thread
            }

            try await homeKitManager.updateDevice(id: deviceId, characteristicType: characteristicType, value: value)

            let displayName = CharacteristicTypes.displayName(
                for: CharacteristicTypes.characteristicType(forName: characteristicType) ?? characteristicType
            )

            let content: [[String: Any]] = [
                [
                    "type": "text",
                    "text": "Successfully set \(displayName) to \(value) on device \(deviceId)"
                ]
            ]
            let result: [String: Any] = ["content": content, "isError": false]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))
        } catch {
            let content: [[String: Any]] = [
                [
                    "type": "text",
                    "text": "Failed to control device: \(error.localizedDescription)"
                ]
            ]
            let result: [String: Any] = ["content": content, "isError": true]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))
        }
    }

    private func handleListDevices(id: JSONRPCId?) async -> JSONRPCResponse {
        let groups = await MainActor.run { homeKitManager.getDevicesGroupedByRoom() }

        var lines: [String] = []
        for group in groups {
            lines.append("## \(group.roomName)")
            for device in group.devices {
                let status = device.isReachable ? "online" : "offline"
                lines.append("- \(device.name) [\(status)] (id: \(device.id))")
                for service in device.services {
                    for char in service.characteristics {
                        let name = CharacteristicTypes.displayName(for: char.type)
                        let val = char.value.map { CharacteristicTypes.formatValue($0.value, characteristicType: char.type) } ?? "--"
                        lines.append("    \(name): \(val)")
                    }
                }
            }
            lines.append("")
        }

        if lines.isEmpty {
            lines.append("No HomeKit devices found.")
        }

        let content: [[String: Any]] = [["type": "text", "text": lines.joined(separator: "\n")]]
        let result: [String: Any] = ["content": content, "isError": false]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
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

        let content: [[String: Any]] = [["type": "text", "text": lines.joined(separator: "\n")]]
        let result: [String: Any] = ["content": content, "isError": false]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
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
            let content: [[String: Any]] = [["type": "text", "text": "Room not found: \(roomName). Use list_rooms to see available rooms."]]
            let result: [String: Any] = ["content": content, "isError": true]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))
        }

        guard let jsonData = try? Self.encoder.encode(group.devices),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            let content: [[String: Any]] = [["type": "text", "text": "Failed to encode device data"]]
            let result: [String: Any] = ["content": content, "isError": true]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))
        }

        let content: [[String: Any]] = [["type": "text", "text": jsonString]]
        let result: [String: Any] = ["content": content, "isError": false]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
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
            lines.append("[\(formatter.string(from: log.timestamp))] \(log.deviceName) — \(charName): \(oldVal) → \(newVal)")
        }

        if lines.isEmpty {
            lines.append("No logs found.")
        }

        let content: [[String: Any]] = [["type": "text", "text": lines.joined(separator: "\n")]]
        let result: [String: Any] = ["content": content, "isError": false]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
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
            let content: [[String: Any]] = [
                [
                    "type": "text",
                    "text": "Device not found: \(deviceId)"
                ]
            ]
            let result: [String: Any] = ["content": content, "isError": true]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))
        }

        guard let jsonData = try? Self.encoder.encode(device),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            let content: [[String: Any]] = [
                [
                    "type": "text",
                    "text": "Failed to encode device data"
                ]
            ]
            let result: [String: Any] = ["content": content, "isError": true]
            return JSONRPCResponse.success(id: id, result: AnyCodable(result))
        }

        let content: [[String: Any]] = [
            [
                "type": "text",
                "text": jsonString
            ]
        ]
        let result: [String: Any] = ["content": content, "isError": false]
        return JSONRPCResponse.success(id: id, result: AnyCodable(result))
    }
}
