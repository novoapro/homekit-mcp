# CompAI - Home — API Reference

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
  - [Bearer Tokens](#bearer-tokens)
  - [OAuth 2.1 (PKCE)](#oauth-21-pkce)
- [OAuth 2.1 Endpoints](#oauth-21-endpoints)
  - [Discovery](#discovery)
  - [Authorization](#authorization)
  - [Token](#token)
  - [Credential Management](#credential-management)
- [WebSocket (Real-time Updates)](#websocket-real-time-updates)
- [REST API](#rest-api)
  - [Health](#health)
  - [Devices](#devices)
  - [Scenes](#scenes)
  - [Logs](#logs)
  - [automations](#automations)
  - [Subscription](#subscription)
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

The CompAI - Home server exposes Apple HomeKit devices, scenes, logs, and automations through two complementary interfaces:

- **REST API** — standard HTTP endpoints for CRUD operations
- **MCP Protocol** — JSON-RPC 2.0 over HTTP (Streamable HTTP or legacy SSE) for AI/LLM tool use

| Setting | Default |
|---|---|
| Port | `3000` (configurable) |
| Bind address | `127.0.0.1` (configurable) |
| Max request body | 1 MB |
| Temperature unit | `celsius` (configurable: `celsius` or `fahrenheit`) |

### Temperature Unit

A global temperature unit preference controls how temperature values are exposed across all surfaces. When set to `fahrenheit`, all temperature characteristics (Current Temperature, Target Temperature) have their `value`, `minValue`, `maxValue`, and `stepValue` converted from Celsius to Fahrenheit, and the `units` field reads `"fahrenheit"` instead of `"celsius"`. This applies to REST API responses, MCP tool results, WebSocket broadcasts, and the native app UI.

- **Outgoing values** (device state, logs, WebSocket events): Converted from Celsius to the configured unit at the point of creation/output.
- **Incoming values** (`control_device`, automation actions): Accepted in the configured unit and converted back to Celsius before sending to HomeKit.
- **Logs**: Persisted in the unit active at the time of creation. Changing the unit does not retroactively convert existing log entries.
- **automations**: When the unit preference changes, all automation definitions are automatically migrated — temperature thresholds in triggers, conditions, and actions are converted to the new unit.

### Feature Flags

Each API surface is independently toggleable in the app settings:

| Flag | Controls |
|---|---|
| REST API enabled | All `/devices`, `/scenes`, `/logs`, `/automations` endpoints |
| MCP Protocol enabled | `/mcp`, `/sse`, `/messages` endpoints |
| automations enabled | automation REST endpoints and MCP automation tools |
| Log Access enabled | `GET /logs` endpoint and `get_logs` MCP tool |
| WebSocket enabled | `GET /ws` WebSocket endpoint for real-time push |
| Pro subscription | Automation and AI endpoints (returns 402 when not subscribed) |

When a feature is disabled, its endpoints return **404 Not Found**.

### CORS

CORS is optionally enabled in settings. When active:

- **Allowed methods**: GET, POST, PUT, DELETE, OPTIONS
- **Allowed headers**: Content-Type, Authorization, Mcp-Session-Id
- **Allowed origins**: configurable (specific list, or all)

---

## Authentication

All endpoints except `GET /health` and the OAuth 2.1 endpoints (`/.well-known/oauth-authorization-server`, `GET /oauth/authorize`, `POST /oauth/token`) require authentication.

Two authentication methods are supported and can be used interchangeably:

### Bearer Tokens

Static tokens managed in the app's Settings (stored in Keychain). Multiple tokens are supported for multi-client access.

```
Authorization: Bearer <token>
```

### OAuth 2.1 (PKCE)

Dynamic tokens obtained via the OAuth 2.1 authorization code flow with PKCE (S256), per MCP spec 2025-03-26. Access tokens are issued as Bearer tokens and used identically to static tokens on all requests.

**Token lifetimes:**

| Token type | Lifetime |
|---|---|
| Access token | 1 hour |
| Refresh token | 30 days |

See [OAuth 2.1 Endpoints](#oauth-21-endpoints) for the full flow.

**Error responses for invalid auth:**

| Condition | Status | Body |
|---|---|---|
| Missing header | 401 | `{"error": "Missing Authorization header"}` |
| Wrong scheme | 401 | `{"error": "Invalid Authorization scheme. Use Bearer."}` |
| Invalid token | 401 | `{"error": "Invalid API token"}` |

---

## OAuth 2.1 Endpoints

These endpoints implement OAuth 2.1 with PKCE (S256) as required by the MCP specification (version 2025-03-26). They enable third-party clients (e.g. AI assistants, automations platforms) to obtain short-lived access tokens without handling static API keys.

### Discovery

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/.well-known/oauth-authorization-server` | None | OAuth 2.0 Authorization Server Metadata (RFC 8414) |

Returns server metadata JSON describing the supported endpoints and capabilities. No authentication required.

**Response (200):**

```json
{
  "issuer": "http://127.0.0.1:3000",
  "authorization_endpoint": "http://127.0.0.1:3000/oauth/authorize",
  "token_endpoint": "http://127.0.0.1:3000/oauth/token",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["client_secret_post"]
}
```

---

### Authorization

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/oauth/authorize` | None | Initiate authorization code flow |

Begins the OAuth 2.1 authorization code flow. Since all registered clients are pre-authorized (credentials created in Settings), the server immediately redirects to `redirect_uri` with a one-time authorization code. No login or consent screen is shown.

**Query parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `response_type` | string | yes | Must be `code` |
| `client_id` | string | yes | Registered OAuth client ID |
| `code_challenge` | string | yes | PKCE code challenge (base64url-encoded SHA-256 of the verifier) |
| `code_challenge_method` | string | yes | Must be `S256` |
| `redirect_uri` | string | yes | Callback URL. Must match the registered redirect URI for the client. |
| `state` | string | no | Opaque value for CSRF protection. Returned unchanged in the redirect. |
| `scope` | string | no | Requested scope. Defaults to `*` (all permissions). |

**Success — 302 redirect to `redirect_uri`:**

```
https://your-app.example.com/callback?code=AUTH_CODE&state=ORIGINAL_STATE
```

**Success — 200 JSON (programmatic clients):**

When the request includes an `Accept: application/json` header, the server returns the authorization code directly as JSON instead of a 302 redirect. This is intended for programmatic clients such as the web dashboard that cannot follow redirects.

```json
{
  "code": "AUTH_CODE",
  "state": "ORIGINAL_STATE"
}
```

The `state` field is omitted if it was not included in the request. The response includes `Cache-Control: no-store`.

**Error — 302 redirect to `redirect_uri`:**

```
https://your-app.example.com/callback?error=access_denied&state=ORIGINAL_STATE
```

**Error — 400 JSON (when redirect_uri is missing or invalid):**

```json
{
  "error": "invalid_request",
  "error_description": "redirect_uri is required"
}
```

**Standard OAuth error codes:**

| Code | Description |
|---|---|
| `invalid_request` | Missing or invalid parameter |
| `unauthorized_client` | Client not authorized to use this flow |
| `access_denied` | User denied authorization |
| `unsupported_response_type` | `response_type` is not `code` |
| `invalid_scope` | Requested scope is invalid |
| `server_error` | Unexpected server error |

---

### Token

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/oauth/token` | None | Exchange authorization code or refresh token |

Exchanges an authorization code for tokens, or refreshes an existing access token. No authentication required — the client is authenticated by its `client_id`/`client_secret` and the PKCE verifier.

**Content-Type:** `application/x-www-form-urlencoded` or `application/json`

**Request body — Authorization code grant:**

| Field | Type | Required | Description |
|---|---|---|---|
| `grant_type` | string | yes | `authorization_code` |
| `code` | string | yes | Authorization code received from `/oauth/authorize` |
| `client_id` | string | yes | OAuth client ID |
| `client_secret` | string | yes | Client secret |
| `code_verifier` | string | yes | PKCE code verifier (plain text, 43–128 chars) |
| `redirect_uri` | string | yes | Must match the value used in the authorization request |

```bash
curl -X POST http://localhost:3000/oauth/token \
  -d "grant_type=authorization_code" \
  -d "code=AUTH_CODE" \
  -d "client_id=my-client" \
  -d "client_secret=my-secret" \
  -d "code_verifier=VERIFIER_STRING" \
  -d "redirect_uri=https://your-app.example.com/callback"
```

**Request body — Refresh token grant:**

| Field | Type | Required | Description |
|---|---|---|---|
| `grant_type` | string | yes | `refresh_token` |
| `refresh_token` | string | yes | Previously issued refresh token |
| `client_id` | string | yes | OAuth client ID |
| `client_secret` | string | yes | Client secret |

```bash
curl -X POST http://localhost:3000/oauth/token \
  -d "grant_type=refresh_token" \
  -d "refresh_token=REFRESH_TOKEN" \
  -d "client_secret=my-secret" \
  -d "client_id=my-client"
```

**Success response (200):**

```json
{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "rt_..."
}
```

| Field | Type | Description |
|---|---|---|
| `access_token` | string | Bearer token for API requests. Valid for 1 hour. |
| `token_type` | string | Always `Bearer` |
| `expires_in` | integer | Seconds until the access token expires (3600) |
| `refresh_token` | string | Token for obtaining new access tokens. Valid for 30 days. |

**Error response (400):**

```json
{
  "error": "invalid_grant",
  "error_description": "Authorization code has expired or already been used"
}
```

**Standard token error codes:**

| Code | HTTP | Description |
|---|---|---|
| `invalid_request` | 400 | Missing or malformed parameter |
| `invalid_client` | 401 | Unknown or unauthorized client |
| `invalid_grant` | 400 | Code expired, already used, or verifier mismatch |
| `unsupported_grant_type` | 400 | `grant_type` is not `authorization_code` or `refresh_token` |
| `invalid_scope` | 400 | Requested scope is invalid |

---

### Credential Management

Requires: **Bearer auth** (static token or OAuth access token)

Manage OAuth credentials (client registrations). These endpoints allow creating, listing, revoking, and deleting OAuth client credentials.

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/oauth/credentials` | Bearer | List all OAuth credentials |
| `POST` | `/oauth/credentials` | Bearer | Create a new OAuth credential |
| `POST` | `/oauth/credentials/:id/revoke` | Bearer | Revoke a credential (invalidate all tokens) |
| `DELETE` | `/oauth/credentials/:id` | Bearer | Delete a credential permanently |

---

#### GET /oauth/credentials

List all registered OAuth credentials.

```bash
curl http://localhost:3000/oauth/credentials \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response (200):**

```json
[
  {
    "id": "cred-uuid",
    "clientId": "my-client",
    "name": "Claude Desktop",
    "createdAt": "2026-03-18T10:00:00Z",
    "lastUsedAt": "2026-03-18T12:30:00Z",
    "isRevoked": false
  }
]
```

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | string | no | Credential UUID |
| `clientId` | string | no | OAuth client identifier |
| `name` | string | no | Human-readable label |
| `createdAt` | string (ISO 8601) | no | When the credential was created |
| `lastUsedAt` | string (ISO 8601) | yes | When this credential last exchanged a token |
| `isRevoked` | boolean | no | Whether the credential has been revoked |

---

#### POST /oauth/credentials

Create a new OAuth credential (client registration).

**Request body (JSON):**

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Human-readable label for the credential |
| `redirectUris` | string[] | yes | Allowed redirect URIs for the authorization flow |
| `clientSecret` | string | no | Client secret. Omit for public clients (PKCE-only). |

```bash
curl -X POST http://localhost:3000/oauth/credentials \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Claude Desktop",
    "redirectUris": ["https://claude.ai/oauth/callback"]
  }'
```

**Response (201):**

```json
{
  "id": "cred-uuid",
  "clientId": "my-client-id",
  "clientSecret": "cs_...",
  "name": "Claude Desktop",
  "redirectUris": ["https://claude.ai/oauth/callback"],
  "createdAt": "2026-03-18T10:00:00Z"
}
```

> **Note:** `clientSecret` is returned only on creation and cannot be retrieved later. Store it securely.

**Error responses:**

| Status | Reason |
|---|---|
| 400 | Missing required field (`name` or `redirectUris`) |
| 400 | `redirectUris` is empty or contains invalid URIs |

---

#### POST /oauth/credentials/:id/revoke

Revoke a credential. All active access tokens and refresh tokens issued for this credential are immediately invalidated. The credential record is retained but marked as revoked.

```bash
curl -X POST http://localhost:3000/oauth/credentials/cred-uuid/revoke \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response (200):**

```json
{
  "revoked": true
}
```

**Error responses:**

| Status | Reason |
|---|---|
| 404 | Credential not found |

---

#### DELETE /oauth/credentials/:id

Permanently delete a credential and all associated tokens.

```bash
curl -X DELETE http://localhost:3000/oauth/credentials/cred-uuid \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Response (200):**

```json
{
  "deleted": true
}
```

**Error responses:**

| Status | Reason |
|---|---|
| 404 | Credential not found |

---

## WebSocket (Real-time Updates)

The server provides a WebSocket endpoint for pushing real-time log and automation execution log updates to connected clients.

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
| `automation_log` | New automation execution started | `{"type":"automation_log","data":{...AutomationExecutionLog...}}` |
| `automation_log_updated` | Existing automation execution updated (completed/failed) | `{"type":"automation_log_updated","data":{...AutomationExecutionLog...}}` |
| `automations_updated` | automation definitions changed (created/updated/deleted/enabled/disabled) | `{"type":"automations_updated","data":[{...automation...}]}` |
| `devices_updated` | Structural device/scene change (added/removed/renamed/reachability) | `{"type":"devices_updated"}` |
| `characteristic_updated` | Single characteristic value changed (only for `observed` characteristics) | `{"type":"characteristic_updated","data":{"deviceId":"...","serviceId":"...","characteristicId":"...","characteristicType":"...","value":...,"timestamp":"..."}}` |
| `logs_cleared` | All logs have been cleared on the server | `{"type":"logs_cleared"}` |
| `subscription_changed` | Subscription tier changed (purchased/expired/restored) | `{"type":"subscription_changed","data":{"tier":"pro","isPro":true}}` |
| `pong` | Response to client ping | `{"type":"pong"}` |

The `data` field in `log` messages has the same shape as items in the `GET /logs` response. The `data` field in `automation_log` / `automation_log_updated` messages has the same shape as items in the `GET /automations/:id/logs` response. The `data` field in `automations_updated` messages is an array with the same shape as the `GET /automations` response. The `data` field in `characteristic_updated` messages contains: `deviceId` (stable registry ID), `serviceId` (stable registry ID), `characteristicId` (stable registry ID), `characteristicType` (HomeKit type string), `value` (the new value), and `timestamp` (ISO 8601). This event is only sent for characteristics marked as `observed` in the device registry, and is batched with a 100ms window.

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
    case 'automation_log':
      console.log('automation started:', msg.data);
      break;
    case 'automation_log_updated':
      console.log('automation updated:', msg.data);
      break;
    case 'automations_updated':
      console.log('automations changed:', msg.data);
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

Devices are filtered by the per-characteristic "enabled" setting in the device registry. Only characteristics marked as enabled are included in API responses. The `permissions` array on each characteristic reflects the MCP app's effective permissions — `notify` is only present when the characteristic is marked as observed. All IDs in responses are stable app-generated IDs (not raw HomeKit UUIDs).

**404** if device not found.

---

### Services

Requires: **REST API enabled**

| Method | Path | Description | Response |
|---|---|---|---|
| `PATCH` | `/services/:serviceId` | Rename a service | `{"success": true}` |

**Request body** (JSON):

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string or null | yes | Custom display name. Pass `null` or empty string to reset to the HomeKit default. |

The custom name is persisted in the device registry and reflected in all API responses. When set, the `name` field on the service in device responses uses the custom value instead of the HomeKit-provided name.

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
| `DELETE` | `/logs` | Clear all logs (state-change + automation execution) | `{"cleared": true}` |

**Query Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `categories` | string (comma-separated) | all | Filter by category. Values: `state_change`, `webhook_call`, `webhook_error`, `mcp_call`, `rest_call`, `server_error`, `automation_execution`, `automation_error`, `scene_execution`, `scene_error`, `backup_restore` |
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

Each log entry is a polymorphic JSON object — the `category` field determines which fields are present (see [StateChangeLog](#statechangelog) in Data Models). Running (in-progress) automation executions are included in the response.

---

### automation Runtime

Requires: **REST API enabled**

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/automation-runtime` | Get automation runtime information (sun events) | `AutomationRuntimeResponse` |

**Response (200):**

```json
{
  "sunEvents": {
    "sunrise": "2026-03-07T11:48:57Z",
    "sunset": "2026-03-07T23:33:26Z",
    "locationConfigured": true,
    "cityName": "Land O Lakes"
  }
}
```

- `sunrise`/`sunset`: ISO 8601 timestamps for today's calculated times, or `null` if not computable (polar regions)
- `locationConfigured`: `false` when latitude and longitude are both 0 (not set). When `false`, `sunrise` and `sunset` will be `null`
- `cityName`: User-configured city name, or `null` if not set

---

### automations

Requires: **REST API enabled** + **automations enabled**

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `GET` | `/automations` | List all automations | 200 | `automation[]` |
| `GET` | `/automations/:automationId` | Get a single automation | 200 | `automation` |
| `POST` | `/automations` | Create an automation | 201 | `automation` |
| `PUT` | `/automations/:automationId` | Update an automation (partial) | 200 | `automation` |
| `DELETE` | `/automations/:automationId` | Delete an automation | 200 | `{"deleted": true}` |
| `POST` | `/automations/:automationId/trigger` | Trigger an automation | 202 | `TriggerResult` |
| `GET` | `/automations/:automationId/logs` | Get execution history | 200 | `AutomationExecutionLog[]` |
| `POST` | `/automations/generate` | Generate an automation using AI | 201 | `GenerateResult` |
| `POST` | `/automations/:automationId/improve` | Improve an automation using AI (preview only) | 200 | `automation` |

**GET /automations/:automationId/logs query params:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `limit` | integer | `50` | Max entries to return |

**POST /automations — Create**

Send a full `automation` JSON body. The following fields are auto-generated and should be omitted: `id`, `createdAt`, `updatedAt`, `metadata`. Defaults: `isEnabled = true`, `continueOnError = false`, `retriggerPolicy = "ignoreNew"`.

**PUT /automations/:automationId — Update**

Send a partial JSON body. Only included top-level fields are updated; omitted fields are preserved. Arrays (`triggers`, `conditions`, `blocks`) are replaced wholesale when provided.

Updatable fields: `name`, `description`, `isEnabled`, `continueOnError`, `retriggerPolicy`, `triggers`, `conditions`, `blocks`.

See [automation](#automation) in Data Models for the full schema.

---

### Global Values

Requires: **REST API enabled**

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `GET` | `/global-values` | List all global values | 200 | `globalValue[]` |
| `GET` | `/global-values/:variableId` | Get a single global value | 200 | `globalValue` |
| `POST` | `/global-values` | Create a new global value | 201 | `globalValue` |
| `PUT` | `/global-values/:variableId` | Update a global value | 200 | `globalValue` |
| `DELETE` | `/global-values/:variableId` | Delete a global value | 204 | (empty) |

**POST /global-values — Create**

```json
{
  "name": "counter",
  "type": "number",
  "value": 0
}
```

Required fields: `name` (string, unique), `type` (`"number"`, `"string"`, `"boolean"`, or `"datetime"`), `value` (must match the declared type; datetime values are ISO 8601 strings).

**PUT /global-values/:variableId — Update**

```json
{
  "value": 42
}
```

Only `value` can be updated. The type is immutable after creation.

**Global Value Model:**

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Auto-generated |
| `name` | string | Unique name |
| `type` | string | `"number"`, `"string"`, `"boolean"`, or `"datetime"` |
| `value` | any | Current value (type-specific) |
| `createdAt` | ISO 8601 | Creation timestamp |
| `updatedAt` | ISO 8601 | Last update timestamp |

---

### Settings

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/settings/temperature-unit` | Get current temperature unit | `{"unit": "celsius"}` or `{"unit": "fahrenheit"}` |
| `PATCH` | `/settings/temperature-unit` | Set temperature unit | `{"unit": "fahrenheit"}` |

**PATCH request body:**

```json
{ "unit": "fahrenheit" }
```

Valid values: `"celsius"`, `"fahrenheit"`. Returns **400** for invalid values.

---

### Subscription

| Method | Path | Description | Response |
|---|---|---|---|
| `GET` | `/subscription/status` | Get current subscription tier | `{"tier": "free", "isPro": false}` |

Returns the user's subscription status. Always accessible (no feature-flag guard beyond bearer token auth).

**Response:**

```json
{
  "tier": "free",
  "isPro": false
}
```

`tier` is either `"free"` or `"pro"`. `isPro` is a convenience boolean.

**Subscription gating:** Automation endpoints (`/automations/*`) and AI endpoints (`/automations/generate`, `/automations/:id/improve`) return **402 Payment Required** when the user does not have a Pro subscription. The response body includes:

```json
{
  "error": true,
  "reason": "This feature requires a CompAI - Home Pro subscription."
}
```

---

### Webhook Trigger

Requires: **REST API enabled** + **automations enabled**

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `POST` | `/automations/webhook/:token` | Trigger automations by webhook token | 202 | `TriggerResult[]` |

Finds all enabled automations that have a webhook trigger matching the given token and triggers each one. Returns an array of results.

**404** if no automations match the token.

---

### AI automation Generation

Requires: **REST API enabled** + **automations enabled** + **AI enabled** (with a valid API key configured in settings)

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `POST` | `/automations/generate` | Generate an automation from a natural language prompt | 201 | `GenerateResult` |

The MCP server acts as a proxy — it enriches the prompt with device context, calls the configured LLM (Claude, OpenAI, or Gemini), parses the response into an automation, saves it, and returns a summary.

**Request body:**

```json
{
  "prompt": "Turn on the living room lights at sunset",
  "deviceIds": ["device-uuid-1", "device-uuid-2"],
  "sceneIds": ["scene-uuid-1"]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `prompt` | string | yes | Natural language description of the automation |
| `deviceIds` | string[] | no | Pre-selected device IDs to use as context. When provided (and at least one ID across deviceIds/sceneIds is non-empty), the server skips automatic device selection and prompt validation, using only the specified devices. |
| `sceneIds` | string[] | no | Pre-selected scene IDs to use as context. Same behavior as deviceIds. |

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
| 404 | REST API, automations, or AI features disabled |
| 422 | Vague prompt or model refused to generate |
| 500 | AI response could not be parsed into a valid automation |
| 502 | LLM API network or upstream error |
| 503 | AI not configured (no API key set) |

Error body: `{ "error": "Human-readable error message" }`

### Improve automation with AI

Requires: **REST API enabled** + **automations enabled** + **AI enabled** (with a valid API key configured in settings)

| Method | Path | Description | Status | Response |
|---|---|---|---|---|
| `POST` | `/automations/:automationId/improve` | Improve an existing automation using AI | 200 | `automation` |

Analyzes the existing automation structure, fixes labels/titles that don't match their configuration, and applies the requested improvements. The response is a **preview only** — the automation is **not saved** until you apply it with `PUT /automations/:automationId`.

**Request body:**

```json
{
  "prompt": "Add a condition to only run during nighttime"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `prompt` | string | no | Instructions for how to improve the automation. When omitted or empty, the AI performs an automatic review and optimization (fixes labels, suggests structural improvements). |

**Success response (200):**

Returns the full improved `automation` JSON (same schema as `GET /automations/:automationId`). The automation retains its original `id`, `createdAt`, and `metadata`. The `updatedAt` field is set to the current time.

**To apply the improvements**, send the response body (or relevant fields) to `PUT /automations/:automationId`.

**Error responses:**

| Status | Reason |
|---|---|
| 400 | Invalid automation ID |
| 404 | automation not found, or REST API / automations / AI features disabled |
| 422 | Vague prompt or model refused |
| 500 | AI response could not be parsed |
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
| Server name | `CompAI-Home` |
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
| `homekit://devices` | HomeKit Devices | `application/json` | JSON array of all devices with current state (filtered by enabled setting) |
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

List HomeKit devices grouped by room, with optional filters. All filters are AND-ed.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `rooms` | string[] | no | Filter by room name(s). Case-insensitive. |
| `device_category` | string | no | Filter by device category (e.g. "Lightbulb", "Sensor"). Case-insensitive. |

Returns markdown-formatted text with devices grouped by room. Each device shows its name, online/offline status, and stable device ID. For multi-service devices, each service shows its display name and service ID. Each characteristic includes its stable characteristic ID, current value, compact permissions (`[r/w/n]` where r=read, w=write, n=notify), and metadata (format, range, units, or enum labels).

Use `list_device_categories` to discover valid category filter values.

Example output:
```
## Living Room
- Living Room Light [online] (id: abc-123)
    Power (id: def-456): On [r/w/n]
    Brightness (id: ghi-789): 75 [r/w] (uint8, 0–100, percentage)
    Current Temperature (id: jkl-012): 22.5 [r] (float, celsius)
```

---

##### get_device_details

Get the full state of one or more devices.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `device_ids` | string[] | yes | Array of stable device identifiers |

Returns a JSON array of `RESTDevice` objects. Reports any device IDs not found.

---

##### control_device

Set a characteristic value on a device.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `device_id` | string | yes | Stable device identifier |
| `characteristic_id` | string | yes | Stable characteristic identifier (from `list_devices` or `get_device_details`) |
| `value` | varies | yes | Value to set. Type depends on characteristic: bool for power/lock, int 0-100 for brightness/saturation/position, int 0-360 for hue, float for temperature |

Values are validated against the characteristic's metadata (format, min/max, valid values).

**Temperature values**: When the temperature unit preference is set to Fahrenheit, provide temperature values in Fahrenheit. The server automatically converts to Celsius before sending to HomeKit.

**Permission requirement:** The target characteristic must have `"write"` permission. Attempting to set a value on a read-only characteristic will return an error.

---

##### list_rooms

List all rooms with device counts.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns text list of rooms and the number of devices in each.

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

#### Global Value Tools

Requires automations enabled + Pro subscription.

##### list_global_values

List all global values with their current values and types.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns JSON array of all global values.

##### get_global_value

Get a specific global value by ID or name.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `variable_id` | string | No | UUID of the global value |
| `name` | string | No | Name of the global value (alternative) |

##### create_global_value

Create a new global value.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `name` | string | Yes | Unique name for the value |
| `type` | string | Yes | `"number"`, `"string"`, or `"boolean"` |
| `value` | any | Yes | Initial value matching the declared type |

##### update_global_value

Update the value of an existing global value.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `variable_id` | string | No | UUID of the global value |
| `name` | string | No | Name of the global value (alternative) |
| `value` | any | Yes | New value matching the value's type |

##### delete_global_value

Delete a global value by ID or name.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `variable_id` | string | No | UUID of the global value |
| `name` | string | No | Name of the global value (alternative) |

---

#### Metadata Tools

Always available. These tools help AI agents discover valid type names and automation schema before making requests.

##### list_device_categories

List all known HomeKit device categories with semantic descriptions.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns a text list of all device categories. Each entry includes:
- Friendly name (e.g. "Lightbulb", "Thermostat", "Sensor")
- Semantic description explaining what kind of physical device the category represents

These names can be used as filter values in `list_devices`.

Example entry: `- Sensor — Environmental or state sensor (motion, temperature, humidity, contact, leak, etc.)`

---

##### get_automation_schema

Get a structured JSON schema for automation creation and updates.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns a JSON object describing the full automation definition format including:
- Top-level automation fields
- All trigger types with their fields and valid values
- All block types (action and flow control) with fields
- All condition types with comparison operators
- Valid enum values for policies, execution modes, etc.
- Important rules and restrictions

Use this schema to reliably generate automations for `create_automation` and `update_automation`.

---

#### automation Tools

Requires **automations enabled**.

##### list_automations

List all automations with status and stats.

| Parameter | Type | Required | Description |
|---|---|---|---|
| *(none)* | | | |

Returns markdown text with automation name, enabled status, trigger/block counts, execution stats, and failure counts.

---

##### get_automation

Get the full definition of an automation.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | yes | UUID of the automation |

Returns complete JSON `automation` object.

---

##### create_automation

Create a new automation.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation` | object | yes | Complete automation definition (see [automation schema](#automation)) |

Auto-generated fields (omit from input): `id`, `createdAt`, `updatedAt`, `metadata`.

Defaults: `isEnabled = true`, `continueOnError = false`, `retriggerPolicy = "ignoreNew"`.

Returns success message with the new automation's ID and name.

---

##### update_automation

Update an existing automation (partial update).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | yes | UUID of the automation |
| `automation` | object | yes | Partial or full automation JSON |

Only top-level fields present in the object are replaced. Arrays (`triggers`, `conditions`, `blocks`) are replaced wholesale.

---

##### delete_automation

Delete an automation permanently.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | yes | UUID of the automation |

---

##### enable_automation

Toggle an automation on or off.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | yes | UUID of the automation |
| `enabled` | boolean | yes | `true` to enable, `false` to disable |

---

##### get_automation_logs

Get execution history for automations.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | no | Filter to a specific automation |
| `limit` | integer | no | Max entries (default: 20) |

Returns formatted text with timestamp, status, duration, trigger info, errors, and block results.

---

##### trigger_automation

Manually trigger an automation (fire-and-forget).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | yes | UUID of the automation |

Returns the scheduling outcome based on the retrigger policy. See [TriggerResult](#triggerresult).

---

##### improve_automation

Use AI to analyze and improve an existing automation. Returns the improved automation JSON **without saving it**. Review the result and use `update_automation` to apply the changes.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `automation_id` | string | yes | UUID of the automation to improve |
| `prompt` | string | no | Instructions for how to improve the automation. When omitted, performs automatic review and optimization. |

Returns the full improved automation JSON as text. The automation retains its original ID, creation date, and metadata. Use `update_automation` with the returned JSON to persist the changes.

Requires AI to be configured (API key set in settings). Returns an error if AI is not available.

---

## Outgoing Webhooks

When a HomeKit device state changes, the app can send an HTTP POST to a configured webhook URL. Webhooks are sent only for characteristics marked as `observed` in the device registry. Only characteristics with `"notify"` permission can be observed — these are the characteristics that receive real-time state change events from HomeKit.

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
| `units` | string | yes | Unit of measurement (e.g. "celsius", "fahrenheit", "percentage"). For temperature characteristics, reflects the configured temperature unit preference. |
| `permissions` | string[] | no | Effective access permissions as determined by the MCP app (not raw HomeKit). `"read"` and `"write"` are passed through from HomeKit for enabled characteristics. `"notify"` is only present when the characteristic is marked as observed in the app — if not observed, `notify` is stripped regardless of HomeKit capability. This allows the MCP app to act as a permission proxy. |
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

### automation

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Auto-generated |
| `name` | string | no | automation name |
| `description` | string | yes | Optional description |
| `isEnabled` | boolean | no | Whether the automation is active |
| `triggers` | AutomationTrigger[] | no | What starts the automation |
| `conditions` | AutomationCondition[] | yes | Execution guards (all must pass for automation to run). Evaluated after any trigger fires. Failure logs as `conditionNotMet`. |
| `blocks` | AutomationBlock[] | no | Sequence of actions/flow control |
| `continueOnError` | boolean | no | Skip failed blocks instead of stopping |
| `retriggerPolicy` | string | no | Default concurrent execution policy (see below) |
| `metadata` | AutomationMetadata | no | Execution statistics |
| `createdAt` | string (ISO 8601) | no | Creation timestamp |
| `updatedAt` | string (ISO 8601) | no | Last update timestamp |

**ConcurrentExecutionPolicy values:**

| Value | Behavior |
|---|---|
| `ignoreNew` | Ignore new triggers while running (default) |
| `cancelAndRestart` | Cancel current execution, start new |
| `queueAndExecute` | Queue new trigger, execute after current finishes |
| `cancelOnly` | Cancel current execution, don't restart |

**AutomationMetadata:**

| Field | Type | Description |
|---|---|---|
| `createdBy` | string? | Creator identifier |
| `tags` | string[]? | Optional tags |
| `lastTriggeredAt` | string? (ISO 8601) | Last trigger timestamp |
| `totalExecutions` | integer | Total execution count |
| `consecutiveFailures` | integer | Consecutive failure count |

---

### AutomationTrigger

Each trigger has a `type` discriminator, an optional `retriggerPolicy` that overrides the automation-level default, and an optional `conditions` array for per-trigger guard conditions.

**Per-trigger guards** are evaluated after the trigger matches but before the automation is considered triggered. If per-trigger guards fail, the trigger is **silently skipped** (as if it never matched). No execution log entry is created. Only `deviceState` and `timeCondition` condition types are allowed (no `blockResult`). Per-trigger guards use the same `AutomationCondition` format as execution guards.

#### deviceStateChange

Fires when a device characteristic changes. **The referenced characteristic must have `"notify"` permission** — only characteristics that support HomeKit event notifications can trigger automations. The server validates this on create/update and returns an error if the characteristic lacks notify permission.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"deviceStateChange"` | yes | |
| `name` | string | no | Display name |
| `deviceId` | string | yes | Stable device ID |
| `deviceName` | string | yes | Device name (for cross-device migration) |
| `roomName` | string | yes | Room name |
| `serviceId` | string | no | Specific service |
| `characteristicId` | string | yes | Stable characteristic ID (resolvable via device registry) |
| `matchOperator` | object | no | Trigger match operator (see below) |
| `retriggerPolicy` | string | no | Override policy |
| `conditions` | AutomationCondition[] | no | Per-trigger guard conditions (silently skip trigger if not met) |

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
| `transitioned` | `from` (optional), `to` (optional); at least one required | Value transitioned from/to |

#### schedule

Time-based trigger.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"schedule"` | yes | |
| `name` | string | no | |
| `scheduleType` | object | yes | Schedule definition (see below) |
| `retriggerPolicy` | string | no | |
| `conditions` | AutomationCondition[] | no | Per-trigger guard conditions |

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
| `conditions` | AutomationCondition[] | no | Per-trigger guard conditions |

#### webhook

External HTTP trigger with a unique token.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"webhook"` | yes | |
| `name` | string | no | |
| `token` | string | yes | Unique webhook token |
| `retriggerPolicy` | string | no | |
| `conditions` | AutomationCondition[] | no | Per-trigger guard conditions |

#### automation

Makes this automation callable by other automations.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"automation"` | yes | |
| `name` | string | no | |
| `retriggerPolicy` | string | no | |
| `conditions` | AutomationCondition[] | no | Per-trigger guard conditions |

---

### AutomationBlock

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
| `value` | any | yes | Value to set (Local mode), or default fallback value when `valueRef` is used |
| `valueRef` | StateVariableRef | no | When set, the value is resolved at runtime from the referenced global value. Falls back to `value` if the global value is deleted. Example: `{"type": "byName", "name": "sprinkler_duration"}` |

**Permission requirement:** The referenced characteristic must have `"write"` permission. The server validates this on automation create/update.

**Value source modes:**
- **Local** (default): Uses the `value` field directly, as a hardcoded value in the workflow.
- **Global**: When `valueRef` is set, the value is resolved at runtime from the referenced global value. The `value` field serves as a default fallback if the global value is deleted or unavailable.

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

##### stateVariable

Operate on global values (create, update, remove, arithmetic, boolean logic, read from device).

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"stateVariable"` | yes | |
| `operation` | StateVariableOperation | yes | Operation to perform (see below) |

**StateVariableOperation** has an `operation` field discriminator:

| Operation | Fields | Description |
|---|---|---|
| `create` | `name`, `variableType`, `initialValue` | Create a new global value |
| `remove` | `variableRef` | Delete a global value |
| `set` | `variableRef`, `value` | Set a global value |
| `setFromCharacteristic` | `variableRef`, `deviceId`, `characteristicId`, `serviceId` (optional) | Read a device characteristic's current value into a global value |
| `setToNow` | `variableRef` | Set a datetime global value to the current date/time |
| `addTime` | `variableRef`, `amount`, `unit` | Add time to a datetime value. Unit: `seconds`, `minutes`, `hours`, `days` |
| `subtractTime` | `variableRef`, `amount`, `unit` | Subtract time from a datetime value. Unit: `seconds`, `minutes`, `hours`, `days` |
| `increment` | `variableRef`, `by` | Add `by` to a number value |
| `decrement` | `variableRef`, `by` | Subtract `by` from a number value |
| `multiply` | `variableRef`, `by` | Multiply a number value by `by` |
| `addState` | `variableRef`, `otherRef` | Add another global value to this one |
| `subtractState` | `variableRef`, `otherRef` | Subtract another global value |
| `toggle` | `variableRef` | Flip a boolean value |
| `andState` | `variableRef`, `otherRef` | Boolean AND with another value |
| `orState` | `variableRef`, `otherRef` | Boolean OR with another value |
| `notState` | `variableRef` | Boolean NOT |

**StateVariableRef** identifies a global value by name or ID: `{"type": "byName", "name": "counter"}` or `{"type": "byId", "id": "uuid"}`.

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
| `condition` | AutomationCondition | yes | Condition to wait for (same format as conditional/repeatWhile — supports AND/OR/NOT groups, deviceState, timeCondition) |
| `timeoutSeconds` | number | yes | Max wait time in seconds |

> **Backward compatibility:** The old flat format (`deviceId`, `characteristicId`, `condition` as ComparisonOperator) is still accepted for decoding and automatically converted to a `AutomationCondition.deviceState`.

##### conditional

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"conditional"` | yes | |
| `condition` | AutomationCondition | yes | Condition to evaluate |
| `thenBlocks` | AutomationBlock[] | yes | Blocks to run if true |
| `elseBlocks` | AutomationBlock[] | no | Blocks to run if false |

##### repeat

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"repeat"` | yes | |
| `count` | integer | yes | Number of iterations |
| `blocks` | AutomationBlock[] | yes | Blocks to repeat |
| `delayBetweenSeconds` | number | no | Delay between iterations |

##### repeatWhile

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"repeatWhile"` | yes | |
| `condition` | AutomationCondition | yes | Continue condition (no `blockResult` allowed) |
| `blocks` | AutomationBlock[] | yes | Blocks to repeat |
| `maxIterations` | integer | yes | Safety limit |
| `delayBetweenSeconds` | number | no | Delay between iterations |

##### group

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"group"` | yes | |
| `label` | string | no | Group label |
| `blocks` | AutomationBlock[] | yes | Nested blocks |

##### return

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"return"` | yes | |
| `outcome` | string | yes | `"success"`, `"error"`, or `"cancelled"` |
| `message` | string | no | Optional message |

Exits the current scope (group, repeat, conditional). At top level, terminates the entire automation.

##### executeAutomation

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"executeAutomation"` | yes | |
| `targetAutomationId` | string (UUID) | yes | automation to execute |
| `executionMode` | string | yes | `"inline"`, `"parallel"`, or `"delegate"` |

---

### AutomationCondition

Conditions are used in automation-level guards, conditional blocks, and repeatWhile blocks. They support arbitrary nesting via `and`/`or`/`not`.

#### deviceState

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"deviceState"` | yes | |
| `deviceId` | string | yes | |
| `deviceName` | string | yes | |
| `roomName` | string | yes | |
| `serviceId` | string | no | |
| `characteristicId` | string | yes | Stable characteristic ID (resolvable via device registry) |
| `comparison` | object | yes | `{type, value}` — types: `equals`, `notEquals`, `greaterThan`, `lessThan`, `greaterThanOrEqual`, `lessThanOrEqual`, `isEmpty`, `isNotEmpty`, `contains`. `isEmpty`/`isNotEmpty` have no value field. `contains` takes a string value. |

#### timeCondition

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"timeCondition"` | yes | |
| `mode` | string | yes | `beforeSunrise`, `afterSunrise`, `beforeSunset`, `afterSunset`, `daytime`, `nighttime`, `timeRange` |
| `startTime` | TimePoint | for `timeRange` | Start time. Cross-midnight aware. See TimePoint format below. |
| `endTime` | TimePoint | for `timeRange` | End time. See TimePoint format below. |

**TimePoint** — either a fixed clock time or a named marker:
- Fixed: `{"type": "fixed", "hour": 23, "minute": 0}` (hour 0-23, minute 0-59)
- Marker: `{"type": "marker", "marker": "midnight"}` — available markers: `midnight`, `noon`, `sunrise`, `sunset`
- Legacy format `{"hour": 23, "minute": 0}` (without `type` field) is accepted and treated as fixed.
- `sunrise` and `sunset` markers require location to be configured in Settings.

#### blockResult

Only valid inside `conditional` block conditions. Not allowed in automation-level guards or `repeatWhile`.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"blockResult"` | yes | |
| `scope` | string | yes | `"specific"`, `"lastBlock"`, or `"anyPreviousBlock"` |
| `blockId` | string (UUID) | for `specific` | Must reference an earlier block |
| `expectedStatus` | string | yes | `"success"`, `"failure"`, or `"cancelled"` |

Requires `continueOnError = true` on the automation.

#### engineState

Compare a global value's current value.

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"engineState"` | yes | |
| `variableRef` | StateVariableRef | yes | Reference to the variable (`{"type": "byName", "name": "counter"}`) |
| `comparison` | ComparisonOperator | yes | Comparison to apply. Boolean: `equals`/`notEquals`. String: `equals`/`notEquals`/`isEmpty`/`isNotEmpty`/`contains`. Number: all numeric operators. `isEmpty`/`isNotEmpty` have no value field. |
| `compareToStateRef` | StateVariableRef | no | When set, compare against another variable's value instead of the literal in `comparison` |

#### Logical operators

| Type | Field | Description |
|---|---|---|
| `and` | `conditions: AutomationCondition[]` | All must pass |
| `or` | `conditions: AutomationCondition[]` | Any must pass |
| `not` | `condition: AutomationCondition` | Negates inner condition |

---

### TriggerResult

Returned by automation trigger endpoints. Encoded as flat JSON.

| Status | HTTP Code | Description |
|---|---|---|
| `scheduled` | 202 | Execution scheduled |
| `replaced` | 202 | Previous cancelled, new scheduled |
| `queued` | 202 | Queued behind current execution |
| `cancelled` | 202 | Current execution cancelled, no restart |
| `ignored` | 409 | Already running, trigger ignored |
| `not_found` | 404 | automation not found |
| `disabled` | 503 | automations feature disabled |
| `automation_disabled` | 503 | Specific automation is disabled |

**JSON shape:**

```json
{
  "status": "scheduled",
  "automationId": "...",
  "automationName": "...",
  "message": "automation 'Morning Routine' execution scheduled."
}
```

---

### StateChangeLog

Polymorphic JSON — the `category` field determines which fields are present. Every entry has the common fields; additional fields depend on category.

#### Common fields (all categories)

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Log entry ID |
| `timestamp` | string (ISO 8601) | When it occurred |
| `category` | string | Log category (see below) |

#### Category-specific fields

**`state_change`** — Device characteristic changed

| Field | Type | Nullable | Description |
|---|---|---|---|
| `deviceId` | string | no | Device ID |
| `deviceName` | string | no | Device name |
| `roomName` | string | yes | Room name |
| `serviceId` | string | yes | Service ID |
| `serviceName` | string | yes | Service name |
| `characteristicType` | string | no | Characteristic type |
| `oldValue` | any | yes | Previous value |
| `newValue` | any | yes | New value |
| `unit` | string | yes | Value unit suffix (e.g. `"%"`, `"°C"`, `"°F"`, `"K"`, `"°"`, `"lux"`) |

**`webhook_call`** / **`webhook_error`** — Outgoing webhook sent/failed

Same device fields as `state_change` (including `unit`), plus:

| Field | Type | Nullable | Description |
|---|---|---|---|
| `summary` | string | no | Webhook request summary |
| `result` | string | no | Webhook response summary |
| `errorDetails` | string | yes | Error description (webhook_error only) |
| `detailedRequest` | string | yes | Full request body |

**`mcp_call`** / **`rest_call`** — API call

| Field | Type | Nullable | Description |
|---|---|---|---|
| `method` | string | no | HTTP method and path (e.g. `"GET /devices"`) |
| `summary` | string | no | Request summary |
| `result` | string | no | Response summary (e.g. `"200 OK (3 devices)"`) |
| `detailedRequest` | string | yes | Full request body |
| `detailedResponse` | string | yes | Full response body |

**`server_error`** — Server error

| Field | Type | Nullable | Description |
|---|---|---|---|
| `errorDetails` | string | no | Error description |

**`automation_execution`** / **`automation_error`** — automation executed/failed

| Field | Type | Description |
|---|---|---|
| `automationExecution` | AutomationExecutionLog | Full automation execution data |

**`scene_execution`** / **`scene_error`** — Scene executed/failed

| Field | Type | Nullable | Description |
|---|---|---|---|
| `sceneId` | string | no | Scene ID |
| `sceneName` | string | no | Scene name |
| `succeeded` | boolean | no | Whether the scene succeeded |
| `summary` | string | yes | Execution summary |
| `errorDetails` | string | yes | Error description (scene_error only) |

**`backup_restore`** — Backup/restore operation

| Field | Type | Description |
|---|---|---|
| `subtype` | string | Operation subtype (e.g. `"backup"`, `"restore"`, `"orphan-detection"`) |
| `summary` | string | Operation summary |

**`ai_interaction`** / **`ai_interaction_error`** — AI automation operation

| Field | Type | Description |
|---|---|---|
| `aiInteractionPayload` | AIInteractionPayload | Full AI interaction data |

#### AIInteractionPayload

| Field | Type | Nullable | Description |
|---|---|---|---|
| `provider` | string | no | AI provider name |
| `model` | string | no | Model name |
| `operation` | string | no | Operation type |
| `systemPrompt` | string | no | System prompt used |
| `userMessage` | string | no | User message sent |
| `rawResponse` | string | yes | Raw AI response |
| `parsedSuccessfully` | boolean | no | Whether the response was parsed |
| `errorMessage` | string | yes | Error message if failed |
| `durationSeconds` | number | no | Request duration in seconds |

### LogCategory

| Value | Description |
|---|---|
| `state_change` | Device characteristic changed |
| `webhook_call` | Outgoing webhook sent successfully |
| `webhook_error` | Outgoing webhook failed |
| `mcp_call` | MCP tool/resource call |
| `rest_call` | REST API call |
| `server_error` | Server error |
| `automation_execution` | automation executed (includes success, running, skipped/conditionNotMet, and cancelled statuses) |
| `automation_error` | automation execution failed (only `failure` status) |
| `scene_execution` | Scene executed |
| `scene_error` | Scene execution failed |
| `backup_restore` | Backup/restore operation |
| `ai_interaction` | AI automation operation succeeded |
| `ai_interaction_error` | AI automation operation failed |

### AutomationExecutionLog

Embedded in `StateChangeLog` entries with `automation_execution` or `automation_error` category. Also returned directly by `GET /automations/:id/logs`.

| Field | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Execution log ID |
| `automationId` | UUID | no | Parent automation ID |
| `automationName` | string | no | automation name at time of execution |
| `triggeredAt` | string (ISO 8601) | no | When the execution was triggered |
| `completedAt` | string (ISO 8601) | yes | When the execution finished (null if still running) |
| `triggerEvent` | TriggerEvent | yes | What triggered the execution |
| `conditionResults` | ConditionResult[] | yes | Results of execution guards |
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
| `conditionNotMet` | Execution guards not met (displayed as "Skipped"). The `errorMessage` field describes which conditions failed. When the "Log Skipped automations" setting is disabled, automations with this status are not logged. Per-trigger guard failures are not logged — the trigger is silently skipped. |
| `cancelled` | Cancelled (by retrigger policy, return block, or user request). The `errorMessage` field describes the cancellation reason. |

#### TriggerEvent

| Field | Type | Nullable | Description |
|---|---|---|---|
| `deviceId` | string | yes | Device that triggered the automation |
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
| `blockType` | string | no | Block type: `controlDevice`, `delay`, `conditional`, `repeat`, `repeatWhile`, `group`, `return`, `webhook`, `log`, `runScene`, `waitForState`, `executeAutomation` |
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
| 201 | Created (POST /automations) |
| 202 | Accepted (automation triggers, MCP notifications) |
| 400 | Bad request (invalid params, malformed JSON) |
| 401 | Unauthorized (missing/invalid Bearer token) |
| 402 | Payment required (Pro subscription needed for this feature) |
| 404 | Not found (resource missing or feature disabled) |
| 405 | Method not allowed |
| 409 | Conflict (trigger ignored — automation already running) |
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
