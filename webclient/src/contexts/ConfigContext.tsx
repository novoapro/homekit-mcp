import { createContext, useContext, useState, useCallback, useMemo, type ReactNode } from 'react';

const STORAGE_PREFIX = 'hk-log-viewer';
const SAVED_KEY = `${STORAGE_PREFIX}:_saved`;

/** True when the user has explicitly saved settings at least once. */
function hasUserSaved(): boolean {
  return localStorage.getItem(SAVED_KEY) === '1';
}

function loadString(key: string, fallback: string): string {
  return localStorage.getItem(`${STORAGE_PREFIX}:${key}`) ?? fallback;
}

function loadNumber(key: string, fallback: number): number {
  const v = localStorage.getItem(`${STORAGE_PREFIX}:${key}`);
  return v !== null ? Number(v) : fallback;
}

function loadBool(key: string, fallback: boolean): boolean {
  const v = localStorage.getItem(`${STORAGE_PREFIX}:${key}`);
  return v !== null ? v === 'true' : fallback;
}

/** Build defaults from env vars (dev) or hardcoded values (prod). */
function envDefaults(): ConfigState {
  return {
    serverAddress: import.meta.env.VITE_DEFAULT_SERVER_ADDRESS || 'localhost',
    serverPort: Number(import.meta.env.VITE_DEFAULT_SERVER_PORT) || 3000,
    bearerToken: import.meta.env.VITE_DEFAULT_BEARER_TOKEN || '',
    pollingInterval: 300,
    websocketEnabled: true,
    useHTTPS: import.meta.env.VITE_DEFAULT_USE_HTTPS === 'true',
    authMethod: 'bearer' as const,
    oauthClientId: '',
    oauthClientSecret: '',
  };
}

/** Load config: use localStorage if user explicitly saved, otherwise env defaults. */
function loadConfig(): ConfigState {
  const defaults = envDefaults();
  if (!hasUserSaved()) return defaults;
  return {
    serverAddress: loadString('serverAddress', defaults.serverAddress),
    serverPort: loadNumber('serverPort', defaults.serverPort),
    bearerToken: loadString('bearerToken', defaults.bearerToken),
    pollingInterval: loadNumber('pollingInterval', defaults.pollingInterval),
    websocketEnabled: loadBool('websocketEnabled', defaults.websocketEnabled),
    useHTTPS: loadBool('useHTTPS', defaults.useHTTPS),
    authMethod: (loadString('authMethod', defaults.authMethod) as 'bearer' | 'oauth'),
    oauthClientId: loadString('oauthClientId', defaults.oauthClientId),
    oauthClientSecret: loadString('oauthClientSecret', defaults.oauthClientSecret),
  };
}

export interface ConfigState {
  serverAddress: string;
  serverPort: number;
  bearerToken: string;
  pollingInterval: number;
  websocketEnabled: boolean;
  useHTTPS: boolean;
  authMethod: 'bearer' | 'oauth';
  oauthClientId: string;
  oauthClientSecret: string;
}

interface ConfigContextValue {
  config: ConfigState;
  isConfigured: boolean;
  baseUrl: string;
  setConfig: (updates: Partial<ConfigState>) => void;
  save: (state?: ConfigState) => void;
  reset: () => void;
}

const ConfigContext = createContext<ConfigContextValue | null>(null);

export function ConfigProvider({ children }: { children: ReactNode }) {
  const [config, setConfigState] = useState<ConfigState>(loadConfig);

  const isConfigured = config.authMethod === 'oauth'
    ? !!(config.oauthClientId && config.oauthClientSecret)
    : !!config.bearerToken;
  const httpProtocol = config.useHTTPS ? 'https' : 'http';
  const baseUrl = `${httpProtocol}://${config.serverAddress}:${config.serverPort}`;

  const setConfig = useCallback((updates: Partial<ConfigState>) => {
    setConfigState(prev => ({ ...prev, ...updates }));
  }, []);

  const save = useCallback((state?: ConfigState) => {
    const s = state ?? config;
    localStorage.setItem(SAVED_KEY, '1');
    localStorage.setItem(`${STORAGE_PREFIX}:serverAddress`, s.serverAddress);
    localStorage.setItem(`${STORAGE_PREFIX}:serverPort`, String(s.serverPort));
    localStorage.setItem(`${STORAGE_PREFIX}:bearerToken`, s.bearerToken);
    localStorage.setItem(`${STORAGE_PREFIX}:pollingInterval`, String(s.pollingInterval));
    localStorage.setItem(`${STORAGE_PREFIX}:websocketEnabled`, String(s.websocketEnabled));
    localStorage.setItem(`${STORAGE_PREFIX}:useHTTPS`, String(s.useHTTPS));
    localStorage.setItem(`${STORAGE_PREFIX}:authMethod`, s.authMethod);
    localStorage.setItem(`${STORAGE_PREFIX}:oauthClientId`, s.oauthClientId);
    localStorage.setItem(`${STORAGE_PREFIX}:oauthClientSecret`, s.oauthClientSecret);
  }, [config]);

  const reset = useCallback(() => {
    const keys = ['serverAddress', 'serverPort', 'bearerToken', 'pollingInterval', 'websocketEnabled', 'useHTTPS', 'authMethod', 'oauthClientId', 'oauthClientSecret'];
    keys.forEach(k => localStorage.removeItem(`${STORAGE_PREFIX}:${k}`));
    localStorage.removeItem(SAVED_KEY);
    setConfigState(envDefaults());
  }, []);

  const value = useMemo<ConfigContextValue>(
    () => ({ config, isConfigured, baseUrl, setConfig, save, reset }),
    [config, isConfigured, baseUrl, setConfig, save, reset],
  );

  return (
    <ConfigContext.Provider value={value}>
      {children}
    </ConfigContext.Provider>
  );
}

export function useConfig(): ConfigContextValue {
  const ctx = useContext(ConfigContext);
  if (!ctx) throw new Error('useConfig must be used within ConfigProvider');
  return ctx;
}
