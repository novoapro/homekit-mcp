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
    if (!tokens) {
      const result = await authenticate();
      return result.accessToken;
    }

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
