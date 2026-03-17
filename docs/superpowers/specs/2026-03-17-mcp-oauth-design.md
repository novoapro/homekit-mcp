# MCP OAuth 2.1 — Design Spec

## Overview

Add OAuth 2.1 authorization to CompAI - Home, enabling MCP clients (e.g., Claude Desktop) and REST API consumers to authenticate via the MCP spec's OAuth flow (2025-03-26). Credentials are pre-authorized — generated in the app's Settings with no login or consent UI.

Existing Bearer token authentication is preserved alongside OAuth.

## Approach

**Minimal "Pre-authorized" OAuth.** The app acts as its own OAuth 2.1 authorization server. Since the user creates credentials in Settings (no interactive login), the authorization endpoint auto-grants immediately. Only the token exchange requires cryptographic validation (PKCE S256).

This avoids the complexity of a full authorization code grant while remaining MCP-spec compliant — the server controls auth policy and chooses to pre-authorize all registered clients.

## Data Model

### OAuthCredential (Keychain-persisted)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Internal identifier |
| `clientId` | String | Generated, shared with MCP client |
| `clientSecret` | String | Generated, shared with MCP client (shown once at creation) |
| `name` | String | User-given label (e.g., "Claude Desktop") |
| `createdAt` | Date | Creation timestamp |
| `lastUsedAt` | Date? | Last successful token exchange |
| `isRevoked` | Bool | Revocation status |

### OAuthToken (in-memory, persisted to JSON file)

| Field | Type | Description |
|-------|------|-------------|
| `accessToken` | String | Short-lived token (1-hour lifetime) |
| `refreshToken` | String | Long-lived token (30-day lifetime) |
| `credentialId` | UUID | Links to issuing credential |
| `expiresAt` | Date | Access token expiry |
| `scopes` | Set\<String\> | Initially `["*"]`, extensible later |

**Token persistence:** Tokens are held in an in-memory dictionary for fast lookup. The full token set is written to a JSON file in Application Support (alongside existing log data) on every mutation (issue, refresh, revoke). On app launch, tokens are loaded from this file. Authorization codes are ephemeral (in-memory only, 60s TTL) and not persisted — an app restart invalidates any pending auth codes.

## OAuth Endpoints

Three new endpoints on the existing Vapor server (port 3000):

### 1. Discovery — `GET /.well-known/oauth-authorization-server`

Returns OAuth server metadata per RFC 8414:

```json
{
  "issuer": "http://localhost:3000",
  "authorization_endpoint": "http://localhost:3000/oauth/authorize",
  "token_endpoint": "http://localhost:3000/oauth/token",
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["client_secret_post"],
  "response_types_supported": ["code"]
}
```

### 2. Authorization — `GET /oauth/authorize`

Since credentials are pre-authorized, this endpoint validates the request and immediately redirects back with an authorization code. No consent screen.

Standard OAuth 2.1 authorization code flow: the client opens this URL (typically in a browser or embedded webview), and the server responds with a `302` redirect. Since all registered clients are pre-authorized, the redirect happens immediately — no user interaction required.

Note: `client_id` alone (without secret) is sufficient at this step, which is standard OAuth behavior. The `client_secret` is validated at the token endpoint. Since this is a localhost server, the risk of unauthorized auth code requests is minimal.

**Query parameters:**
- `response_type` (required) — must be `code`
- `client_id` (required) — must match a registered, non-revoked credential
- `code_challenge` (required) — PKCE S256 challenge
- `code_challenge_method` (required) — must be `S256`
- `redirect_uri` (required) — stored for validation at token exchange
- `state` (optional) — returned unchanged
- `scope` (optional) — defaults to `*`

**Success response:** `302 Found` redirect to `redirect_uri` with query parameters:
- `code` — single-use authorization code (expires in 60 seconds)
- `state` — echoed back if provided

Example: `Location: http://localhost:1234/callback?code=abc123&state=xyz`

**Error responses:**
- `302` redirect with `error=invalid_request` — missing/invalid parameters
- `302` redirect with `error=unauthorized_client` — unknown or revoked `client_id`

### 3. Token — `POST /oauth/token`

Exchanges credentials for tokens. Two grant types:

