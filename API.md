# HomeKit MCP — API Reference

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [WebSocket (Real-time Updates)](#websocket-real-time-updates)
- [REST API](#rest-api)
  - [Health](#health)
  - [Devices](#devices)
  - [Scenes](#scenes)
  - [Logs](#logs)
  - [Workflows](#workflows)
  - [Webhook Trigger](#webhook-trigger)
- [MCP Protocol (JSON-RPC 2.0)](#mcp-protocol-json-rpc-20)
  - [Streamable HTTP Transport](#streamable-http-transport)
  - [Legacy SSE Transport](#legacy-sse-transport)
  - [MCP Resources](#mcp-resources)
  - [MCP Tools](#mcp-tools)
- [Outgoing Webhooks](#outgoing-webhooks)
- [Data Models](#data-models)
- [Error Handling](#error-handling)

---

## Overview

The HomeKit MCP server exposes Apple HomeKit devices, scenes, logs, and automation workflows through two complementary interfaces:

- **REST API** — standard HTTP endpoints for CRUD operations
- **MCP Protocol** — JSON-RPC 2.0 over HTTP (Streamable HTTP or legacy SSE) for AI/LLM tool use

| Setting | Default |
|---|---|
| Port | `3000` (configurable) |
| Bind address | All interfaces (configurable) |
| Max request body | 1 MB |

### Feature Flags

Each API surface is independently toggleable in the app settings:

| Flag | Controls |
|---|---|
| REST API enabled | All `/devices`, `/scenes`, `/logs`, `/workflows` endpoints |
| MCP Protocol enabled | `/mcp`, `/sse`, `/messages` endpoints |
| Workflows enabled | Workflow REST endpoints and MCP workflow tools |
| Log Access enabled | `GET /logs` endpoint and `get_logs` MCP tool |
| WebSocket enabled | `GET /ws` WebSocket endpoint for real-time push |

When a feature is disabled, its endpoints return **404 Not Found**.

### CORS

CORS is optionally enabled in settings. When active:

- **Allowed methods**: GET, POST, PUT, DELETE, OPTIONS
- **Allowed headers**: Content-Type, Authorization, Mcp-Session-Id
- **Allowed origins**: configurable (specific list, or all)

---

## Authentication

All endpoints except `GET /health` require a Bearer token.

```
Authorization: Bearer <token>
```

Tokens are managed in the app's settings (stored in Keychain). Multiple tokens are supported for multi-client access.

**Error responses for invalid auth:**

| Condition | Status | Body |
|---|---|---|
| Missing header | 401 | `{"error": "Missing Authorization header"}` |
| Wrong scheme | 401 | `{"error": "Invalid Authorization scheme. Use Bearer."}` |
| Invalid token | 401 | `{"error": "Invalid API token"}` |

---

## WebSocket (Real-time Updates)

The server provides a WebSocket endpoint for pushing real-time log and workflow execution log updates to connected clients.

### Connection

```
GET /ws?token=<bearer-token>
```

Authentication is via the `token` query parameter (browser WebSocket API does not support custom headers). The token is the same Bearer token used for REST/MCP auth.

**Requirements**: Both the "WebSocket enabled" and "Log Access enabled" feature flags must be active. If either is disabled, the connection is rejected with close code `1008` (Policy Violation).

### Message Protocol

All messages are JSON objects with a `type` field.

#### Server → Client

| Type | Description | Payload |
|---|---|---|
| `connected` | Sent on successful connection | `{"type":"connected","connectionId":"<UUID>"}` |
| `log` | New state-change log entry | `{"type":"log","data":{...StateChangeLog...}}` |
| `workflow_log` | New workflow execution started | `{"type":"workflow_log","data":{...WorkflowExecutionLog...}}` |
| `workflow_log_updated` | Existing workflow execution updated (completed/failed) | `{"type":"workflow_log_updated","data":{...WorkflowExecutionLog...}}` |
| `workflows_updated` | Workflow definitions changed (created/updated/deleted/enabled/disabled) | `{"type":"workflows_updated","data":[{...Workflow...}]}` |
| `devices_updated` | Structural device/scene change (added/removed/renamed/reachability) | `{"type":"devices_updated"}` |
| `characteristic_updated` | Single characteristic value changed (only for `webhookEnabled` characteristics) | `{"type":"characteristic_updated","data":{"deviceId":"...","serviceId":"...","characteristicId":"...","characteristicType":"...","value":...,"timestamp":"..."}}` |
| `logs_cleared` | All logs have been cleared on the server | `{"type":"logs_cleared"}` |
| `pong` | Response to client ping | `{"type":"pong"}` |

The `data` field in `log` messages has the same shape as items in the `GET /logs` response. The `data` field in `workflow_log` / `workflow_log_updated` messages has the same shape as items in the `GET /workflows/:id/logs` response. The `data` field in `workflows_updated` messages is an array with the same shape as the `GET /workflows` response. The `data` field in `characteristic_updated` messages contains: `deviceId` (stable registry ID), `serviceId` (stable registry ID), `characteristicId` (stable registry ID), `characteristicType` (HomeKit type string), `value` (the new value), and `timestamp` (ISO 8601). This event is only sent for characteristics with `webhookEnabled = true` in the device configuration, and is batched with a 100ms window.

#### Client → Server

| Type | Description |
|---|---|
| `ping` | Application-level keepalive: `{"type":"ping"}` |

### Example

```javascript
const ws = new WebSocket('ws://localhost:3000/ws?token=YOUR_TOKEN');

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  switch (msg.type) {
    case 'connected':
      console.log('Connected:', msg.connectionId);
      break;
    case 'log':
      console.log('New log:', msg.data);
      break;
    case 'workflow_log':
      console.log('Workflow started:', msg.data);
      break;
    case 'workflow_log_updated':
      console.log('Workflow updated:', msg.data);
      break;
    case 'workflows_updated':
      console.log('Workflows changed:', msg.data);
      break;
  }
};
```

---

## REST API

All REST responses use `Content-Type: application/json` with ISO 8601 date encoding.

### Health

| Method | Path | Auth | Response |
|---|---|---|---|
| `GET` | `/health` | None | `"ok"` (200) |

---

### Devices

Requires: **REST API enabled**

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/devices` | List all devices with current state | `RESTDevice[]` |
| `GET` | `/devices/:deviceId` | Get a single device by ID | `RESTDevice` |

Devices are filtered by the per-characteristic "external access" configuration. Only characteristics marked as externally accessible are included. All IDs in responses are stable app-generated IDs (not raw HomeKit UUIDs).

**404** if device not found.

---

### Scenes

Requires: **REST API enabled**

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/scenes` | List all scenes | `RESTScene[]` |
| `GET` | `/scenes/:sceneId` | Get a single scene by ID | `RESTScene` |
| `POST` | `/scenes/:sceneId/execute` | Execute a scene | See below |

**Execute scene response (200):**

```json
{
  "success": true,
  "scene": "Good Morning"
}
```

**Execute scene error (500):**

```json
{
  "error": "Scene execution failed: ..."
}
```

---

### Logs

Requires: **REST API enabled** + **Log Access enabled**

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/logs` | Get filtered, paginated logs | Paginated log object |
| `DELETE` | `/logs` | Clear all logs (state-change + workflow execution) | `{"cleared": true}` |

**Query Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `categories` | string (comma-separated) | all | Filter by category. Values: `state_change`, `webhook_call`, `webhook_error`, `mcp_call`, `rest_call`, `server_error`, `workflow_execution`, `workflow_error`, `scene_execution`, `scene_error`, `backup_restore` |
| `device_name` | string | — | Case-insensitive substring filter on device name |
| `date` | string | — | Single day filter (`yyyy-MM-dd`). Mutually exclusive with `from`/`to` |
| `from` | string | — | Range start (ISO 8601: `yyyy-MM-dd` or full datetime) |
| `to` | string | — | Range end (ISO 8601) |
| `offset` | integer | `0` | Pagination offset |
| `limit` | integer | `50` | Page size |

**Response:**

```json
{
  "logs": [ ... ],
  "total": 142,
  "offset": 0,
  "limit": 50
}
```

Each log entry is a flat JSON object (see [StateChangeLog](#statechangelog) in Data Models). Workflow entries (categories `workflow_execution` and `workflow_error`) include a nested `workflowExecution` object with the full execution tree (see [WorkflowExecutionLog](#workflowexecutionlog)). Running (in-progress) workflow executions are included in the response.

---

### Workflows

Requires: **REST API enabled** + **Workflows enabled**

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `GET` | `/workflows` | List all workflows | 200 | `Workflow[]` |
| `GET` | `/workflows/:workflowId` | Get a single workflow | 200 | `Workflow` |
| `POST` | `/workflows` | Create a workflow | 201 | `Workflow` |
| `PUT` | `/workflows/:workflowId` | Update a workflow (partial) | 200 | `Workflow` |
| `DELETE` | `/workflows/:workflowId` | Delete a workflow | 200 | `{"deleted": true}` |
| `POST` | `/workflows/:workflowId/trigger` | Trigger a workflow | 202 | `TriggerResult` |
| `GET` | `/workflows/:workflowId/logs` | Get execution history | 200 | `WorkflowExecutionLog[]` |
| `POST` | `/workflows/generate` | Generate a workflow using AI | 201 | `GenerateResult` |

**GET /workflows/:workflowId/logs query params:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `limit` | integer | `50` | Max entries to return |

**POST /workflows — Create**

Send a full `Workflow` JSON body. The following fields are auto-generated and should be omitted: `id`, `createdAt`, `updatedAt`, `metadata`. Defaults: `isEnabled = true`, `continueOnError = false`, `retriggerPolicy = "ignoreNew"`.

**PUT /workflows/:workflowId — Update**

Send a partial JSON body. Only included top-level fields are updated; omitted fields are preserved. Arrays (`triggers`, `conditions`, `blocks`) are replaced wholesale when provided.

Updatable fields: `name`, `description`, `isEnabled`, `continueOnError`, `retriggerPolicy`, `triggers`, `conditions`, `blocks`.

See [Workflow](#workflow) in Data Models for the full schema.

---

### Webhook Trigger

Requires: **REST API enabled** + **Workflows enabled**

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `POST` | `/workflows/webhook/:token` | Trigger workflows by webhook token | 202 | `TriggerResult[]` |

Finds all enabled workflows that have a webhook trigger matching the given token and triggers each one. Returns an array of results.

**404** if no workflows match the token.

---

### AI Workflow Generation

Requires: **REST API enabled** + **Workflows enabled** + **AI enabled** (with a valid API key configured in settings)

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `POST` | `/workflows/generate` | Generate a workflow from a natural language prompt | 201 | `GenerateResult` |

The MCP server acts as a proxy — it enriches the prompt with device context, calls the configured LLM (Claude, OpenAI, or Gemini), parses the response into a workflow, saves it, and returns a summary.

**Request body:**

```json
{ "prompt": "Turn on the living room lights at sunset" }
```

**Success response (201):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Sunset Living Room Lights",
  "description": "Turns on the living room lights every day at sunset"
}
```

**Error responses:**

| Status | Reason |
|---|---|
| 400 | Missing or empty prompt |
| 404 | REST API, Workflows, or AI features disabled |
| 422 | Vague prompt or model refused to generate |
| 500 | AI response could not be parsed into a valid workflow |
| 502 | LLM API network or upstream error |
| 503 | AI not configured (no API key set) |

Error body: `{ "error": "Human-readable error message" }`

---

## MCP Protocol (JSON-RPC 2.0)

Requires: **MCP Protocol enabled**

| Setting | Value |
|---|---|
| Protocol version | `2025-03-26` |
| Supported versions | `2025-03-26`, `2024-11-05` |
| Server name | `HomeKitMCP` |
| Server version | `1.0.0` |

### JSON-RPC Request

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": { ... }
}
```

`id` can be an integer or string. Requests without `id` are treated as notifications (no response, 202 Accepted).

### JSON-RPC Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": { ... }
}
```

### JSON-RPC Error

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Invalid params"
  }
}
```

### Supported Methods

| Method | Description |
|---|---|
| `initialize` | Handshake, returns server capabilities |
| `notifications/initialized` | Client signals initialization complete |
| `ping` | Health check, returns `{}` |
| `resources/list` | List available resources |
| `resources/read` | Read a specific resource by URI |
| `tools/list` | List all available tools |
| `tools/call` | Call a tool by name with arguments |

---

### Streamable HTTP Transport

The modern transport uses a single `/mcp` endpoint.

| Method | Path | Description |
|---|---|---|
| `POST` | `/mcp` | Send JSON-RPC request(s). Supports batch (JSON array). |
| `GET` | `/mcp` | Not supported. Returns 405. |
| `DELETE` | `/mcp` | Terminate a session. Requires `Mcp-Session-Id` header. |

**Session management:**

- On `initialize`, the server returns an `Mcp-Session-Id` response header.
- All subsequent requests must include `Mcp-Session-Id` as a request header.
- Session TTL: 24 hours max lifetime, 1 hour idle timeout.
- Sessions are cleaned up every 5 minutes.

---

### Legacy SSE Transport

The 2024-11-05 transport uses two separate endpoints.

| Method | Path | Description |
|---|---|---|
| `GET` | `/sse` | Opens an SSE stream. Returns `event: endpoint` with the messages URL, then `event: message` for responses. Keepalive comments every 30s. |
| `POST` | `/messages?sessionId=<uuid>` | Send a JSON-RPC request. The `sessionId` query parameter is provided in the initial `endpoint` event. |

---

### MCP Resources

| URI | Name | MIME Type | Description |
|---|---|---|---|
| `homekit://devices` | HomeKit Devices | `application/json` | JSON array of all devices with current state (filtered by access config) |
| `homekit://scenes` | HomeKit Scenes | `application/json` | JSON array of all scenes with their actions |

**Reading a resource:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "resources/read",
  "params": { "uri": "homekit://devices" }
}
```

---

### MCP Tools

All MCP tools return results in the standard content format:

```json
{
  "content": [{ "type": "text", "text": "..." }],
  "isError": false
}
```

For tools that return structured data, the `text` field contains a JSON string.

---

#### Device Tools

##### list_devices

List all HomeKit devices grouped by room.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns markdown-formatted text with device names, status, IDs, services, and characteristics.

---

##### get_device

Get the full state of a specific device.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `device_id` | string | yes | Stable device identifier |

Returns a JSON `RESTDevice` object.

---

##### control_device

Set a characteristic value on a device.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `device_id` | string | yes | Stable device identifier |
| `characteristic_type` | string | yes | Human-readable name or shorthand. Common shorthands: `power`, `brightness`, `hue`, `saturation`, `color_temperature`, `temperature`, `current_temperature`, `target_position`, `lock_state`, `rotation_speed`. Full display names (e.g. `Target Temperature`, `Door State`, `Motion Detected`) are also accepted (case-insensitive). |
| `value` | varies | yes | Value to set. Type depends on characteristic (see below) |
| `service_id` | string | no | Target a specific service when a device has multiple (e.g. fan + light) |

**Value types by characteristic:**

| Characteristic | Type | Range |
|---|---|---|
| `power` | bool | `true` / `false` |
| `brightness` | int | 0–100 |
| `hue` | int | 0–360 |
| `saturation` | int | 0–100 |
| `color_temperature` | int | device-specific (typically 50–400) |
| `temperature` / `target_temperature` | float | device-specific |
| `current_temperature` | float | read-only |
| `target_position` | int | 0–100 |
| `lock_state` | bool | `true` (secured) / `false` (unsecured) |
| `rotation_speed` | int | 0–100 |

All 45+ HomeKit characteristic types are supported. The full display name (e.g., `Target Humidity`, `Door State`, `Active`) can also be used as the `characteristic_type` value. Values are validated against the characteristic's metadata (format, min/max, valid values).

---

##### list_rooms

List all rooms with device counts.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns text list of rooms and the number of devices in each.

---

##### get_room_devices

Get all devices in a room.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `room_name` | string | yes | Room name (case-insensitive) |

Returns JSON array of `RESTDevice` objects.

---

##### get_devices_in_rooms

Get devices across multiple rooms.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `rooms` | string[] | yes | List of room names |

Returns JSON array of matching devices. Reports any rooms not found.

---

##### get_devices_by_type

Get devices filtered by service type.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `types` | string[] | yes | Service types to match (e.g. `["Lightbulb", "Switch"]`). Case-insensitive substring match. |

Returns JSON array of `RESTDevice` objects matching any of the requested types.

---

#### Log Tool

##### get_logs

Get filtered, paginated logs. Requires **Log Access enabled**.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `device_name` | string | no | Case-insensitive substring filter |
| `categories` | string[] | no | Filter by category (see [LogCategory](#logcategory)) |
| `date` | string | no | Single day (`yyyy-MM-dd`). Mutually exclusive with `from`/`to` |
| `from` | string | no | Range start (ISO 8601) |
| `to` | string | no | Range end (ISO 8601) |
| `limit` | integer | no | Page size (default: 50) |
| `offset` | integer | no | Skip entries (default: 0) |

Returns formatted text with log entries showing timestamp, device, characteristic, value changes, and pagination info.

---

#### Scene Tools

##### list_scenes

List all HomeKit scenes.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns text with scene name, type, execution status, action count, and individual actions.

---

##### execute_scene

Execute a scene.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `scene_id` | string | yes | Stable scene identifier |

Returns success message with scene name, or error with reason.

---

#### Workflow Tools

Requires **Workflows enabled**.

##### list_workflows

List all workflows with status and stats.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns markdown text with workflow name, enabled status, trigger/block counts, execution stats, and failure counts.

---

##### get_workflow

Get the full definition of a workflow.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | yes | UUID of the workflow |

Returns complete JSON `Workflow` object.

---

##### create_workflow

Create a new workflow.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow` | object | yes | Complete workflow definition (see [Workflow schema](#workflow)) |

Auto-generated fields (omit from input): `id`, `createdAt`, `updatedAt`, `metadata`.

Defaults: `isEnabled = true`, `continueOnError = false`, `retriggerPolicy = "ignoreNew"`.

Returns success message with the new workflow's ID and name.

---

##### update_workflow

Update an existing workflow (partial update).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | yes | UUID of the workflow |
| `workflow` | object | yes | Partial or full workflow JSON |

Only top-level fields present in the object are replaced. Arrays (`triggers`, `conditions`, `blocks`) are replaced wholesale.

---

##### delete_workflow

Delete a workflow permanently.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | yes | UUID of the workflow |

---

##### enable_workflow

Toggle a workflow on or off.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | yes | UUID of the workflow |
| `enabled` | boolean | yes | `true` to enable, `false` to disable |

---

##### get_workflow_logs

Get execution history for workflows.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | no | Filter to a specific workflow |
| `limit` | integer | no | Max entries (default: 20) |

Returns formatted text with timestamp, status, duration, trigger info, errors, and block results.

---

##### trigger_workflow

Manually trigger a workflow (fire-and-forget).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `workflow_id` | string | yes | UUID of the workflow |

Returns the scheduling outcome based on the retrigger policy. See [TriggerResult](#triggerresult).

---

##### trigger_workflow_webhook

Trigger workflows by webhook token (fire-and-forget).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `token` | string | yes | Webhook token from the trigger definition |

Triggers all workflows with a matching webhook trigger. Returns scheduling outcome for each.

---

## Outgoing Webhooks

When a HomeKit device state changes, the app can send an HTTP POST to a configured webhook URL.

### Payload

```json
{
  "timestamp": "2026-02-25T14:30:00Z",
  "deviceId": "abc-123",
  "deviceName": "Living Room Light",
  "serviceId": "svc-456",
  "serviceName": "Lightbulb",
  "characteristicType": "Power",
  "characteristicName": "Power State",
  "oldValue": false,
  "newValue": true
}
```

| Field | Type | Nullable | Description |
|---|---|---|---|
| `timestamp` | string (ISO 8601) | no | When the change occurred |
| `deviceId` | string | no | Stable device ID |
| `deviceName` | string | no | Human-readable device name |
| `serviceId` | string | yes | Stable service ID |
| `serviceName` | string | yes | Human-readable service name |
| `characteristicType` | string | no | Characteristic type identifier |
| `characteristicName` | string | no | Human-readable characteristic name |
| `oldValue` | any | yes | Previous value |
| `newValue` | any | yes | New value |

### Security

- **HMAC-SHA256 signature**: The request includes an `X-Signature-256` header containing the HMAC-SHA256 hex digest of the JSON body, signed with a shared secret configured in the app.

### Retry Policy

- Max retries: 3
- Backoff: exponential (`2^attempt` seconds — 2s, 4s, 8s)
- Success: HTTP 200–299

### SSRF Protection

Private IP ranges are blocked by default (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8). Localhost is allowed. A wildcard allowlist can be configured for private IPs.

---

## Data Models

### RESTDevice

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | string | no | Stable device ID |
| `name` | string | no | Device name |
| `room` | string | yes | Room name |
| `isReachable` | boolean | no | Whether the device is currently reachable |
| `services` | RESTService[] | no | Array of services on this device |

### RESTService

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | string | no | Stable service ID |
| `name` | string | no | Display name (e.g. "Ceiling Fan Light") |
| `type` | string | no | Service type (e.g. "Lightbulb", "Switch", "Fan") |
| `characteristics` | RESTCharacteristic[] | no | Characteristics on this service |

### RESTCharacteristic

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | string | no | Stable characteristic ID |
| `name` | string | no | Display name (e.g. "Brightness", "Power State") |
| `value` | any | yes | Current value (bool, int, float, or string) |
| `format` | string | no | Value format (e.g. "bool", "uint8", "float") |
| `units` | string | yes | Unit of measurement (e.g. "celsius", "percentage") |
| `permissions` | string[] | no | Access permissions: `"pr"` (read), `"pw"` (write) |
| `minValue` | number | yes | Minimum allowed value |
| `maxValue` | number | yes | Maximum allowed value |
| `stepValue` | number | yes | Step increment |
| `validValues` | RESTValidValue[] | yes | Enumerated valid values with labels |

### RESTValidValue

| Field | Type | Description |
|---|---|---|
| `value` | integer | Numeric value |
| `label` | string | Human-readable label (e.g. "Auto", "Cool", "Heat") |

### RESTScene

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | string | no | Stable scene ID |
| `name` | string | no | Scene name |
| `type` | string | no | Scene type |
| `isExecuting` | boolean | no | Whether currently executing |
| `actionCount` | integer | no | Number of actions |
| `actions` | RESTSceneAction[] | no | Individual actions in the scene |

### RESTSceneAction

| Field | Type | Description |
|---|---|---|
| `deviceName` | string | Target device name |
| `characteristicType` | string | Characteristic being set |
| `targetValue` | any | Value to set |

---

### Workflow

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Auto-generated |
| `name` | string | no | Workflow name |
| `description` | string | yes | Optional description |
| `isEnabled` | boolean | no | Whether the workflow is active |
| `triggers` | WorkflowTrigger[] | no | What starts the workflow |
| `conditions` | WorkflowCondition[] | yes | Guard conditions (all must pass for workflow to run) |
| `blocks` | WorkflowBlock[] | no | Sequence of actions/flow control |
| `continueOnError` | boolean | no | Skip failed blocks instead of stopping |
| `retriggerPolicy` | string | no | Default concurrent execution policy (see below) |
| `metadata` | WorkflowMetadata | no | Execution statistics |
| `createdAt` | string (ISO 8601) | no | Creation timestamp |
| `updatedAt` | string (ISO 8601) | no | Last update timestamp |

**ConcurrentExecutionPolicy values:**

| Value | Behavior |
|---|---|
| `ignoreNew` | Ignore new triggers while running (default) |
| `cancelAndRestart` | Cancel current execution, start new |
| `queueAndExecute` | Queue new trigger, execute after current finishes |
| `cancelOnly` | Cancel current execution, don't restart |

**WorkflowMetadata:**

| Field | Type | Description |
|---|---|---|
| `createdBy` | string? | Creator identifier |
| `tags` | string[]? | Optional tags |
| `lastTriggeredAt` | string? (ISO 8601) | Last trigger timestamp |
| `totalExecutions` | integer | Total execution count |
| `consecutiveFailures` | integer | Consecutive failure count |

---

### WorkflowTrigger

Each trigger has a `type` discriminator and an optional `retriggerPolicy` that overrides the workflow-level default.

#### deviceStateChange

Fires when a device characteristic changes.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"deviceStateChange"` | yes | |
| `name` | string | no | Display name |
| `deviceId` | string | yes | Stable device ID |
| `deviceName` | string | yes | Device name (for cross-device migration) |
| `roomName` | string | yes | Room name |
| `serviceId` | string | no | Specific service |
| `characteristicId` | string | yes | Stable characteristic ID (resolvable via device registry) |
| `condition` | object | no | Trigger condition (see below) |
| `retriggerPolicy` | string | no | Override policy |

**Trigger condition types:**

| Type | Fields | Description |
|---|---|---|
| `changed` | *(none)* | Any value change |
| `equals` | `value` | New value equals |
| `notEquals` | `value` | New value does not equal |
| `greaterThan` | `value` | New value greater than |
| `lessThan` | `value` | New value less than |
| `greaterThanOrEqual` | `value` | New value >= |
| `lessThanOrEqual` | `value` | New value <= |
| `transitioned` | `to` (required), `from` (optional) | Value transitioned from/to |

#### schedule

Time-based trigger.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"schedule"` | yes | |
| `name` | string | no | |
| `scheduleType` | object | yes | Schedule definition (see below) |
| `retriggerPolicy` | string | no | |

**Schedule types:**

| Type | Fields | Description |
|---|---|---|
| `once` | `date` (ISO 8601) | Fire once at specific time |
| `daily` | `time: {hour, minute}` | Fire daily at time |
| `weekly` | `time: {hour, minute}`, `days: [int]` (1=Sun..7=Sat) | Fire on specific days |
| `interval` | `seconds` (int) | Fire every N seconds |

#### sunEvent

Sunrise/sunset trigger.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"sunEvent"` | yes | |
| `name` | string | no | |
| `event` | `"sunrise"` or `"sunset"` | yes | |
| `offsetMinutes` | integer | no | Negative = before, positive = after, 0 = exact |
| `retriggerPolicy` | string | no | |

#### webhook

External HTTP trigger with a unique token.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"webhook"` | yes | |
| `name` | string | no | |
| `token` | string | yes | Unique webhook token |
| `retriggerPolicy` | string | no | |

#### workflow

Makes this workflow callable by other workflows.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"workflow"` | yes | |
| `name` | string | no | |
| `retriggerPolicy` | string | no | |

---

### WorkflowBlock

Blocks use a two-level discriminator: `block` (`"action"` or `"flowControl"`) and `type`.

All blocks accept an optional `name` field.

#### Action Blocks (`"block": "action"`)

##### controlDevice

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"controlDevice"` | yes | |
| `deviceId` | string | yes | Stable device ID |
| `deviceName` | string | yes | For migration |
| `roomName` | string | yes | For migration |
| `serviceId` | string | no | Target specific service |
| `characteristicId` | string | yes | Stable characteristic ID (resolvable via device registry) |
| `value` | any | yes | Value to set |

##### runScene

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"runScene"` | yes | |
| `sceneId` | string | yes | Stable scene ID |
| `sceneName` | string | no | Cached display name |

##### webhook

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"webhook"` | yes | |
| `url` | string | yes | Target URL |
| `method` | string | yes | HTTP method |
| `headers` | object | no | Custom headers |
| `body` | string | no | Request body |

##### log

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"log"` | yes | |
| `message` | string | yes | Message to log |

#### Flow Control Blocks (`"block": "flowControl"`)

##### delay

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"delay"` | yes | |
| `seconds` | number | yes | Pause duration |

##### waitForState

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"waitForState"` | yes | |
| `condition` | WorkflowCondition | yes | Condition to wait for (same format as conditional/repeatWhile — supports AND/OR/NOT groups, deviceState, timeCondition, sceneActive) |
| `timeoutSeconds` | number | yes | Max wait time in seconds |

> **Backward compatibility:** The old flat format (`deviceId`, `characteristicId`, `condition` as ComparisonOperator) is still accepted for decoding and automatically converted to a `WorkflowCondition.deviceState`.

##### conditional

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"conditional"` | yes | |
| `condition` | WorkflowCondition | yes | Condition to evaluate |
| `thenBlocks` | WorkflowBlock[] | yes | Blocks to run if true |
| `elseBlocks` | WorkflowBlock[] | no | Blocks to run if false |

##### repeat

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"repeat"` | yes | |
| `count` | integer | yes | Number of iterations |
| `blocks` | WorkflowBlock[] | yes | Blocks to repeat |
| `delayBetweenSeconds` | number | no | Delay between iterations |

##### repeatWhile

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"repeatWhile"` | yes | |
| `condition` | WorkflowCondition | yes | Continue condition (no `blockResult` allowed) |
| `blocks` | WorkflowBlock[] | yes | Blocks to repeat |
| `maxIterations` | integer | yes | Safety limit |
| `delayBetweenSeconds` | number | no | Delay between iterations |

##### group

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"group"` | yes | |
| `label` | string | no | Group label |
| `blocks` | WorkflowBlock[] | yes | Nested blocks |

##### return

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"return"` | yes | |
| `outcome` | string | yes | `"success"`, `"error"`, or `"cancelled"` |
| `message` | string | no | Optional message |

Exits the current scope (group, repeat, conditional). At top level, terminates the entire workflow.

##### executeWorkflow

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"executeWorkflow"` | yes | |
| `targetWorkflowId` | string (UUID) | yes | Workflow to execute |
| `executionMode` | string | yes | `"inline"`, `"parallel"`, or `"delegate"` |

---

### WorkflowCondition

Conditions are used in workflow-level guards, conditional blocks, and repeatWhile blocks. They support arbitrary nesting via `and`/`or`/`not`.

#### deviceState

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"deviceState"` | yes | |
| `deviceId` | string | yes | |
| `deviceName` | string | yes | |
| `roomName` | string | yes | |
| `serviceId` | string | no | |
| `characteristicId` | string | yes | Stable characteristic ID (resolvable via device registry) |
| `comparison` | object | yes | `{type, value}` — types: `equals`, `notEquals`, `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual` |

#### timeCondition

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"timeCondition"` | yes | |
| `mode` | string | yes | `beforeSunrise`, `afterSunrise`, `beforeSunset`, `afterSunset`, `daytime`, `nighttime`, `timeRange` |
| `startTime` | `{hour, minute}` | for `timeRange` | Start time (0-23, 0-59). Cross-midnight aware. |
| `endTime` | `{hour, minute}` | for `timeRange` | End time |

#### sceneActive

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"sceneActive"` | yes | |
| `sceneId` | string | yes | |
| `isActive` | boolean | yes | |

#### blockResult

Only valid inside `conditional` block conditions. Not allowed in workflow-level guards or `repeatWhile`.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"blockResult"` | yes | |
| `scope` | string | yes | `"specific"`, `"lastBlock"`, or `"anyPreviousBlock"` |
| `blockId` | string (UUID) | for `specific` | Must reference an earlier block |
| `expectedStatus` | string | yes | `"success"`, `"failure"`, or `"cancelled"` |

Requires `continueOnError = true` on the workflow.

#### Logical operators

| Type | Field | Description |
|---|---|---|
| `and` | `conditions: WorkflowCondition[]` | All must pass |
| `or` | `conditions: WorkflowCondition[]` | Any must pass |
| `not` | `condition: WorkflowCondition` | Negates inner condition |

---

### TriggerResult

Returned by workflow trigger endpoints. Encoded as flat JSON.

| Status | HTTP Code | Description |
|---|---|---|
| `scheduled` | 202 | Execution scheduled |
| `replaced` | 202 | Previous cancelled, new scheduled |
| `queued` | 202 | Queued behind current execution |
| `cancelled` | 202 | Current execution cancelled, no restart |
| `ignored` | 409 | Already running, trigger ignored |
| `not_found` | 404 | Workflow not found |
| `disabled` | 503 | Workflows feature disabled |
| `workflow_disabled` | 503 | Specific workflow is disabled |

**JSON shape:**

```json
{
  "status": "scheduled",
  "workflowId": "...",
  "workflowName": "...",
  "message": "Workflow 'Morning Routine' execution scheduled."
}
```

---

### StateChangeLog

Serialized as flat JSON for all log categories.

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Log entry ID |
| `timestamp` | string (ISO 8601) | no | When it occurred |
| `category` | string | no | Log category (see below) |
| `deviceId` | string | no | Device/workflow/scene ID or synthetic ID |
| `deviceName` | string | no | Device/workflow/scene name or synthetic name |
| `serviceId` | string | yes | Service ID (device events only) |
| `serviceName` | string | yes | Service name (device events only) |
| `characteristicType` | string | no | Characteristic type, method name, or subtype |
| `oldValue` | any | yes | Previous value |
| `newValue` | any | yes | New value or status |
| `errorDetails` | string | yes | Error description |
| `requestBody` | string | yes | Summary/trigger description |
| `responseBody` | string | yes | Result/block summary |
| `detailedRequestBody` | string | yes | Full request detail |
| `workflowExecution` | WorkflowExecutionLog | yes | Full workflow execution data (present only for `workflow_execution` and `workflow_error` categories) |

### LogCategory

| Value | Description |
|---|---|
| `state_change` | Device characteristic changed |
| `webhook_call` | Outgoing webhook sent successfully |
| `webhook_error` | Outgoing webhook failed |
| `mcp_call` | MCP tool/resource call |
| `rest_call` | REST API call |
| `server_error` | Server error |
| `workflow_execution` | Workflow executed |
| `workflow_error` | Workflow execution failed |
| `scene_execution` | Scene executed |
| `scene_error` | Scene execution failed |
| `backup_restore` | Backup/restore operation |

### WorkflowExecutionLog

Embedded in `StateChangeLog` entries with `workflow_execution` or `workflow_error` category. Also returned directly by `GET /workflows/:id/logs`.

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Execution log ID |
| `workflowId` | UUID | no | Parent workflow ID |
| `workflowName` | string | no | Workflow name at time of execution |
| `triggeredAt` | string (ISO 8601) | no | When the execution was triggered |
| `completedAt` | string (ISO 8601) | yes | When the execution finished (null if still running) |
| `triggerEvent` | TriggerEvent | yes | What triggered the execution |
| `conditionResults` | ConditionResult[] | yes | Results of workflow-level guard conditions |
| `blockResults` | BlockResult[] | no | Execution results for each block |
| `status` | ExecutionStatus | no | Current execution status |
| `errorMessage` | string | yes | Top-level error message |

#### ExecutionStatus

| Value | Description |
|---|---|
| `running` | Currently executing |
| `success` | Completed successfully |
| `failure` | Failed with an error |
| `skipped` | Skipped (e.g. condition not met for a block) |
| `conditionNotMet` | Workflow-level guard conditions not met |
| `cancelled` | Cancelled (by retrigger policy or return block) |

#### TriggerEvent

| Field | Type | Nullable | Description |
|---|---|---|---|
| `deviceId` | string | yes | Device that triggered the workflow |
| `deviceName` | string | yes | Device name |
| `serviceId` | string | yes | Service ID |
| `characteristicType` | string | yes | Characteristic that changed |
| `oldValue` | any | yes | Previous value |
| `newValue` | any | yes | New value |
| `triggerDescription` | string | yes | Human-readable trigger description |

#### ConditionResult

| Field | Type | Nullable | Description |
|---|---|---|---|
| `conditionDescription` | string | no | Human-readable description of the condition |
| `passed` | boolean | no | Whether the condition passed |
| `subResults` | ConditionResult[] | yes | Nested results for logical operators |
| `logicOperator` | string | yes | `"and"`, `"or"`, or `"not"` for compound conditions |

#### BlockResult

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Block result ID |
| `blockIndex` | integer | no | Position in the block list |
| `blockKind` | string | no | `"action"` or `"flowControl"` |
| `blockType` | string | no | Block type: `controlDevice`, `delay`, `conditional`, `repeat`, `repeatWhile`, `group`, `return`, `webhook`, `log`, `runScene`, `waitForState`, `executeWorkflow` |
| `blockName` | string | yes | Optional block display name |
| `status` | ExecutionStatus | no | Block execution status |
| `startedAt` | string (ISO 8601) | no | When block execution started |
| `completedAt` | string (ISO 8601) | yes | When block execution finished |
| `detail` | string | yes | Execution detail (e.g. value set, scene name) |
| `errorMessage` | string | yes | Error message if block failed |
| `nestedResults` | BlockResult[] | yes | Results for nested blocks (conditional, repeat, group) |

---

## Error Handling

### HTTP Status Codes

| Code | Meaning |
|---|---|
| 200 | Success |
| 201 | Created (POST /workflows) |
| 202 | Accepted (workflow triggers, MCP notifications) |
| 400 | Bad request (invalid params, malformed JSON) |
| 401 | Unauthorized (missing/invalid Bearer token) |
| 404 | Not found (resource missing or feature disabled) |
| 405 | Method not allowed |
| 409 | Conflict (trigger ignored — workflow already running) |
| 500 | Internal server error |
| 503 | Service unavailable (server starting/stopping, feature disabled) |

### JSON-RPC Error Codes

| Code | Name | Description |
|---|---|---|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid request | Not a valid JSON-RPC request |
| -32601 | Method not found | Unknown method |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Server-side error |
