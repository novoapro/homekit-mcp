# HomeKit MCP Server

A macOS menu bar app that exposes your Apple HomeKit devices through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). Connect AI assistants like Claude to your smart home — query device states, control accessories, create automation workflows, and receive real-time updates when things change.

## Features

- **MCP Server** — JSON-RPC over Streamable HTTP and legacy SSE, exposing device resources, control tools, and workflow automation tools
- **REST API** — Full HTTP REST interface for devices, scenes, logs, and workflows
- **Real-time monitoring** — Observes HomeKit accessory state changes via `HMAccessoryDelegate` with optional polling fallback
- **Device control** — Turn lights on/off, adjust brightness, set thermostats, lock/unlock doors, and more
- **Scene support** — List and execute HomeKit scenes
- **Workflow automation** — Create, manage, and execute automation workflows with triggers (device state, schedule, sun events, webhooks), conditions (device state, time, scene), and action blocks (device control, delays, conditionals, loops, groups, HTTP calls, scene execution, sub-workflow calls)
- **AI workflow generation** — Generate workflows from natural language using Claude, OpenAI, or Gemini
- **WebSocket push** — Real-time broadcast of log entries, workflow executions, and device updates to connected clients
- **Webhook notifications** — HTTP POST callbacks on state changes with HMAC-SHA256 signing and exponential backoff retry
- **State logging** — Configurable circular buffer of activity logs (state changes, API calls, webhook events, workflow executions), persisted to disk
- **iCloud sync** — Optional CloudKit-based workflow sync and backup across devices
- **Stable device IDs** — App-generated stable identifiers that survive HomeKit re-pairing
- **Per-characteristic access control** — Configure which characteristics are exposed externally and to webhooks
- **Multi-token auth** — Multiple Bearer tokens for different clients, stored in Keychain
- **Web dashboard** — Companion React web app for viewing logs, managing workflows, and monitoring devices (see [log-viewer-web/](log-viewer-web/))
- **Menu bar app** — Runs unobtrusively in the macOS menu bar (no Dock icon)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node.js 22+ (for the web dashboard)
- HomeKit-compatible accessories configured in the Apple Home app
- An Apple Developer account (for HomeKit entitlement)

## Quick Start

```bash
# Generate the Xcode project from project.yml
make generate

# Build and launch in dev mode (auto-accepts a default auth token)
make dev

# Install web dashboard dependencies & start dev server
make web-install
make web-dev
```

In **dev mode**, the bearer token `dev-token-homekit-mcp` is automatically accepted — no manual Keychain setup needed.

## Make Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make generate` | Generate the Xcode project from `project.yml` |
| `make dev` | Build and launch in **Dev** mode (auto-accepts dev token) |
| `make dev-all` | Build and run **both** apps in Dev mode, opens browser |
| `make prod` | Build and launch in **Prod** mode (requires real Keychain tokens) |
| `make test` | Run all tests (Swift + web) |
| `make test-swift` | Run Swift unit tests only |
| `make test-web` | Run web unit tests only |
| `make web-dev` | Start the web dashboard dev server |
| `make web-build` | Build the web dashboard for production |
| `make web-prod` | Build and run web dashboard via Docker |
| `make web-install` | Install web dashboard npm dependencies |
| `make clean` | Clean Xcode build artifacts |
| `make kill` | Kill running HomeKitMCP process |

## Build Configurations

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) with four build configurations:

| Configuration | Scheme | Use Case |
|---------------|--------|----------|
| **Dev Debug** | `HomeKitMCP` | Local development with debugger (`make dev`) |
| **Dev Release** | `HomeKitMCP` | Optimized dev build |
| **Prod Debug** | `HomeKitMCP-Prod` | Production behavior with debugger (`make prod`) |
| **Prod Release** | `HomeKitMCP-Prod` | Distribution build |

**Dev** builds compile with the `DEV_ENVIRONMENT` flag, which injects a well-known dev token (`dev-token-homekit-mcp`) so you don't need to configure Keychain tokens during development.