**Grant type: `authorization_code`**
- `grant_type` = `authorization_code`
- `code` — the authorization code
- `client_id` — must match the code's client
- `client_secret` — must match the credential
- `code_verifier` — PKCE verifier (validated against stored challenge)
- `redirect_uri` — must match the authorization request

**Grant type: `refresh_token`**
- `grant_type` = `refresh_token`
- `refresh_token` — valid, non-expired refresh token
- `client_id` — must match the token's credential
- `client_secret` — must match the credential

**Success response (both grant types):**

```json
{
  "access_token": "...",
  "token_type": "bearer",
  "expires_in": 3600,
  "refresh_token": "..."
}
```

**Refresh token rotation:** Each refresh exchanges the old refresh token for a new one. The old refresh token is immediately invalidated.

**Error responses:**
- `400` — invalid grant, missing parameters
- `401` — invalid client credentials, revoked credential

## Authentication Flow

From the MCP client's perspective:

1. **Discover** — `GET /.well-known/oauth-authorization-server` to find endpoints
2. **Authorize** — send `client_id` + PKCE challenge to `/oauth/authorize` → receive auth code immediately
3. **Exchange** — send auth code + PKCE verifier + `client_secret` to `/oauth/token` → receive access + refresh tokens
4. **Use** — include `Authorization: Bearer <access_token>` on all MCP/REST requests
5. **Refresh** — when access token expires (401 response), exchange refresh token for new token pair

## Auth Middleware Changes

The existing Bearer token middleware is extended with a unified validation chain:

1. Extract token from `Authorization: Bearer <token>` header
2. Check if token matches an existing static Bearer token → allow if match
3. Check if token is a valid, non-expired OAuth access token → allow if valid
4. Reject with `401 Unauthorized` + `WWW-Authenticate` header

No changes to how existing Bearer tokens work. OAuth tokens are additive.

## Revocation & Session Termination

Revocation is a **live operation** — no server restart required.

When a credential is revoked via Settings:

1. Set `isRevoked = true` on the OAuthCredential
2. Purge all OAuthTokens linked to that `credentialId`
3. Walk active MCP connections (SSE/Streamable HTTP), close any authenticated with tokens from the revoked credential
4. Subsequent REST requests with revoked tokens receive `401 Unauthorized`
5. Refresh attempts with revoked tokens return `invalid_grant` error

### Active Session Tracking

An in-memory map of `accessToken → connection` maintained by the server. Updated on connection open/close. On revocation, iterate matching entries and force-close connections. When a token is refreshed, the old access token's entry is removed from the map and the new access token is registered in its place.

### Token Lifecycle

| Token Type | Lifetime | Rotation |
|------------|----------|----------|
| Authorization code | 60 seconds | Single-use |
| Access token | 1 hour | Issued fresh on each refresh |
| Refresh token | 30 days | Rotated on use (old invalidated) |

## Settings UI

### MCP Server App (SwiftUI)

New "OAuth Credentials" section in Settings, alongside existing Bearer token management:

- **List view** — shows all credentials: name, client ID (truncated), created date, last used, status (active/revoked)
- **Create Credential** button — prompts for a name, generates client ID + client secret
- **Creation dialog** — shows credentials once with copy buttons:
  - Client ID
  - Client Secret
  - Token endpoint URL
  - "Copy configuration" button (copies formatted block for MCP client config)
- **Per-credential actions** — Reveal client ID, Revoke (with confirmation), Delete
- Revoked credentials shown greyed out until explicitly deleted

### Web App (React)

Mirror the same credential management on the Settings page:
- List, create, revoke, delete credentials
- Same one-time secret display on creation
- Same copy-configuration functionality

## Scope

### In scope
- OAuth 2.1 with PKCE (S256) per MCP spec 2025-03-26
- Pre-authorized credential flow (no login/consent)
- Multiple credential sets, individually revocable
- Immediate revocation with active session termination
- Unified auth middleware (Bearer + OAuth)
- Settings UI in both native app and web app
- Discovery endpoint (`.well-known`)

### Out of scope
- Full authorization code grant with login/consent UI
- Per-scope consent or granular permissions
- Dynamic client registration (MCP spec optional)
- External identity provider delegation (Sign in with Apple, etc.)
- Deprecation or migration of existing Bearer tokens
- OAuth for webhook callbacks
