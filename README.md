# HomeKit MCP Server

A macOS menu bar app that exposes your Apple HomeKit devices through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). Connect AI assistants like Claude to your smart home — query device states, control accessories, create automation workflows, and receive real-time webhook notifications when things change.

## Features

- **MCP Server** — JSON-RPC over Streamable HTTP and legacy SSE, exposing device resources, control tools, and workflow automation tools
- **REST API** — Full HTTP REST interface for devices and workflows
- **Real-time monitoring** — Observes HomeKit accessory state changes via `HMAccessoryDelegate`
- **Device control** — Turn lights on/off, adjust brightness, set thermostats, lock/unlock doors, and more
- **Workflow automation** — Create, manage, and execute automation workflows with triggers, conditions, and action blocks
- **Webhook notifications** — HTTP POST callbacks on state changes with exponential backoff retry (max 3 attempts)
- **State logging** — Circular buffer of recent state changes, persisted to disk
- **Menu bar app** — Runs unobtrusively in the macOS menu bar (no Dock icon)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+
- HomeKit-compatible accessories configured in the Apple Home app
- An Apple Developer account (for HomeKit entitlement)

## Getting Started

### Build

```bash
xcodebuild -scheme HomeKitMCP -destination 'platform=macOS,variant=Mac Catalyst' build
```

Or open `HomeKitMCP.xcodeproj` in Xcode and build with **Cmd+B**.

### Run

1. Launch the app — it appears as an icon in the menu bar
2. Grant HomeKit access when prompted
3. The MCP server starts automatically on `localhost:3000`

### Connect an MCP Client

Point any MCP-compatible client at:

```
http://localhost:3000/mcp       # Streamable HTTP (recommended)
http://localhost:3000/sse        # Legacy SSE (2024-11-05)
```

## Configuration

Settings are available in the app's Settings view:

| Setting | Default | Description |
|---------|---------|-------------|
| MCP Server Port | `3000` | HTTP port for the MCP and REST server |
| Enable External Access | `true` | Start/stop the MCP and REST server |
| Enable Webhooks | `true` | Send HTTP POST on device state changes |
| Webhook URL | — | Destination URL for webhook notifications |
| Detailed Logs | `false` | Log full request/response JSON bodies |

---

## MCP API

