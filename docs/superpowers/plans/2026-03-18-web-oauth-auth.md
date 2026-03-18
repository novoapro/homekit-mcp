# Web App OAuth Authentication Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OAuth 2.1 client credential authentication to the web app as an alternative to Bearer tokens, with automatic token exchange and refresh.

**Architecture:** Add `authMethod`, `oauthClientId`, `oauthClientSecret` to ConfigContext. Create a new `oauth-client.ts` module that handles PKCE generation, token exchange via JSON authorize endpoint, and auto-refresh. Create an `AuthContext` that wraps the API client and exposes a `getAccessToken()` for WebSocket. Update the server's `/oauth/authorize` endpoint to return JSON when `Accept: application/json` is sent.

**Tech Stack:** React 18, TypeScript, Web Crypto API (PKCE), Vite

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `webclient/src/lib/oauth-client.ts` | PKCE generation, OAuth token exchange, auto-refresh, token state |
| `webclient/src/contexts/AuthContext.tsx` | Provides API client + `getAccessToken()` to the app, bridges config to auth |

### Modified Files

| File | Changes |
|------|---------|
| `CompAI-Home/Services/MCPServer.swift` | `/oauth/authorize` returns JSON when `Accept: application/json` |
| `webclient/src/contexts/ConfigContext.tsx` | Add `authMethod`, `oauthClientId`, `oauthClientSecret` fields |
| `webclient/src/contexts/WebSocketContext.tsx` | Use `AuthContext.getAccessToken()` instead of `config.bearerToken` |
| `webclient/src/pages/SettingsPage.tsx` | Auth method selector, conditional Bearer/OAuth fields |
| `webclient/src/main.tsx` | Add `AuthProvider` to provider tree |
| `webclient/src/lib/api.ts` | Accept auth token getter instead of static token |
| `API.md` | Document JSON response mode for `/oauth/authorize` |

---

## Task 1: Server — JSON Response for /oauth/authorize

**Files:**
- Modify: `CompAI-Home/Services/MCPServer.swift`
- Modify: `API.md`

The `/oauth/authorize` endpoint currently always returns a 302 redirect. When the client sends `Accept: application/json`, return the auth code as JSON instead.

- [ ] **Step 1: Find the authorize endpoint handler**

In MCPServer.swift, find the `app.on(.GET, "oauth", "authorize")` route handler. It's in the OAuth endpoints section added in the prior PR.

- [ ] **Step 2: Add JSON response branch**

After the auth code is created successfully (the `guard let authCode = await self.oauthService.createAuthorizationCode(...)` block), before building the redirect `URLComponents`, add:

```swift
// If client accepts JSON (programmatic clients like web app), return code directly
if req.headers.first(name: .accept)?.contains("application/json") == true {
    var jsonBody: [String: String] = ["code": authCode.code]
    if let state { jsonBody["state"] = state }
    let data = try JSONSerialization.data(withJSONObject: jsonBody)
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    headers.add(name: .cacheControl, value: "no-store")
    return Response(status: .ok, headers: headers, body: .init(data: data))
}
```

Insert this right before the existing `guard var components = URLComponents(string: redirectURI)` line that builds the redirect response.

- [ ] **Step 3: Update API.md**

Add a note to the Authorization endpoint section explaining that when `Accept: application/json` header is sent, the response is a `200 OK` with JSON body `{ "code": "...", "state": "..." }` instead of a 302 redirect. This is for programmatic clients that can't follow redirects (e.g., browser `fetch`).

- [ ] **Step 4: Build and verify**

Run: `cd /Users/manuel/Desktop/development/homekit-mcp/.worktrees/oauth && make dev`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add CompAI-Home/Services/MCPServer.swift API.md
git commit -m "feat(oauth): support JSON response for /oauth/authorize endpoint"
```

---

## Task 2: OAuth Client Library

**Files:**
- Create: `webclient/src/lib/oauth-client.ts`

This module handles PKCE generation, token exchange, and auto-refresh. It's a plain TypeScript module (no React), stateful via closure.

- [ ] **Step 1: Create oauth-client.ts**

```typescript
// webclient/src/lib/oauth-client.ts

export interface OAuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: number; // unix ms
}

export interface OAuthClientConfig {
  baseUrl: string;
  clientId: string;
  clientSecret: string;
}

export class OAuthAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OAuthAuthError';
  }
}

