import { createContext, useContext, useMemo, useCallback, useRef, type ReactNode } from 'react';
import { useConfig } from './ConfigContext';
import { createApiClient, type ApiClient } from '@/lib/api';
import { createOAuthClient } from '@/lib/oauth-client';

interface AuthContextValue {
  api: ApiClient;
  getAccessToken: () => Promise<string>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const { config, baseUrl } = useConfig();
  const oauthClientRef = useRef<ReturnType<typeof createOAuthClient> | null>(null);

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

  const api = useMemo(() => {
    if (config.authMethod === 'oauth' && oauthClient) {
      // Create a proxy that gets a fresh token for each call
      const baseClient = createApiClient(baseUrl, '');
      return new Proxy(baseClient, {
        get(target, prop, receiver) {
          const original = Reflect.get(target, prop, receiver);
          if (typeof original !== 'function') return original;
          if (prop === 'checkHealth') return original;

          return async (...args: unknown[]) => {
            const token = await oauthClient.getAccessToken();
            const authedClient = createApiClient(baseUrl, token);
            const method = authedClient[prop as keyof ApiClient];
            if (typeof method === 'function') {
              try {
                return await (method as (...a: unknown[]) => unknown)(...args);
              } catch (err) {
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
