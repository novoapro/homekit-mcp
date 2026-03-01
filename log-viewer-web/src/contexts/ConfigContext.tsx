import { createContext, useContext, useState, useCallback, useMemo, type ReactNode } from 'react';

const STORAGE_PREFIX = 'hk-log-viewer';

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

export interface ConfigState {
  serverAddress: string;
  serverPort: number;
  bearerToken: string;
  pollingInterval: number;
  websocketEnabled: boolean;
}

interface ConfigContextValue {
  config: ConfigState;
  isConfigured: boolean;
  baseUrl: string;
  setConfig: (updates: Partial<ConfigState>) => void;
  save: (state?: ConfigState) => void;
}

const ConfigContext = createContext<ConfigContextValue | null>(null);

export function ConfigProvider({ children }: { children: ReactNode }) {
  const [config, setConfigState] = useState<ConfigState>(() => ({
    serverAddress: loadString('serverAddress', 'localhost'),
    serverPort: loadNumber('serverPort', 3000),
    bearerToken: loadString('bearerToken', ''),
    pollingInterval: loadNumber('pollingInterval', 10),
    websocketEnabled: loadBool('websocketEnabled', true),
  }));

  const isConfigured = !!config.bearerToken;
  const baseUrl = `http://${config.serverAddress}:${config.serverPort}`;

  const setConfig = useCallback((updates: Partial<ConfigState>) => {
    setConfigState(prev => ({ ...prev, ...updates }));
  }, []);

  const save = useCallback((state?: ConfigState) => {
    const s = state ?? config;
    localStorage.setItem(`${STORAGE_PREFIX}:serverAddress`, s.serverAddress);
    localStorage.setItem(`${STORAGE_PREFIX}:serverPort`, String(s.serverPort));
    localStorage.setItem(`${STORAGE_PREFIX}:bearerToken`, s.bearerToken);
    localStorage.setItem(`${STORAGE_PREFIX}:pollingInterval`, String(s.pollingInterval));
    localStorage.setItem(`${STORAGE_PREFIX}:websocketEnabled`, String(s.websocketEnabled));
  }, [config]);

  const value = useMemo<ConfigContextValue>(
    () => ({ config, isConfigured, baseUrl, setConfig, save }),
    [config, isConfigured, baseUrl, setConfig, save],
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