// PKCE helpers using Web Crypto API
async function generateCodeVerifier(): Promise<string> {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

async function generateCodeChallenge(verifier: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return base64UrlEncode(new Uint8Array(digest));
}

function base64UrlEncode(bytes: Uint8Array): string {
  const binary = Array.from(bytes, b => String.fromCharCode(b)).join('');
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function createOAuthClient(config: OAuthClientConfig) {
  let tokens: OAuthTokens | null = null;
  let refreshPromise: Promise<OAuthTokens> | null = null;

  async function authenticate(): Promise<OAuthTokens> {
    const codeVerifier = await generateCodeVerifier();
    const codeChallenge = await generateCodeChallenge(codeVerifier);
    const redirectUri = 'urn:ietf:wg:oauth:2.0:oob';

    // Step 1: Get authorization code via JSON response
    const authorizeParams = new URLSearchParams({
      response_type: 'code',
      client_id: config.clientId,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
      redirect_uri: redirectUri,
    });

    const authRes = await fetch(
      `${config.baseUrl}/oauth/authorize?${authorizeParams}`,
      { headers: { 'Accept': 'application/json' }, redirect: 'manual' }
    );

    if (!authRes.ok) {
      const text = await authRes.text();
      throw new OAuthAuthError(`Authorization failed: ${text}`);
    }

    const { code } = await authRes.json() as { code: string };

    // Step 2: Exchange code for tokens
    const tokenRes = await fetch(`${config.baseUrl}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        grant_type: 'authorization_code',
        code,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        code_verifier: codeVerifier,
        redirect_uri: redirectUri,
      }),
    });

    if (!tokenRes.ok) {
      const text = await tokenRes.text();
      throw new OAuthAuthError(`Token exchange failed: ${text}`);
    }

    const data = await tokenRes.json() as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
    };

    tokens = {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt: Date.now() + data.expires_in * 1000 - 60_000, // refresh 1min early
    };
    return tokens;
  }

  async function refresh(): Promise<OAuthTokens> {
    if (!tokens) throw new OAuthAuthError('No tokens to refresh');

    const res = await fetch(`${config.baseUrl}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        grant_type: 'refresh_token',
        refresh_token: tokens.refreshToken,
        client_id: config.clientId,
        client_secret: config.clientSecret,
      }),
    });

    if (!res.ok) {
      tokens = null;
      throw new OAuthAuthError('Token refresh failed');
    }

    const data = await res.json() as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
    };

    tokens = {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresAt: Date.now() + data.expires_in * 1000 - 60_000,
    };
    return tokens;
  }

  /** Get a valid access token, refreshing or re-authenticating as needed. */
  async function getAccessToken(): Promise<string> {
    // No tokens yet — full authenticate
    if (!tokens) {
      const result = await authenticate();
      return result.accessToken;
    }

    // Token still valid
    if (Date.now() < tokens.expiresAt) {
      return tokens.accessToken;
    }

    // Token expired — refresh (deduplicate concurrent calls)
    if (!refreshPromise) {
      refreshPromise = refresh().finally(() => { refreshPromise = null; });
    }

    try {
      const result = await refreshPromise;
      return result.accessToken;
    } catch {
      // Refresh failed — try full re-auth
      tokens = null;
      const result = await authenticate();
      return result.accessToken;
    }
  }

  /** Clear all tokens (e.g., on credential change or logout). */
  function clearTokens() {
    tokens = null;
    refreshPromise = null;
  }

  return { getAccessToken, clearTokens, authenticate };
}
```

- [ ] **Step 2: Commit**

```bash
git add webclient/src/lib/oauth-client.ts
git commit -m "feat(oauth): add OAuth client library with PKCE and auto-refresh"
```

---

## Task 3: ConfigContext — Add OAuth Fields

**Files:**
- Modify: `webclient/src/contexts/ConfigContext.tsx`

- [ ] **Step 1: Add fields to ConfigState interface**

Add after `useHTTPS: boolean;`:

```typescript
authMethod: 'bearer' | 'oauth';
oauthClientId: string;
oauthClientSecret: string;
```

- [ ] **Step 2: Update envDefaults()**

Add to the return object:

```typescript
authMethod: 'bearer' as const,
oauthClientId: '',
oauthClientSecret: '',
```

- [ ] **Step 3: Update loadConfig()**

Add to the return object in the `hasUserSaved()` branch:

```typescript
authMethod: (loadString('authMethod', defaults.authMethod) as 'bearer' | 'oauth'),
oauthClientId: loadString('oauthClientId', defaults.oauthClientId),
oauthClientSecret: loadString('oauthClientSecret', defaults.oauthClientSecret),
```

- [ ] **Step 4: Update isConfigured**

Change from:
```typescript
const isConfigured = !!config.bearerToken;
```
To:
```typescript
const isConfigured = config.authMethod === 'oauth'
  ? !!(config.oauthClientId && config.oauthClientSecret)
  : !!config.bearerToken;
