import Foundation

/// Declarative registry of all MCP tool schemas exposed by the CompAI - Home server.
///
/// Extracted from the 266-line `handleToolsList` method so the definitions live
/// in one focused file and `MCPRequestHandler` stays thin.
///
/// Each entry is a `[String: Any]` that serialises to the MCP JSON-RPC tool schema format.
enum MCPToolDefinitions {

    /// The complete list of tool definitions returned by the `tools/list` method.
    /// Note: `automationTools` are conditionally added in `handleToolsList`.
    static let all: [[String: Any]] = deviceTools + sceneTools + metadataTools

    /// Device, room, and log tools — always available.
    static let deviceTools: [[String: Any]] = [

        // MARK: - Device Tools

        [
            "name": "list_devices",
            "description": "List HomeKit devices with their current states, grouped by room. Optionally filter by room(s) and/or device category. All filters are AND-ed. Use list_device_categories to discover valid category filter values.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "rooms": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Filter by room name(s). Case-insensitive."
                    ],
                    "device_category": [
                        "type": "string",
                        "description": "Filter by device category (e.g. 'Lightbulb', 'Thermostat', 'Sensor'). Case-insensitive."
                    ]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "get_device_details",
            "description": "Get the current state of one or more HomeKit devices by their IDs. Returns detailed information for each requested device.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "device_ids": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Array of device identifiers (UUIDs from the devices list)"
                    ]
                ] as [String: Any],
                "required": ["device_ids"]
            ] as [String: Any]
        ],
        [
            "name": "control_device",
            "description": "Control a HomeKit device by setting a characteristic value. Use the characteristic_id from list_devices or get_device_details to target the exact characteristic.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "device_id": [
                        "type": "string",
                        "description": "Unique device identifier (UUID from the devices list)"
                    ],
                    "characteristic_id": [
                        "type": "string",
                        "description": "Unique characteristic identifier (UUID from list_devices or get_device_details)"
                    ],
                    "value": [
                        "description": "Value to set. Type depends on characteristic: bool for power/lock, int 0-100 for brightness/saturation/position, int 0-360 for hue, float for temperature"
                    ]
                ] as [String: Any],
                "required": ["device_id", "characteristic_id", "value"]
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
            "description": "Get recent logs with filtering and pagination. Filter by device name, date range, and/or log categories (state_change, webhook_call, webhook_error, mcp_call, rest_call, server_error, automation_execution, automation_error, scene_execution, scene_error, backup_restore).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "device_name": [
                        "type": "string",
                        "description": "Filter logs by device name (case-insensitive substring match)"
                    ],
                    "categories": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Filter by log categories. Valid values: state_change, webhook_call, webhook_error, mcp_call, rest_call, server_error, automation_execution, automation_error, scene_execution, scene_error, backup_restore"
                    ],
                    "date": [
                        "type": "string",
                        "description": "Filter logs for a single calendar day (e.g. '2024-01-15'). Mutually exclusive with from/to."
                    ],
                    "from": [
                        "type": "string",
                        "description": "Start date for date range filter (ISO 8601, e.g. '2024-01-01' or '2024-01-01T00:00:00Z')"
                    ],
                    "to": [
                        "type": "string",
                        "description": "End date for date range filter (ISO 8601, e.g. '2024-01-31' or '2024-01-31T23:59:59Z')"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of log entries to return, acts as page size (default 50)"
                    ],
                    "offset": [
                        "type": "integer",
                        "description": "Number of entries to skip for pagination (default 0)"
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

    /// Automation tools — only available when automations are enabled.
    static let automationTools: [[String: Any]] = [

        // MARK: - Automation Tools

        [
            "name": "list_automations",
            "description": "List all automation automations with their status, trigger count, and execution statistics.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "get_automation",
            "description": "Get the full definition of a specific automation including triggers, conditions, blocks, and metadata.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "UUID of the automation"
                    ]
                ] as [String: Any],
                "required": ["automation_id"]
            ] as [String: Any]
        ],
        [
            "name": "create_automation",
            "description": """
                Create a new automation automation from a JSON definition.

                TOP-LEVEL FIELDS: name (required), description, isEnabled (bool, default true), \
                continueOnError (bool, default false), \
                triggers (array), conditions (optional guard array), blocks (array). \
                Omit id, createdAt, updatedAt, metadata — they are auto-generated.

                TRIGGER TYPES (triggers array):
                Each trigger accepts an optional "retriggerPolicy" field that controls what happens if \
                this trigger fires while the automation is already running: \
                "ignoreNew" (default) | "cancelAndRestart" | "queueAndExecute" | "cancelOnly".
                • deviceStateChange — { "type":"deviceStateChange", "name":"optional", "retriggerPolicy":"ignoreNew", \
                "deviceId":"uuid", \
                "deviceName":"Room Light", "roomName":"Living Room", "serviceId":"optional-uuid", \
                "characteristicId":"char-uuid", "condition":{"type":"equals","value":true} } \
                Trigger condition types: "changed" (no value), "equals"/"notEquals"/"greaterThan"/"lessThan"/ \
                "greaterThanOrEqual"/"lessThanOrEqual" (with "value"), \
                "transitioned" (optional "from", optional "to"; at least one required).
                • schedule — { "type":"schedule", "name":"optional", "retriggerPolicy":"ignoreNew", "scheduleType":{ ... } } \
                scheduleType formats: {"type":"once","date":"ISO8601"}, \
                {"type":"daily","time":{"hour":7,"minute":30}}, \
                {"type":"weekly","time":{"hour":7,"minute":30},"days":[2,3,4,5,6]} (1=Sun…7=Sat), \
                {"type":"interval","seconds":300}.
                • sunEvent — { "type":"sunEvent", "name":"optional", "retriggerPolicy":"ignoreNew", \
                "event":"sunrise"|"sunset", "offsetMinutes":-15 } \
                offsetMinutes: negative=before, positive=after, 0=exact.
                • webhook — { "type":"webhook", "name":"optional", "retriggerPolicy":"ignoreNew", "token":"unique-string" }
                • automation — { "type":"automation", "name":"optional", "retriggerPolicy":"ignoreNew" } \
                (makes this automation callable by others)

                BLOCK TYPES (blocks array, use "block" discriminator):
                Action blocks: { "block":"action", "type":"controlDevice"|"runScene"|"webhook"|"log", ... }
                • controlDevice: + deviceId, deviceName, roomName, serviceId?, characteristicId, value
                • runScene: + sceneId, sceneName (optional, cached display name)
                • webhook: + url, method, headers?, body?
                • log: + message
                Flow control blocks: { "block":"flowControl", "type":"...", ... }
                • delay: + seconds
                • waitForState: + condition (AutomationCondition, same as conditional/repeatWhile), timeoutSeconds
                • conditional: + condition (AutomationCondition, see below), thenBlocks, elseBlocks?
                • repeat: + count, blocks, delayBetweenSeconds?
                • repeatWhile: + condition (AutomationCondition), blocks, maxIterations, delayBetweenSeconds?
                • group: + label?, blocks
                • return: + outcome ("success"|"error"|"cancelled"), message? \
                Return exits the current scope (group, repeat, conditional branch) with the given outcome. \
                At top level it terminates the entire automation.
                • executeAutomation: + targetAutomationId (UUID), executionMode ("inline"|"parallel"|"delegate")
                All blocks accept an optional "name" field.

                CONDITION TYPES (AutomationCondition). All support nesting to any depth via and/or/not:
                • { "type":"deviceState", "deviceId":"uuid", "deviceName":"Room Light", "roomName":"Living Room", \
                "serviceId":"optional", "characteristicId":"char-uuid", \
                "comparison":{"type":"equals","value":true} }
                  comparison types: equals/notEquals/greaterThan/lessThan/greaterThanOrEqual/lessThanOrEqual (with "value")
                • { "type":"timeCondition", "mode":"beforeSunrise"|"afterSunrise"|"beforeSunset"|"afterSunset"|"daytime"|"nighttime"|"timeRange", \
                "startTime":{"type":"fixed","hour":23,"minute":0}, "endTime":{"type":"marker","marker":"sunrise"} }
                  mode: beforeSunrise, afterSunrise, beforeSunset, afterSunset, daytime (sunrise–sunset), \
                nighttime (sunset–sunrise), timeRange (custom hours or markers, cross-midnight aware). \
                startTime/endTime required only for timeRange. Each is a TimePoint: \
                {"type":"fixed","hour":0-23,"minute":0-59} or {"type":"marker","marker":"midnight"|"noon"|"sunrise"|"sunset"}. \
                sunrise/sunset markers require location configured. Legacy {hour,minute} without type also accepted.
                • { "type":"and", "conditions":[...] } — all must pass
                • { "type":"or",  "conditions":[...] } — any must pass
                • { "type":"not", "condition":{...} } — negates inner condition
                • { "type":"blockResult", "scope":"specific"|"lastBlock"|"anyPreviousBlock", \
                "blockId":"uuid-of-block" (only when scope is "specific"), \
                "expectedStatus":"success"|"failure"|"cancelled" } — checks the execution result of a \
                previously-run block. Requires continueOnError=true on the automation. \
                IMPORTANT: blockResult is ONLY valid inside conditional (if/else) block conditions. \
                Do NOT use blockResult in automation-level execution guards, per-trigger guards, repeatWhile conditions, or anywhere else. \
                Each block has a 1-based ordinal in depth-first execution order. A blockResult with scope \
                "specific" can ONLY reference blocks with a lower ordinal (earlier in the blocks array). \
                If the referenced block has not executed, the condition evaluates to false.
                The same AutomationCondition format is used in the top-level "conditions" execution guards array \
                (deviceState, timeCondition only), in per-trigger "conditions" arrays \
                (deviceState, timeCondition only — if conditions fail, trigger is silently skipped), \
                in "conditional" block "condition" fields (all types including blockResult), \
                and in "repeatWhile" block "condition" fields (deviceState, timeCondition only — no blockResult).

                DEVICE METADATA: Always include "deviceName" and "roomName" alongside "deviceId" in \
                triggers, execution guards, per-trigger guards, and blocks. This enables \
                cross-machine migration when HomeKit reassigns UUIDs.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation": [
                        "type": "object",
                        "description": "Complete automation JSON definition matching the Automation schema"
                    ]
                ] as [String: Any],
                "required": ["automation"]
            ] as [String: Any]
        ],
        [
            "name": "update_automation",
            "description": """
                Update an existing automation. Provide the automation_id and a partial or full automation JSON. \
                Only top-level fields that are present in the submitted object are replaced; omitted fields \
                remain unchanged. Triggers, conditions, and blocks arrays are replaced wholesale when provided.

                Updatable fields: name, description, isEnabled, continueOnError, \
                triggers, conditions, blocks. \
                Per-trigger retriggerPolicy: set on each trigger object \
                ("ignoreNew"|"cancelAndRestart"|"queueAndExecute"|"cancelOnly").

                The schema for triggers, blocks, and conditions is identical to create_automation. \
                Trigger types: deviceStateChange, schedule, sunEvent, webhook, automation. \
                Block types (use "block":"action"|"flowControl" discriminator): \
                controlDevice, runScene, webhook, log, delay, waitForState, conditional, repeat, \
                repeatWhile, group, return, executeAutomation. \
                Condition types (AutomationCondition, nestable via and/or/not): \
                deviceState, timeCondition, sceneActive, and, or, not (execution guards, per-trigger guards, and block level); \
                blockResult (conditional/if-else blocks only, NOT in execution guards, per-trigger guards, or repeatWhile). \
                Each trigger can have an optional "conditions" array for per-trigger guards. \
                Always include "deviceName" and "roomName" alongside "deviceId" wherever device references appear.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "UUID of the automation to update"
                    ],
                    "automation": [
                        "type": "object",
                        "description": "Partial or full automation JSON. See create_automation for the complete schema."
                    ]
                ] as [String: Any],
                "required": ["automation_id", "automation"]
            ] as [String: Any]
        ],
        [
            "name": "delete_automation",
            "description": "Permanently delete a automation by its ID.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "UUID of the automation to delete"
                    ]
                ] as [String: Any],
                "required": ["automation_id"]
            ] as [String: Any]
        ],
        [
            "name": "enable_automation",
            "description": "Enable or disable a automation.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "UUID of the automation"
                    ],
                    "enabled": [
                        "type": "boolean",
                        "description": "Whether the automation should be enabled (true) or disabled (false)"
                    ]
                ] as [String: Any],
                "required": ["automation_id", "enabled"]
            ] as [String: Any]
        ],
        [
            "name": "get_automation_logs",
            "description": "Get execution history logs for automations. Optionally filter by automation ID and limit the number of results.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "Optional UUID of a specific automation to get logs for"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of log entries to return (default 20)"
                    ]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "trigger_automation",
            "description": "Schedule a automation execution immediately (fire-and-forget). Returns the scheduling outcome based on the trigger's retrigger policy: scheduled, replaced (previous cancelled), queued, cancelled, or ignored (already running).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "UUID of the automation to trigger"
                    ]
                ] as [String: Any],
                "required": ["automation_id"]
            ] as [String: Any]
        ],
        [
            "name": "improve_automation",
            "description": "Use AI to analyze and improve an existing automation. Returns the improved automation JSON without saving it. Review the result and use update_automation to apply the changes.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "automation_id": [
                        "type": "string",
                        "description": "UUID of the automation to improve"
                    ],
                    "prompt": [
                        "type": "string",
                        "description": "Optional instructions for how to improve the automation. Leave empty for automatic review and optimization."
                    ]
                ] as [String: Any],
                "required": ["automation_id"]
            ] as [String: Any]
        ],
    ]

    // MARK: - State Variable Tools

    static let stateVariableTools: [[String: Any]] = [
        [
            "name": "list_state_variables",
            "description": "List all engine state variables with their current values, types, and metadata.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "get_state_variable",
            "description": "Get a specific state variable by ID or name.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "variable_id": [
                        "type": "string",
                        "description": "UUID of the state variable"
                    ] as [String: Any],
                    "name": [
                        "type": "string",
                        "description": "Name of the state variable (alternative to variable_id)"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "create_state_variable",
            "description": "Create a new engine state variable. Types: 'number', 'string', 'boolean'.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of the state variable (must be unique)"
                    ] as [String: Any],
                    "type": [
                        "type": "string",
                        "description": "Variable type: 'number', 'string', or 'boolean'",
                        "enum": ["number", "string", "boolean"]
                    ] as [String: Any],
                    "value": [
                        "description": "Initial value. Must match the declared type."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["name", "type", "value"]
            ] as [String: Any]
        ],
        [
            "name": "update_state_variable",
            "description": "Update the value of an existing state variable. The new value must match the variable's type.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "variable_id": [
                        "type": "string",
                        "description": "UUID of the state variable"
                    ] as [String: Any],
                    "name": [
                        "type": "string",
                        "description": "Name of the state variable (alternative to variable_id)"
                    ] as [String: Any],
                    "value": [
                        "description": "New value. Must match the variable's type."
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["value"]
            ] as [String: Any]
        ],
        [
            "name": "delete_state_variable",
            "description": "Delete a state variable by ID or name.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "variable_id": [
                        "type": "string",
                        "description": "UUID of the state variable"
                    ] as [String: Any],
                    "name": [
                        "type": "string",
                        "description": "Name of the state variable (alternative to variable_id)"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ],
    ]

    // MARK: - Metadata Tools

    /// Metadata tools for AI agent efficiency — always available.
    static let metadataTools: [[String: Any]] = [
        [
            "name": "list_device_categories",
            "description": "List all known HomeKit device categories (e.g. Lightbulb, Thermostat, Sensor). Use these names as filter values in list_devices.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ],
        [
            "name": "get_automation_schema",
            "description": "Get a structured JSON schema describing the automation definition format. Includes all trigger types, block types, condition types, their fields, and valid enum values. Use this to reliably generate automations for create_automation and update_automation.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ] as [String: Any]
        ],
    ]
}