**Prod** builds behave like the final app — tokens must be created and stored in the Keychain through the app's settings UI.

## Testing

```bash
# Run all tests (Swift + web)
make test

# Swift tests only (DeviceRegistryService, etc.)
make test-swift

# Web tests only (Vitest)
make test-web

# Web tests in watch mode
cd log-viewer-web && npm run test:watch
```

## CI/CD

GitHub Actions runs automatically on every push and PR to `main`:

- **Swift job** (macOS): generates project via XcodeGen, builds, runs unit tests
- **Web job** (Ubuntu): TypeScript type-check, Vitest tests, production build

See [.github/workflows/ci.yml](.github/workflows/ci.yml) for details. GitHub Actions is free for public repositories and includes 2,000 minutes/month for private repos on the free tier.

## Getting Started (Manual)

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

Authentication is required for all endpoints except `/health`. Configure Bearer tokens in the app's Server Settings.

## Configuration

Settings are available in the app's Settings view:

### General

| Setting | Default | Description |
|---------|---------|-------------|
| Hide Room Name | `false` | Strip room prefix from device display names |

### Server

| Setting | Default | Description |
|---------|---------|-------------|
| MCP Server Port | `3000` | HTTP port for the MCP and REST server |
| Bind Address | All interfaces | Network interface to listen on |
| Enable External Access | `true` | Start/stop the MCP and REST server |
| MCP Protocol | `true` | Enable MCP JSON-RPC endpoints (`/mcp`, `/sse`) |
| REST API | `true` | Enable REST endpoints (`/devices`, `/workflows`, etc.) |
| CORS | `false` | Enable CORS headers with configurable allowed origins |
| WebSocket | `true` | Enable real-time WebSocket push at `/ws` |
| API Tokens | — | Manage multiple Bearer tokens for authentication |

### Webhooks

| Setting | Default | Description |
|---------|---------|-------------|
| Enable Webhooks | `false` | Send HTTP POST on device state changes |
| Webhook URL | — | Destination URL for webhook notifications |
| Private IP Allowlist | — | Wildcard patterns for allowed private IPs |

### Logging

| Setting | Default | Description |
|---------|---------|-------------|
| Detailed Logs | `false` | Log full request/response JSON bodies |
| Log Access via API | `true` | Expose logs through MCP `get_logs` tool and REST `/logs` endpoint |
| Device State Logging | `true` | Log HomeKit state changes |
| Log Only Webhook Devices | `false` | Only log changes for webhook-configured devices |
| Log Cache Size | `500` | Maximum number of log entries to keep in memory |

### Workflows

| Setting | Default | Description |
|---------|---------|-------------|
| Enable Workflows | `true` | Enable the workflow automation engine |
| iCloud Sync | `false` | Sync workflows across devices via CloudKit |

### AI Assistant

| Setting | Default | Description |
|---------|---------|-------------|
| Enable AI | `false` | Enable AI-powered workflow generation |
| AI Provider | Claude | LLM provider (Claude, OpenAI, or Gemini) |
| Model ID | — | Specific model to use |
| API Key | — | Provider API key (stored in Keychain) |

### Polling

| Setting | Default | Description |
|---------|---------|-------------|
| Enable Polling | `false` | Poll for state changes as a fallback to delegate callbacks |
| Polling Interval | `30s` | Seconds between poll cycles |

---

## MCP API