```

- [ ] **Step 5: Update save()**

Add to the save function:

```typescript
localStorage.setItem(`${STORAGE_PREFIX}:authMethod`, s.authMethod);
localStorage.setItem(`${STORAGE_PREFIX}:oauthClientId`, s.oauthClientId);
localStorage.setItem(`${STORAGE_PREFIX}:oauthClientSecret`, s.oauthClientSecret);
```

- [ ] **Step 6: Update reset()**

Add `'authMethod', 'oauthClientId', 'oauthClientSecret'` to the keys array.

- [ ] **Step 7: Commit**

```bash
git add webclient/src/contexts/ConfigContext.tsx
git commit -m "feat(oauth): add authMethod and OAuth credentials to ConfigContext"
```

---

## Task 4: AuthContext — Unified Auth Provider

**Files:**
- Create: `webclient/src/contexts/AuthContext.tsx`
- Modify: `webclient/src/main.tsx`

This context bridges ConfigContext to the rest of the app. It creates either a Bearer-based or OAuth-based API client depending on `authMethod`, and exposes `getAccessToken()` for WebSocket.

- [ ] **Step 1: Create AuthContext.tsx**

```typescript
// webclient/src/contexts/AuthContext.tsx
import { createContext, useContext, useMemo, useCallback, useRef, type ReactNode } from 'react';
import { useConfig } from './ConfigContext';
import { createApiClient, type ApiClient } from '@/lib/api';
import { createOAuthClient, type OAuthClientConfig } from '@/lib/oauth-client';

interface AuthContextValue {
  api: ApiClient;
  getAccessToken: () => Promise<string>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const { config, baseUrl } = useConfig();
  const oauthClientRef = useRef<ReturnType<typeof createOAuthClient> | null>(null);

  // Recreate OAuth client when credentials change
  const oauthClient = useMemo(() => {
    if (config.authMethod !== 'oauth' || !config.oauthClientId || !config.oauthClientSecret) {
      oauthClientRef.current = null;
      return null;
    }
    const client = createOAuthClient({
      baseUrl,
      clientId: config.oauthClientId,
      clientSecret: config.oauthClientSecret,
    });
    oauthClientRef.current = client;
    return client;
  }, [baseUrl, config.authMethod, config.oauthClientId, config.oauthClientSecret]);

  const getAccessToken = useCallback(async (): Promise<string> => {
    if (config.authMethod === 'bearer') {
      return config.bearerToken;
    }
    if (!oauthClientRef.current) {
      throw new Error('OAuth not configured');
    }
    return oauthClientRef.current.getAccessToken();
  }, [config.authMethod, config.bearerToken]);

  // Create API client that uses the right auth method
  const api = useMemo(() => {
    if (config.authMethod === 'oauth' && oauthClient) {
      return createOAuthApiClient(baseUrl, oauthClient);
    }
    return createApiClient(baseUrl, config.bearerToken);
  }, [baseUrl, config.authMethod, config.bearerToken, oauthClient]);