The server implements the [Model Context Protocol](https://modelcontextprotocol.io) with both Streamable HTTP (2025-03-26) and legacy SSE (2024-11-05) transports.

### Resources

| URI | Description |
|-----|-------------|
| `homekit://devices` | JSON array of all HomeKit devices with current states |

### Device Tools

| Tool | Description |
|------|-------------|
| `list_devices` | List all devices grouped by room with current states |
| `get_device` | Get a specific device by ID |
| `control_device` | Set a characteristic value on a device |
| `list_rooms` | List all rooms with device counts |
| `get_room_devices` | Get all devices in a specific room |
| `get_devices_in_rooms` | Get devices from multiple rooms at once |
| `get_devices_by_type` | Filter devices by service type (e.g. Lightbulb, Switch) |
| `get_logs` | Get recent state change logs, optionally filtered by device |

### Workflow Tools

| Tool | Description |
|------|-------------|
| `list_workflows` | List all workflows with status and execution stats |
| `get_workflow` | Get full workflow definition as JSON |
| `create_workflow` | Create a new workflow from a JSON definition |
| `update_workflow` | Update an existing workflow (partial updates supported) |
| `delete_workflow` | Delete a workflow |
| `enable_workflow` | Enable or disable a workflow |
| `trigger_workflow` | Manually trigger a workflow for testing |
| `get_workflow_logs` | Get execution history, optionally filtered by workflow |

### Tool Details

#### `control_device`

```json
{
  "device_id": "ABC-123",
  "characteristic_type": "power",
  "value": true,
  "service_id": "optional-service-uuid"
}
```

Use `service_id` when a device has multiple components (e.g. a ceiling fan with separate fan and light services).

**Supported characteristic names:** `power`, `brightness`, `hue`, `saturation`, `color_temperature`, `target_temperature`, `target_position`, `lock_state`, `rotation_speed`, and more.

#### `create_workflow`

```json
{
  "workflow": {
    "name": "Night motion comfort",
    "description": "When motion detected, turn on bedroom light at 30%",
    "triggers": [
      {
        "type": "deviceStateChange",
        "deviceId": "motion-sensor-1",
        "characteristicType": "Motion Detected",
        "condition": { "type": "equals", "value": true }
      }
    ],
    "conditions": [
      {
        "type": "deviceState",
        "deviceId": "bedroom-light-1",
        "characteristicType": "Power",
        "comparison": { "type": "equals", "value": false }
      }
    ],
    "blocks": [
      {
        "block": "action",
        "type": "controlDevice",
        "deviceId": "bedroom-light-1",
        "characteristicType": "Power",
        "value": true
      },
      {
        "block": "action",
        "type": "controlDevice",
        "deviceId": "bedroom-light-1",
        "characteristicType": "Brightness",
        "value": 30
      },
      {
        "block": "flowControl",
        "type": "delay",
        "seconds": 300
      },
      {
        "block": "action",
        "type": "controlDevice",
        "deviceId": "bedroom-light-1",
        "characteristicType": "Power",
        "value": false
      }
    ],
    "continueOnError": false
  }
}
```

#### Workflow Block Types

**Action blocks** (atomic operations):

| Type | Fields | Description |
|------|--------|-------------|
| `controlDevice` | `deviceId`, `characteristicType`, `value`, `serviceId?` | Set a device characteristic |
| `webhook` | `url`, `method`, `headers?`, `body?` | Send an HTTP request |
| `log` | `message` | Emit a log entry |

**Flow control blocks** (structural, can contain nested blocks):

| Type | Fields | Description |
|------|--------|-------------|
| `delay` | `seconds` | Pause execution |
| `waitForState` | `deviceId`, `characteristicType`, `condition`, `timeoutSeconds` | Wait until a device reaches a target state |
| `conditional` | `condition`, `thenBlocks`, `elseBlocks?` | If/else branching |
| `repeat` | `count`, `blocks`, `delayBetweenSeconds?` | Fixed-count loop |
| `repeatWhile` | `condition`, `blocks`, `maxIterations`, `delayBetweenSeconds?` | Condition-based loop (safety-capped) |
| `group` | `label?`, `blocks` | Named sub-sequence |

#### Trigger Types

| Type | Fields | Description |
|------|--------|-------------|
| `deviceStateChange` | `deviceId`, `characteristicType`, `condition` | Fire when a device state changes |
| `compound` | `logicOperator` (and/or), `triggers` | Combine multiple triggers |

**Trigger conditions:** `changed`, `equals`, `notEquals`, `transitioned` (from/to), `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`

#### Guard Conditions

Evaluated after a trigger fires but before blocks execute. All must pass.

| Type | Description |
|------|-------------|
| `deviceState` | Check current device characteristic against a comparison |
| `and` | All sub-conditions must be true |
| `or` | Any sub-condition must be true |
| `not` | Negate a condition |

**Comparison operators:** `equals`, `notEquals`, `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`

---

## REST API

All endpoints return JSON. The server runs on the same port as MCP (default `3000`).

### Device Endpoints

#### `GET /devices`

List all devices.

**Response:** Array of device objects.

```json
[
  {
    "id": "ABC-123",
    "name": "Bedroom Light",
    "room": "Bedroom",
    "isReachable": true,
    "services": [
      {
        "id": "service-uuid",
        "name": "Lightbulb",
        "type": "Lightbulb",
        "characteristics": [
          { "id": "char-uuid", "name": "Power", "value": true },
          { "id": "char-uuid", "name": "Brightness", "value": 75 }
        ]
      }
    ]
  }
]
```

#### `GET /devices/:deviceId`

Get a specific device by ID.

**Response:** Single device object (same structure as above).

### Workflow Endpoints

#### `GET /workflows`

List all workflows.

**Response:** Array of workflow objects with full definitions.

#### `GET /workflows/:workflowId`

Get a specific workflow by ID.

**Response:** Single workflow object.

#### `POST /workflows`

Create a new workflow.

**Request body:** Workflow JSON (see [create_workflow](#create_workflow) for schema). The `id`, `createdAt`, `updatedAt`, and `metadata` fields are auto-generated if omitted.

**Response:** `201 Created` with the created workflow object.

#### `PUT /workflows/:workflowId`

Update an existing workflow. Partial updates are supported — only include the fields you want to change.

**Request body:**

```json
{
  "name": "Updated name",
  "isEnabled": false
}
```

**Response:** Updated workflow object.

#### `DELETE /workflows/:workflowId`

Delete a workflow.

**Response:** `{"deleted": true}`

#### `POST /workflows/:workflowId/trigger`

Manually trigger a workflow execution.

**Response:** Execution log with status, timing, and block results.

#### `GET /workflows/:workflowId/logs?limit=50`

Get execution logs for a specific workflow.

**Response:** Array of execution log objects.

### Utility Endpoints

#### `GET /health`

Health check.

**Response:** `ok`

---

## Webhook Notifications

When a device state changes and webhooks are enabled, the server sends an HTTP POST to your configured URL:

```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "deviceId": "ABC-123",
  "deviceName": "Bedroom Light",
  "serviceId": "service-uuid",
  "serviceName": "Lightbulb",
  "characteristicType": "00000025-0000-1000-8000-0026BB765291",
  "characteristicName": "Power",
  "oldValue": false,
  "newValue": true
}
```

Webhooks retry up to 3 times with exponential backoff (2s, 4s delays) on failure.

---

## Supported Device Types

The server supports 30+ HomeKit service types including:

Lightbulb, Fan, Switch, Outlet, Thermostat, Door, Doorbell, Garage Door Opener, Lock, Window, Window Covering, Motion Sensor, Occupancy Sensor, Contact Sensor, Temperature Sensor, Humidity Sensor, Light Sensor, Leak Sensor, Smoke Sensor, CO Sensor, CO2 Sensor, Air Quality Sensor, Security System, Battery, Speaker, Microphone, Air Purifier, Valve, and more.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            MCP / REST Clients            │
                    └─────┬──────────────┬──────────────┬─────┘
                          │              │              │
                    ┌─────▼─────┐  ┌─────▼─────┐  ┌────▼─────┐
                    │ MCP Tools │  │ REST API  │  │ Webhooks │
                    └─────┬─────┘  └─────┬─────┘  └────▲─────┘
                          │              │              │
                    ┌─────▼──────────────▼─────┐        │
                    │     MCPServer (Vapor)     │        │
                    │     MCPRequestHandler     │        │
                    └─────┬──────────────┬─────┘        │
                          │              │              │
               ┌──────────▼───┐    ┌─────▼──────────────┤
               │HomeKitManager│    │  WorkflowEngine    │
               │  (HMHome)    │◀───│  (triggers,        │
               └──────┬───────┘    │   conditions,      │
                      │            │   block execution)  │
                      │            └─────┬──────────────┘
                      │                  │
               ┌──────▼───────┐    ┌─────▼──────────┐
               │   Webhook    │    │   Workflow      │
               │   Service    │    │   Storage       │
               └──────────────┘    └────────────────┘
```

**Layers:**

1. **Views** (SwiftUI) — DeviceListView, LogViewerView, SettingsView, WorkflowListView, WorkflowDetailView, WorkflowEditorView
2. **ViewModels** — Bridge services to UI via `@Published` properties
3. **Services** — HomeKitManager, MCPServer, WorkflowEngine, WebhookService, LoggingService, StorageService
4. **Models** — DeviceModel, Workflow, WorkflowBlock, WorkflowTrigger, StateChangeLog

## Tech Stack

- **Platform**: Mac Catalyst (iOS app running on macOS)
- **Language**: Swift 5.9
- **UI**: SwiftUI + Combine (MVVM)
- **HTTP Server**: [Vapor 4](https://vapor.codes)
- **Smart Home**: Apple HomeKit framework

## License

All rights reserved.