The server implements the [Model Context Protocol](https://modelcontextprotocol.io) with both Streamable HTTP (2025-03-26) and legacy SSE (2024-11-05) transports.

### Resources

| URI | Description |
|-----|-------------|
| `homekit://devices` | JSON array of all HomeKit devices with current states |
| `homekit://scenes` | JSON array of all HomeKit scenes with their actions |

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

### Scene Tools

| Tool | Description |
|------|-------------|
| `list_scenes` | List all HomeKit scenes with actions |
| `execute_scene` | Execute a scene by ID |

### Log Tool

| Tool | Description |
|------|-------------|
| `get_logs` | Get recent logs with filtering by device, category, date/date range, and pagination |

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
| `trigger_workflow_webhook` | Trigger workflows by webhook token |
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

**Supported characteristic names:** `power`, `brightness`, `hue`, `saturation`, `color_temperature`, `target_temperature`, `target_position`, `lock_state`, `rotation_speed`, and 35+ more. Full display names (e.g. `Target Temperature`) are also accepted (case-insensitive).

#### `get_logs`

```json
{
  "device_name": "Bedroom Light",
  "categories": ["state_change", "mcp_call"],
  "date": "2025-01-15",
  "limit": 50,
  "offset": 0
}
```

All parameters are optional. Filter by:

- **`device_name`** — case-insensitive substring match on device name
- **`categories`** — array of log category values: `state_change`, `webhook_call`, `webhook_error`, `mcp_call`, `rest_call`, `server_error`, `workflow_execution`, `workflow_error`, `scene_execution`, `scene_error`, `backup_restore`
- **`date`** — single calendar day (e.g. `2025-01-15`). Mutually exclusive with `from`/`to`
- **`from`** / **`to`** — date range (ISO 8601, e.g. `2025-01-01` or `2025-01-01T00:00:00Z`)
- **`limit`** — page size (default 50)
- **`offset`** — entries to skip for pagination (default 0)

Requires the "Log Access via API" setting to be enabled.

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
| `runScene` | `sceneId`, `sceneName?` | Execute a HomeKit scene |
| `webhook` | `url`, `method`, `headers?`, `body?` | Send an HTTP request |
| `log` | `message` | Emit a log entry |

**Flow control blocks** (structural, can contain nested blocks):

| Type | Fields | Description |
|------|--------|-------------|
| `delay` | `seconds` | Pause execution |
| `waitForState` | `condition`, `timeoutSeconds` | Wait until a condition is met |
| `conditional` | `condition`, `thenBlocks`, `elseBlocks?` | If/else branching |
| `repeat` | `count`, `blocks`, `delayBetweenSeconds?` | Fixed-count loop |
| `repeatWhile` | `condition`, `blocks`, `maxIterations`, `delayBetweenSeconds?` | Condition-based loop (safety-capped) |
| `group` | `label?`, `blocks` | Named sub-sequence |
| `return` | `outcome`, `message?` | Exit current scope with success/error/cancelled |
| `executeWorkflow` | `targetWorkflowId`, `executionMode` | Call another workflow (inline/parallel/delegate) |

#### Trigger Types

| Type | Fields | Description |
|------|--------|-------------|
| `deviceStateChange` | `deviceId`, `characteristicType`, `condition` | Fire when a device state changes |
| `schedule` | `scheduleType` | Time-based (once, daily, weekly, interval) |
| `sunEvent` | `event`, `offsetMinutes?` | Sunrise/sunset with optional offset |
| `webhook` | `token` | External HTTP trigger with unique token |
| `workflow` | — | Makes this workflow callable by other workflows |

**Trigger conditions:** `changed`, `equals`, `notEquals`, `transitioned` (from/to), `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`

#### Guard Conditions

Evaluated after a trigger fires but before blocks execute. All must pass.

| Type | Description |
|------|-------------|
| `deviceState` | Check current device characteristic against a comparison |
| `timeCondition` | Time-based condition (before/after sunrise/sunset, daytime, nighttime, time range) |
| `blockResult` | Check the result of a previous block (requires `continueOnError`) |
| `and` | All sub-conditions must be true |
| `or` | Any sub-condition must be true |
| `not` | Negate a condition |

---

## REST API

All endpoints return JSON. The server runs on the same port as MCP (default `3000`). See [API.md](API.md) for the complete API reference with request/response schemas.

### Device Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/devices` | List all devices with current state |
| `GET` | `/devices/:deviceId` | Get a specific device by ID |

### Scene Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/scenes` | List all scenes |
| `GET` | `/scenes/:sceneId` | Get a specific scene by ID |
| `POST` | `/scenes/:sceneId/execute` | Execute a scene |

### Log Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/logs` | Get filtered, paginated logs |
| `DELETE` | `/logs` | Clear all logs |

### Workflow Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/workflows` | List all workflows |
| `GET` | `/workflows/:workflowId` | Get a specific workflow |
| `POST` | `/workflows` | Create a new workflow |
| `PUT` | `/workflows/:workflowId` | Update a workflow (partial) |
| `DELETE` | `/workflows/:workflowId` | Delete a workflow |
| `POST` | `/workflows/:workflowId/trigger` | Manually trigger a workflow |
| `GET` | `/workflows/:workflowId/logs` | Get execution logs |
| `POST` | `/workflows/generate` | AI-generate a workflow from prompt |
| `POST` | `/workflows/webhook/:token` | Trigger workflows by webhook token |

### WebSocket

```
GET /ws?token=<bearer-token>
```

Real-time push of log entries, workflow executions, workflow definition changes, and device updates. See [API.md](API.md) for the full message protocol.

### Utility Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check (no auth required) |

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

- **HMAC-SHA256 signed** via `X-Signature-256` header
- **Retry policy:** up to 3 attempts with exponential backoff (2s, 4s, 8s)
- **SSRF protection:** private IP ranges blocked by default, configurable allowlist

---

## Web Dashboard

A companion React web application for monitoring and managing your HomeKit MCP server. See [log-viewer-web/](log-viewer-web/) for setup instructions and details.

Features include:
- Real-time activity log viewer with filtering and search
- Workflow management (create, edit, duplicate, delete)
- Visual workflow editor with drag-and-drop block reordering
- Workflow execution history and detailed block-level results
- AI-powered workflow generation from natural language
- WebSocket-based live updates
- Configurable server connection with Bearer token auth

---

## Supported Device Types

The server supports 30+ HomeKit service types including:

Lightbulb, Fan, Switch, Outlet, Thermostat, Door, Doorbell, Garage Door Opener, Lock, Window, Window Covering, Motion Sensor, Occupancy Sensor, Contact Sensor, Temperature Sensor, Humidity Sensor, Light Sensor, Leak Sensor, Smoke Sensor, CO Sensor, CO2 Sensor, Air Quality Sensor, Security System, Battery, Speaker, Microphone, Air Purifier, Valve, and more.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │     MCP / REST / WebSocket Clients       │
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

1. **Views** (SwiftUI) — DeviceListView, SceneListView, LogViewerView, SettingsView, WorkflowListView, WorkflowDetailView, WorkflowEditorView, WorkflowBuilderView
2. **ViewModels** — HomeKitViewModel, LogViewModel, SettingsViewModel, WorkflowViewModel — bridge services to UI via `@Published` properties
3. **Services** — HomeKitManager, MCPServer, MCPRequestHandler, WorkflowEngine, ScheduleTriggerManager, WebhookService, LoggingService, StorageService, DeviceRegistryService, DeviceConfigurationService, AIWorkflowService, BackupService, CloudBackupService, WorkflowSyncService, KeychainService
4. **Models** — DeviceModel, Workflow, WorkflowBlock, WorkflowTrigger, WorkflowCondition, StateChangeLog, SceneModel, RESTModels

## Tech Stack

- **Platform**: Mac Catalyst (iOS app running on macOS)
- **Language**: Swift 5.9+, minimum macOS 13.0 (Ventura)
- **UI**: SwiftUI + Combine (MVVM)
- **HTTP Server**: [Vapor 4](https://vapor.codes)
- **Smart Home**: Apple HomeKit framework
- **Web Dashboard**: React 19, TypeScript, Vite, Tailwind CSS v4

## License

All rights reserved.