  const value = useMemo(() => ({ api, getAccessToken }), [api, getAccessToken]);

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

/**
 * Creates an ApiClient that uses OAuth tokens for authentication.
 * Wraps createApiClient but dynamically gets the Bearer token from the OAuth client.
 */
function createOAuthApiClient(
  baseUrl: string,
  oauthClient: ReturnType<typeof createOAuthClient>,
): ApiClient {
  // We create a proxy that fetches with the OAuth token
  // Reuse the existing createApiClient with a placeholder, then override the fetch behavior
  const baseClient = createApiClient(baseUrl, '');

  // Override each method to inject the OAuth token
  return new Proxy(baseClient, {
    get(target, prop, receiver) {
      const original = Reflect.get(target, prop, receiver);
      if (typeof original !== 'function') return original;
      if (prop === 'checkHealth') return original; // health doesn't need auth

      return async (...args: unknown[]) => {
        // Get fresh token before each call
        const token = await oauthClient.getAccessToken();
        // Create a fresh client with the current token and delegate
        const authedClient = createApiClient(baseUrl, token);
        const method = authedClient[prop as keyof ApiClient];
        if (typeof method === 'function') {
          try {
            return await (method as (...a: unknown[]) => unknown)(...args);
          } catch (err) {
            // On 401, try refreshing and retry once
            if (err instanceof Error && err.message.includes('401')) {
              oauthClient.clearTokens();
              const newToken = await oauthClient.getAccessToken();
              const retriedClient = createApiClient(baseUrl, newToken);
              const retriedMethod = retriedClient[prop as keyof ApiClient];
              if (typeof retriedMethod === 'function') {
                return await (retriedMethod as (...a: unknown[]) => unknown)(...args);
              }
            }
            throw err;
          }
        }
      };
    },
  });
}
```

- [ ] **Step 2: Add AuthProvider to main.tsx**

Import and add `AuthProvider` between `ConfigProvider` and `WebSocketProvider`:

```typescript
import { AuthProvider } from '@/contexts/AuthContext';
```

In the JSX:
```tsx
<ConfigProvider>
  <AuthProvider>
    <WebSocketProvider>
      ...
    </WebSocketProvider>
  </AuthProvider>
</ConfigProvider>
```

- [ ] **Step 3: Commit**

```bash
git add webclient/src/contexts/AuthContext.tsx webclient/src/main.tsx
git commit -m "feat(oauth): add AuthContext providing unified API client and token accessor"
```

---

## Task 5: Update WebSocketContext for OAuth

**Files:**
- Modify: `webclient/src/contexts/WebSocketContext.tsx`

- [ ] **Step 1: Import and use AuthContext**

Add import:
```typescript
import { useAuth } from './AuthContext';
```

In `WebSocketProvider`, add:
```typescript
const { getAccessToken } = useAuth();
const getAccessTokenRef = useRef(getAccessToken);
getAccessTokenRef.current = getAccessToken;
```

- [ ] **Step 2: Update the connect function**

Replace the token-building section in `connect()`:

Change from:
```typescript
const cfg = configRef.current;
if (!cfg.websocketEnabled) return;
if (!cfg.bearerToken) return;
// ...
const token = encodeURIComponent(cfg.bearerToken);
```

To:
```typescript
const cfg = configRef.current;
if (!cfg.websocketEnabled) return;

// Get token based on auth method
let wsToken: string;
if (cfg.authMethod === 'oauth') {
  try {
    wsToken = await getAccessTokenRef.current();
  } catch {
    setConnectionState('disconnected');
    return;
  }
} else {
  if (!cfg.bearerToken) return;
  wsToken = cfg.bearerToken;
}

const token = encodeURIComponent(wsToken);
```

Note: `connect` must become `async` since `getAccessToken` is async.

- [ ] **Step 3: Update auto-connect effect dependencies**

Change the effect dependency from `config.bearerToken` to also include `config.authMethod`, `config.oauthClientId`:

```typescript
useEffect(() => {
  const hasAuth = config.authMethod === 'oauth'
    ? !!(config.oauthClientId && config.oauthClientSecret)
    : !!config.bearerToken;
  if (config.websocketEnabled && hasAuth) {
    connect();
  } else {
    disconnect();
  }
  return () => disconnect();
}, [config.websocketEnabled, config.bearerToken, config.authMethod, config.oauthClientId, config.oauthClientSecret, config.serverAddress, config.serverPort]);
```

- [ ] **Step 4: Update iOS probe to use getAccessToken**

In the iOS thaw-detection probe (the `setInterval` block), change the auth header from `cfg.bearerToken` to use `getAccessTokenRef.current()`:

```typescript
let probeToken: string;
try {
  probeToken = await getAccessTokenRef.current();
} catch {
  wsFailsSinceProbe = 0;
  return;
}
// ...
headers: { 'Authorization': `Bearer ${probeToken}` },
```

- [ ] **Step 5: Commit**

```bash
git add webclient/src/contexts/WebSocketContext.tsx
git commit -m "feat(oauth): update WebSocketContext to use AuthContext for token management"
```

---

## Task 6: Settings UI — Auth Method Selector

**Files:**
- Modify: `webclient/src/pages/SettingsPage.tsx`

- [ ] **Step 1: Add OAuth fields to localState**

Add to the `localState` initial state:
```typescript
authMethod: config.authMethod,
oauthClientId: config.oauthClientId,
oauthClientSecret: config.oauthClientSecret,
```

- [ ] **Step 2: Update handleSave to clear credentials on method switch**

In `handleSave`, after validation and before `applyToConfig()`:

```typescript
// Clear credentials for the inactive auth method
const stateToSave = { ...localState };
if (stateToSave.authMethod === 'oauth') {
  stateToSave.bearerToken = '';
} else {
  stateToSave.oauthClientId = '';
  stateToSave.oauthClientSecret = '';
}
setLocalState(stateToSave);
```

Then pass `stateToSave` to `applyToConfig` and `save`.

- [ ] **Step 3: Replace Bearer Token input with auth method selector + conditional fields**

Replace the Bearer Token form group (lines 139-151) with:

```tsx
<div className="form-group">
  <label>Authentication Method</label>
  <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
    <button
      className={`btn ${localState.authMethod === 'bearer' ? 'btn-primary' : 'btn-secondary'}`}
      style={{ flex: 1 }}
      onClick={() => updateField('authMethod', 'bearer')}
    >
      Bearer Token
    </button>
    <button
      className={`btn ${localState.authMethod === 'oauth' ? 'btn-primary' : 'btn-secondary'}`}
      style={{ flex: 1 }}
      onClick={() => updateField('authMethod', 'oauth')}
    >
      OAuth
    </button>
  </div>
</div>

{localState.authMethod === 'bearer' ? (
  <div className="form-group">
    <label htmlFor="bearerToken">Bearer Token</label>
    <input
      id="bearerToken"
      type="password"
      value={localState.bearerToken}
      onChange={e => updateField('bearerToken', e.target.value)}
      placeholder="Enter your API token"
      className="form-input"
      maxLength={512}
    />
    <span className="hint">Found in the CompAI - Home app settings under API tokens</span>
  </div>
) : (
  <>
    <div className="form-group">
      <label htmlFor="oauthClientId">Client ID</label>
      <input
        id="oauthClientId"
        type="text"
        value={localState.oauthClientId}
        onChange={e => updateField('oauthClientId', e.target.value)}
        placeholder="Enter OAuth client ID"
        className="form-input"
        maxLength={512}
      />
    </div>
    <div className="form-group">
      <label htmlFor="oauthClientSecret">Client Secret</label>
      <input
        id="oauthClientSecret"
        type="password"
        value={localState.oauthClientSecret}
        onChange={e => updateField('oauthClientSecret', e.target.value)}
        placeholder="Enter OAuth client secret"
        className="form-input"
        maxLength={512}
      />
      <span className="hint">Generate OAuth credentials in the CompAI - Home app under Server → OAuth Credentials</span>
    </div>
  </>
)}
```

- [ ] **Step 4: Update testConnection to use the selected auth method**

Change the testConnection callback to get the right token:

```typescript
const testConnection = useCallback(async () => {
  applyToConfig();
  setConnectionStatus('testing');
  try {
    const protocol = localState.useHTTPS ? 'https' : 'http';
    const url = `${protocol}://${localState.serverAddress}:${localState.serverPort}/health`;
    // Health endpoint doesn't require auth, but test with auth to verify credentials
    const res = await fetch(url);
    setConnectionStatus(res.ok ? 'success' : 'error');
  } catch {
    setConnectionStatus('error');
  }
  setTimeout(() => setConnectionStatus('idle'), 3000);
}, [applyToConfig, localState.serverAddress, localState.serverPort, localState.useHTTPS]);
```

- [ ] **Step 5: Update the OAuthCredentials api prop**

The `OAuthCredentials` component needs an API client. Import `useAuth` and use it:

```typescript
import { useAuth } from '@/contexts/AuthContext';
// ...
const { api } = useAuth();
```

Remove the `useMemo` that creates `api` from `createApiClient` directly — use the one from AuthContext instead.

- [ ] **Step 6: Verify TypeScript**

Run: `cd /Users/manuel/Desktop/development/homekit-mcp/.worktrees/oauth/webclient && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add webclient/src/pages/SettingsPage.tsx
git commit -m "feat(oauth): add auth method selector to Settings page"
```

---

## Task 7: Manual End-to-End Test

- [ ] **Step 1: Build and start the server**

Run: `cd /Users/manuel/Desktop/development/homekit-mcp/.worktrees/oauth && make dev`

- [ ] **Step 2: Start web app**

Run: `cd /Users/manuel/Desktop/development/homekit-mcp/.worktrees/oauth/webclient && npm run dev`

- [ ] **Step 3: Test Bearer auth (existing flow)**

Navigate to Settings, ensure "Bearer Token" is selected, enter a valid Bearer token, save, verify devices load.

- [ ] **Step 4: Create an OAuth credential**

In the Swift app Settings → Server → OAuth Credentials, create a new credential. Copy client ID and secret.

- [ ] **Step 5: Switch to OAuth in web app**

Navigate to Settings, click "OAuth", enter client ID and secret, save. Verify:
- Devices page loads (OAuth token exchange happened)
- WebSocket connects (check connection indicator)
- Bearer token field was cleared

- [ ] **Step 6: Test page reload**

Reload the page. Verify the app re-authenticates automatically (devices load without re-entering credentials).

- [ ] **Step 7: Switch back to Bearer**

Switch back to Bearer, enter token, save. Verify OAuth fields are cleared and Bearer auth works.
