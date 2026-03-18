# Web App OAuth Authentication — Design Spec

## Overview

Add OAuth 2.1 as an authentication method in the web app (webclient), alongside the existing Bearer token. Users enter their OAuth client ID and client secret in Settings, and the web app handles the full token exchange (authorize → token) and automatic refresh behind the scenes.

## Auth Method Selection

The Settings page gets an "Authentication Method" selector with two options:

- **Bearer Token** (default) — existing behavior, single token field
- **OAuth** — shows Client ID and Client Secret fields

Switching methods **clears** the other method's stored values from localStorage. Only one method is active at a time.

## OAuth Token Flow (Web App Side)

1. User enters client ID + client secret in Settings → Save
2. Web app generates a PKCE code verifier + challenge (S256)
3. Web app calls `GET /oauth/authorize?response_type=code&client_id=...&code_challenge=...&code_challenge_method=S256&redirect_uri=...` — since the server auto-grants, this returns a 302 with the auth code. The web app uses `fetch` with `redirect: 'manual'` to extract the code from the `Location` header without following the redirect.
4. Web app calls `POST /oauth/token` with `grant_type=authorization_code`, code, client_id, client_secret, code_verifier
5. Receives access_token (1hr) + refresh_token (30 days)
6. All subsequent API calls use `Authorization: Bearer <access_token>`
7. On 401 response: automatically attempt refresh via `POST /oauth/token` with `grant_type=refresh_token`
8. On refresh failure: clear tokens, surface error to UI (user needs to re-enter credentials or check them)

## Token Storage

- Access and refresh tokens stored **in memory only** (not localStorage) — they're short-lived and re-obtainable from the stored credentials
- On page reload: re-authenticate using stored client ID + secret (fast, since server auto-grants)
- Client ID and client secret stored in localStorage (same as Bearer token today)

## Config Context Changes

Add to `ConfigState`:

| Field | Type | Default | Storage Key |
|-------|------|---------|-------------|
| `authMethod` | `'bearer' \| 'oauth'` | `'bearer'` | `hk-log-viewer:authMethod` |
| `oauthClientId` | `string` | `''` | `hk-log-viewer:oauthClientId` |
| `oauthClientSecret` | `string` | `''` | `hk-log-viewer:oauthClientSecret` |

`isConfigured` logic: returns true if `authMethod === 'bearer' && bearerToken` is set, or `authMethod === 'oauth' && oauthClientId && oauthClientSecret` are set.

When `authMethod` changes:
- Switching to Bearer: clear `oauthClientId` and `oauthClientSecret` from localStorage
- Switching to OAuth: clear `bearerToken` from localStorage

## API Client Changes

Extend `createApiClient` (or create wrapper) to support OAuth:

- Accept either `{ type: 'bearer', token }` or `{ type: 'oauth', clientId, clientSecret, baseUrl }` as auth config
- For OAuth mode:
  - Perform token exchange on first request (lazy init)
  - Cache access/refresh tokens in closure scope
  - Intercept 401 responses → attempt refresh → retry original request once
  - If refresh fails → throw auth error that UI can catch

## Settings UI Changes

Replace the single Bearer Token input with a conditional section:

- **Auth method selector** (radio buttons or segmented control)
- **Bearer mode**: existing password input for token
- **OAuth mode**: two inputs — Client ID (text) and Client Secret (password)
- "Test Connection" works with either method
- "Save" validates that the selected method's fields are filled

## WebSocket Authentication

WebSocket currently uses `?token=<bearer_token>` query param. For OAuth mode:
- After obtaining the access token, use it as the WebSocket token param: `?token=<access_token>`
- On WebSocket disconnect due to token expiry: refresh token, reconnect with new access token

## PKCE in the Browser

Generate PKCE values using the Web Crypto API:

- `code_verifier`: 32 random bytes, base64url-encoded
- `code_challenge`: SHA-256 hash of verifier, base64url-encoded

## Scope

### In scope
- Auth method selector in Settings (Bearer vs OAuth)
- OAuth token exchange + auto-refresh in API client
- PKCE generation using Web Crypto API
- WebSocket reconnection with refreshed tokens
- Clearing credentials on method switch

### Out of scope
- Browser redirect-based OAuth flow
- Storing access/refresh tokens in localStorage
- Multiple OAuth credential sets in the web app
- OAuth credential creation from the web app (use the existing credential management UI for that)
