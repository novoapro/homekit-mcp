import Foundation

/// Declarative registry of all MCP tool schemas exposed by the HomeKit MCP server.
///
/// Extracted from the 266-line `handleToolsList` method so the definitions live
/// in one focused file and `MCPRequestHandler` stays thin.
///
/// Each entry is a `[String: Any]` that serialises to the MCP JSON-RPC tool schema format.
enum MCPToolDefinitions {

    /// The complete list of tool definitions returned by the `tools/list` method.
    static let all: [[String: Any]] = [

        // MARK: - Device Tools

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

        // MARK: - Room Tools

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
            "name": "get_devices_in_rooms",
            "description": "Get all devices in specific rooms. Filter by a list of room names. Returns devices for found rooms and optionally reports missing rooms.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "rooms": [
                        "type": "array",
                        "items": ["type": "string"],
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
                        "items": ["type": "string"],
                        "description": "List of service types to filter by (e.g. ['Lightbulb', 'Switch'])."
                    ]
                ] as [String: Any],
                "required": ["types"]
            ] as [String: Any]
        ],

        // MARK: - Log Tools

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

        // MARK: - Workflow Tools

        [
            "name": "list_workflows",
            "description": "List all automation workflows with their status, trigger count, and execution statistics.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "get_workflow",
            "description": "Get the full definition of a specific workflow including triggers, conditions, blocks, and metadata.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "UUID of the workflow"
                    ]
                ] as [String: Any],
                "required": ["workflow_id"]
            ] as [String: Any]
        ],
        [
            "name": "create_workflow",
            "description": """
                Create a new automation workflow from a JSON definition. The workflow JSON should include: \
                name (required), description, triggers (array of trigger objects), conditions (optional array of guard conditions), \
                blocks (array of action/flow-control block objects), continueOnError (bool, default false), enabled (bool, default true), \
                retriggerPolicy (string, 'ignoreNew', 'cancelAndRestart', or 'queueAndExecute', default 'ignoreNew'). \
                Triggers use type 'deviceStateChange' with deviceId, characteristicType, and condition. \
                Blocks use 'block' discriminator ('action' or 'flowControl') and 'type' for the specific kind. \
                Action types: controlDevice, webhook, log. Flow control types: delay, waitForState, conditional, repeat, repeatWhile, group.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow": [
                        "type": "object",
                        "description": "Complete workflow JSON definition matching the Workflow schema"
                    ]
                ] as [String: Any],
                "required": ["workflow"]
            ] as [String: Any]
        ],
        [
            "name": "update_workflow",
            "description": "Update an existing workflow. Provide the workflow_id and a partial or full workflow JSON. Only provided fields are updated; omitted fields remain unchanged.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "UUID of the workflow to update"
                    ],
                    "workflow": [
                        "type": "object",
                        "description": "Partial or full workflow JSON with fields to update (name, description, triggers, conditions, blocks, continueOnError, isEnabled, retriggerPolicy ('ignoreNew', 'cancelAndRestart', or 'queueAndExecute'))"
                    ]
                ] as [String: Any],
                "required": ["workflow_id", "workflow"]
            ] as [String: Any]
        ],
        [
            "name": "delete_workflow",
            "description": "Permanently delete a workflow by its ID.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "UUID of the workflow to delete"
                    ]
                ] as [String: Any],
                "required": ["workflow_id"]
            ] as [String: Any]
        ],
        [
            "name": "enable_workflow",
            "description": "Enable or disable a workflow.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "UUID of the workflow"
                    ],
                    "enabled": [
                        "type": "boolean",
                        "description": "Whether the workflow should be enabled (true) or disabled (false)"
                    ]
                ] as [String: Any],
                "required": ["workflow_id", "enabled"]
            ] as [String: Any]
        ],
        [
            "name": "get_workflow_logs",
            "description": "Get execution history logs for workflows. Optionally filter by workflow ID and limit the number of results.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "Optional UUID of a specific workflow to get logs for"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of log entries to return (default 20)"
                    ]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "trigger_workflow",
            "description": "Manually trigger a workflow execution immediately, bypassing its normal triggers. Useful for testing.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "UUID of the workflow to trigger"
                    ]
                ] as [String: Any],
                "required": ["workflow_id"]
            ] as [String: Any]
        ],
        [
            "name": "trigger_workflow_webhook",
            "description": "Trigger a workflow via its webhook token. Any workflow with a webhook trigger matching this token will execute.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "token": [
                        "type": "string",
                        "description": "The webhook token assigned to the trigger"
                    ]
                ] as [String: Any],
                "required": ["token"]
            ] as [String: Any]
        ]
    ]
}
