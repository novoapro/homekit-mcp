import Foundation

/// Declarative registry of all MCP tool schemas exposed by the HomeKit MCP server.
///
/// Extracted from the 266-line `handleToolsList` method so the definitions live
/// in one focused file and `MCPRequestHandler` stays thin.
///
/// Each entry is a `[String: Any]` that serialises to the MCP JSON-RPC tool schema format.
enum MCPToolDefinitions {

    /// The complete list of tool definitions returned by the `tools/list` method.
    static let all: [[String: Any]] = deviceTools + sceneTools + workflowTools

    /// Device, room, and log tools — always available.
    static let deviceTools: [[String: Any]] = [

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
    ]

    /// Scene tools — always available.
    static let sceneTools: [[String: Any]] = [

        // MARK: - Scene Tools

        [
            "name": "list_scenes",
            "description": "List all HomeKit scenes (action sets) with their type, status, and the actions they perform.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "execute_scene",
            "description": "Execute (activate) a HomeKit scene by its ID. This triggers all the actions defined in the scene.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "scene_id": [
                        "type": "string",
                        "description": "Unique scene identifier (UUID from the scenes list)"
                    ]
                ] as [String: Any],
                "required": ["scene_id"]
            ] as [String: Any]
        ],
    ]

    /// Workflow tools — only available when workflows are enabled.
    static let workflowTools: [[String: Any]] = [

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
                Create a new automation workflow from a JSON definition.

                TOP-LEVEL FIELDS: name (required), description, isEnabled (bool, default true), \
                continueOnError (bool, default false), \
                triggers (array), conditions (optional guard array), blocks (array). \
                Omit id, createdAt, updatedAt, metadata — they are auto-generated.

                TRIGGER TYPES (triggers array):
                Each trigger accepts an optional "retriggerPolicy" field that controls what happens if \
                this trigger fires while the workflow is already running: \
                "ignoreNew" (default) | "cancelAndRestart" | "queueAndExecute" | "cancelOnly".
                • deviceStateChange — { "type":"deviceStateChange", "name":"optional", "retriggerPolicy":"ignoreNew", \
                "deviceId":"uuid", \
                "deviceName":"Room Light", "roomName":"Living Room", "serviceId":"optional-uuid", \
                "characteristicType":"Power", "condition":{"type":"equals","value":true} } \
                Trigger condition types: "changed" (no value), "equals"/"notEquals"/"greaterThan"/"lessThan"/ \
                "greaterThanOrEqual"/"lessThanOrEqual" (with "value"), \
                "transitioned" (required "to", optional "from").
                • schedule — { "type":"schedule", "name":"optional", "retriggerPolicy":"ignoreNew", "scheduleType":{ ... } } \
                scheduleType formats: {"type":"once","date":"ISO8601"}, \
                {"type":"daily","time":{"hour":7,"minute":30}}, \
                {"type":"weekly","time":{"hour":7,"minute":30},"days":[2,3,4,5,6]} (1=Sun…7=Sat), \
                {"type":"interval","seconds":300}.
                • sunEvent — { "type":"sunEvent", "name":"optional", "retriggerPolicy":"ignoreNew", \
                "event":"sunrise"|"sunset", "offsetMinutes":-15 } \
                offsetMinutes: negative=before, positive=after, 0=exact.
                • compound — { "type":"compound", "name":"optional", "retriggerPolicy":"ignoreNew", \
                "operator":"and"|"or", "triggers":[...] }
                • webhook — { "type":"webhook", "name":"optional", "retriggerPolicy":"ignoreNew", "token":"unique-string" }
                • workflow — { "type":"workflow", "name":"optional", "retriggerPolicy":"ignoreNew" } \
                (makes this workflow callable by others)

                BLOCK TYPES (blocks array, use "block" discriminator):
                Action blocks: { "block":"action", "type":"controlDevice"|"runScene"|"webhook"|"log", ... }
                • controlDevice: + deviceId, deviceName, roomName, serviceId?, characteristicType, value
                • runScene: + sceneId
                • webhook: + url, method, headers?, body?
                • log: + message
                Flow control blocks: { "block":"flowControl", "type":"...", ... }
                • delay: + seconds
                • waitForState: + deviceId, deviceName, roomName, serviceId?, characteristicType, \
                condition (ComparisonOperator: equals/notEquals/greaterThan/lessThan/greaterThanOrEqual/ \
                lessThanOrEqual, each with "value"), timeoutSeconds
                • conditional: + condition (WorkflowCondition, see below), thenBlocks, elseBlocks?
                • repeat: + count, blocks, delayBetweenSeconds?
                • repeatWhile: + condition (WorkflowCondition), blocks, maxIterations, delayBetweenSeconds?
                • group: + label?, blocks
                • stop: + outcome ("success"|"error"|"cancelled"), message?
                • executeWorkflow: + targetWorkflowId (UUID), executionMode ("inline"|"parallel"|"delegate")
                All blocks accept an optional "name" field.

                GUARD CONDITION TYPES (workflow-level "conditions" array and block condition fields). \
                All condition objects are WorkflowCondition and support nesting to any depth:
                • { "type":"deviceState", "deviceId":"uuid", "deviceName":"Room Light", "roomName":"Living Room", \
                "serviceId":"optional", "characteristicType":"Power", \
                "comparison":{"type":"equals","value":true} }
                  comparison types: equals/notEquals/greaterThan/lessThan/greaterThanOrEqual/lessThanOrEqual (with "value")
                • { "type":"timeCondition", "mode":"beforeSunrise"|"afterSunrise"|"beforeSunset"|"afterSunset"|"daytime"|"nighttime"|"timeRange", \
                "startTime":{"hour":23,"minute":0}, "endTime":{"hour":2,"minute":0} }
                  mode: beforeSunrise, afterSunrise, beforeSunset, afterSunset, daytime (sunrise–sunset), \
                nighttime (sunset–sunrise), timeRange (custom hours, cross-midnight aware). \
                startTime/endTime required only for timeRange (hour 0-23, minute 0-59)
                • { "type":"sceneActive", "sceneId":"uuid", "isActive":true }
                • { "type":"and", "conditions":[...] } — all must pass
                • { "type":"or",  "conditions":[...] } — any must pass
                • { "type":"not", "condition":{...} } — negates inner condition
                Guard conditions can be nested inside and/or/not to any depth. The same WorkflowCondition \
                format is used in the top-level "conditions" array, in "conditional" block "condition" \
                fields, and in "repeatWhile" block "condition" fields.

                DEVICE METADATA: Always include "deviceName" and "roomName" alongside "deviceId" in \
                triggers, guard conditions, and blocks. This enables cross-machine migration when HomeKit \
                reassigns UUIDs.
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
            "description": """
                Update an existing workflow. Provide the workflow_id and a partial or full workflow JSON. \
                Only top-level fields that are present in the submitted object are replaced; omitted fields \
                remain unchanged. Triggers, conditions, and blocks arrays are replaced wholesale when provided.

                Updatable fields: name, description, isEnabled, continueOnError, \
                triggers, conditions, blocks. \
                Per-trigger retriggerPolicy: set on each trigger object \
                ("ignoreNew"|"cancelAndRestart"|"queueAndExecute"|"cancelOnly").

                The schema for triggers, blocks, and conditions is identical to create_workflow. \
                Trigger types: deviceStateChange, schedule, sunEvent, compound, webhook, workflow. \
                Block types (use "block":"action"|"flowControl" discriminator): \
                controlDevice, runScene, webhook, log, delay, waitForState, conditional, repeat, \
                repeatWhile, group, stop, executeWorkflow. \
                Guard/block condition types (WorkflowCondition, nestable via and/or/not): \
                deviceState, timeCondition, sceneActive, and, or, not. \
                Always include "deviceName" and "roomName" alongside "deviceId" wherever device references appear.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "workflow_id": [
                        "type": "string",
                        "description": "UUID of the workflow to update"
                    ],
                    "workflow": [
                        "type": "object",
                        "description": "Partial or full workflow JSON. See create_workflow for the complete schema."
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
            "description": "Schedule a workflow execution immediately (fire-and-forget). Returns the scheduling outcome based on the trigger's retrigger policy: scheduled, replaced (previous cancelled), queued, cancelled, or ignored (already running).",
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
            "description": "Trigger a workflow via its webhook token (fire-and-forget). Any workflow with a matching webhook trigger will be scheduled. Returns the scheduling outcome for each matched workflow.",
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
