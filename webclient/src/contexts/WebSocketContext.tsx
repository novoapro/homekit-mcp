import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import { useConfig } from './ConfigContext';
import type { StateChangeLog } from '@/types/state-change-log';
import type { AutomationExecutionLog, Automation } from '@/types/automation-log';
import type { CharacteristicUpdateEvent } from '@/types/homekit-device';

export type WSConnectionState = 'disconnected' | 'connecting' | 'connected';

type LogHandler = (log: StateChangeLog) => void;
type AutomationLogHandler = (event: { type: 'new' | 'updated'; data: AutomationExecutionLog }) => void;
type AutomationsUpdatedHandler = (automations: Automation[]) => void;
type CharacteristicUpdatedHandler = (event: CharacteristicUpdateEvent) => void;
export type SubscriptionChangedHandler = (data: { tier: string; isPro: boolean }) => void;
type VoidHandler = () => void;

interface WebSocketContextValue {
  connectionState: WSConnectionState;
  isConnected: boolean;
  reconnect: () => void;
  disconnect: () => void;
  onLog: (handler: LogHandler) => () => void;
  onAutomationLog: (handler: AutomationLogHandler) => () => void;
  onAutomationsUpdated: (handler: AutomationsUpdatedHandler) => () => void;
  onDevicesUpdated: (handler: VoidHandler) => () => void;
  onCharacteristicUpdated: (handler: CharacteristicUpdatedHandler) => () => void;
  onLogsCleared: (handler: VoidHandler) => () => void;
  onSubscriptionChanged: (handler: SubscriptionChangedHandler) => () => void;
  onReconnected: (handler: VoidHandler) => () => void;
}

const WebSocketContext = createContext<WebSocketContextValue | null>(null);

const MAX_RECONNECT_ATTEMPTS = 10;
const BASE_RECONNECT_DELAY = 1000;
const MAX_RECONNECT_DELAY = 30000;
const CONNECT_TIMEOUT = 5000;

export function WebSocketProvider({ children }: { children: ReactNode }) {
  const { config } = useConfig();
  const [connectionState, setConnectionState] = useState<WSConnectionState>('disconnected');

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const connectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectAttemptsRef = useRef(0);
  const intentionalCloseRef = useRef(false);

  // Event handler registries
  const logHandlers = useRef(new Set<LogHandler>());
  const automationLogHandlers = useRef(new Set<AutomationLogHandler>());
  const automationsUpdatedHandlers = useRef(new Set<AutomationsUpdatedHandler>());
  const devicesUpdatedHandlers = useRef(new Set<VoidHandler>());
  const characteristicUpdatedHandlers = useRef(new Set<CharacteristicUpdatedHandler>());
  const logsClearedHandlers = useRef(new Set<VoidHandler>());
  const subscriptionChangedHandlers = useRef(new Set<SubscriptionChangedHandler>());
  const reconnectedHandlers = useRef(new Set<VoidHandler>());

  // Stable config ref for use inside WebSocket callbacks
  const configRef = useRef(config);
  configRef.current = config;

  const clearReconnectTimer = useCallback(() => {
    if (reconnectTimerRef.current) {
      clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }
  }, []);

  const scheduleReconnect = useCallback(() => {
    if (reconnectAttemptsRef.current >= MAX_RECONNECT_ATTEMPTS) return;
    if (!configRef.current.websocketEnabled) return;

    clearReconnectTimer();

    const delay = Math.min(
      BASE_RECONNECT_DELAY * Math.pow(2, reconnectAttemptsRef.current),
      MAX_RECONNECT_DELAY,
    );

    reconnectTimerRef.current = setTimeout(() => {
      reconnectAttemptsRef.current++;
      connect();
    }, delay);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clearReconnectTimer]);

  const connect = useCallback(() => {
    const cfg = configRef.current;
    if (!cfg.websocketEnabled) return;
    if (!cfg.bearerToken) return;

    const ws = wsRef.current;
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;

    intentionalCloseRef.current = false;
    setConnectionState('connecting');

    const token = encodeURIComponent(cfg.bearerToken);
    const wsProtocol = cfg.useHTTPS ? 'wss' : 'ws';
    const url = `${wsProtocol}://${cfg.serverAddress}:${cfg.serverPort}/ws?token=${token}`;

    let socket: WebSocket;
    try {
      socket = new WebSocket(url);
    } catch {
      setConnectionState('disconnected');
      scheduleReconnect();
      return;
    }

    wsRef.current = socket;

    // Timeout: if socket doesn't open within CONNECT_TIMEOUT, kill it and retry.
    if (connectTimeoutRef.current) clearTimeout(connectTimeoutRef.current);
    connectTimeoutRef.current = setTimeout(() => {
      connectTimeoutRef.current = null;
      if (wsRef.current === socket && socket.readyState !== WebSocket.OPEN) {
        wsRef.current = null;
        try { socket.close(); } catch { /* ignore */ }
        setConnectionState('disconnected');
        scheduleReconnect();
      }
    }, CONNECT_TIMEOUT);

    socket.onopen = () => {
      if (wsRef.current !== socket) return;
      if (connectTimeoutRef.current) {
        clearTimeout(connectTimeoutRef.current);
        connectTimeoutRef.current = null;
      }
      setConnectionState('connected');
      if (reconnectAttemptsRef.current > 0) {
        reconnectedHandlers.current.forEach(h => h());
      }
      reconnectAttemptsRef.current = 0;
    };

    socket.onmessage = (event) => {
      if (wsRef.current !== socket) return;
      try {
        const msg = JSON.parse(event.data as string) as { type: string; data: unknown };
        switch (msg.type) {
          case 'log':
            logHandlers.current.forEach(h => h(msg.data as StateChangeLog));
            break;
          case 'automation_log':
            automationLogHandlers.current.forEach(h =>
              h({ type: 'new', data: msg.data as AutomationExecutionLog }),
            );
            break;
          case 'automation_log_updated':
            automationLogHandlers.current.forEach(h =>
              h({ type: 'updated', data: msg.data as AutomationExecutionLog }),
            );
            break;
          case 'automations_updated':
            automationsUpdatedHandlers.current.forEach(h => h(msg.data as Automation[]));
            break;
          case 'devices_updated':
            devicesUpdatedHandlers.current.forEach(h => h());
            break;
          case 'characteristic_updated':
            characteristicUpdatedHandlers.current.forEach(h => h(msg.data as CharacteristicUpdateEvent));
            break;
          case 'logs_cleared':
            logsClearedHandlers.current.forEach(h => h());
            break;
          case 'subscription_changed':
            subscriptionChangedHandlers.current.forEach(h => h(msg.data as { tier: string; isPro: boolean }));
            break;
        }
      } catch (err) {
        console.warn('[WebSocket] Failed to parse message:', (event.data as string).substring(0, 200), err);
      }
    };

    socket.onclose = () => {
      if (wsRef.current !== socket) return;
      if (connectTimeoutRef.current) {
        clearTimeout(connectTimeoutRef.current);
        connectTimeoutRef.current = null;
      }
      setConnectionState('disconnected');
      wsRef.current = null;
      if (!intentionalCloseRef.current) {
        scheduleReconnect();
      }
    };

    socket.onerror = () => {
      // onclose fires after onerror, reconnect handled there
    };
  }, [scheduleReconnect]);

  const disconnect = useCallback(() => {
    intentionalCloseRef.current = true;
    clearReconnectTimer();
    if (connectTimeoutRef.current) {
      clearTimeout(connectTimeoutRef.current);
      connectTimeoutRef.current = null;
    }
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    setConnectionState('disconnected');
    reconnectAttemptsRef.current = 0;
  }, [clearReconnectTimer]);

  const reconnect = useCallback(() => {
    disconnect();
    if (configRef.current.websocketEnabled) {
      setTimeout(() => connect(), 100);
    }
  }, [disconnect, connect]);

  // Auto-connect on mount and when config changes
  useEffect(() => {
    if (config.websocketEnabled && config.bearerToken) {
      connect();
    } else {
      disconnect();
    }
    return () => disconnect();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [config.websocketEnabled, config.bearerToken, config.serverAddress, config.serverPort]);

  // iOS standalone (home screen) apps break WebSocket after freeze/thaw:
  // new WebSocket() creates a socket that gets stuck in CONNECTING forever.
  // The only fix is a page reload to get a fresh JS context.
  // Strategy: periodically probe the server with fetch; if the server is
  // reachable but WebSocket can't connect after a few attempts, force reload.
  useEffect(() => {
    let probeInFlight = false;
    let wsFailsSinceProbe = 0;

    const interval = setInterval(async () => {
      if (document.visibilityState !== 'visible') return;
      if (!configRef.current.websocketEnabled) return;
      if (probeInFlight) return;

      const ws = wsRef.current;

      // Socket is healthy
      if (ws && ws.readyState === WebSocket.OPEN) {
        wsFailsSinceProbe = 0;
        return;
      }

      // Socket is dead or stuck in CONNECTING — probe the server
      const cfg = configRef.current;
      const httpProtocol = cfg.useHTTPS ? 'https' : 'http';
      const probeUrl = `${httpProtocol}://${cfg.serverAddress}:${cfg.serverPort}/health`;

      probeInFlight = true;
      try {
        const resp = await fetch(probeUrl, {
          signal: AbortSignal.timeout(3000),
          headers: { 'Authorization': `Bearer ${cfg.bearerToken}` },
        });

        if (resp.ok) {
          wsFailsSinceProbe++;

          if (wsFailsSinceProbe >= 3) {
            // Server is up but WebSocket is broken (iOS thaw bug) — reload
            window.location.reload();
            return;
          }

          // Kill whatever socket exists (might be stuck in CONNECTING)
          const staleWs = wsRef.current;
          if (staleWs) {
            staleWs.onopen = null;
            staleWs.onclose = null;
            staleWs.onerror = null;
            staleWs.onmessage = null;
            wsRef.current = null;
            try { staleWs.close(); } catch { /* ignore */ }
          }
          clearReconnectTimer();
          if (connectTimeoutRef.current) {
            clearTimeout(connectTimeoutRef.current);
            connectTimeoutRef.current = null;
          }
          intentionalCloseRef.current = false;
          reconnectAttemptsRef.current = 0;
          connect();
        }
      } catch {
        // Server unreachable — not a thaw issue, reset counter
        wsFailsSinceProbe = 0;
      } finally {
        probeInFlight = false;
      }
    }, 5000);

    return () => clearInterval(interval);
  }, [connect, clearReconnectTimer]);

  // Subscription helpers
  const subscribe = useCallback(
    function subscribeToSet<T>(set: React.RefObject<Set<T>>, handler: T): () => void {
      set.current.add(handler);
      return () => { set.current.delete(handler); };
    },
    [],
  );

  const onLog = useCallback((h: LogHandler) => subscribe(logHandlers, h), [subscribe]);
  const onAutomationLog = useCallback((h: AutomationLogHandler) => subscribe(automationLogHandlers, h), [subscribe]);
  const onAutomationsUpdated = useCallback((h: AutomationsUpdatedHandler) => subscribe(automationsUpdatedHandlers, h), [subscribe]);
  const onDevicesUpdated = useCallback((h: VoidHandler) => subscribe(devicesUpdatedHandlers, h), [subscribe]);
  const onCharacteristicUpdated = useCallback((h: CharacteristicUpdatedHandler) => subscribe(characteristicUpdatedHandlers, h), [subscribe]);
  const onLogsCleared = useCallback((h: VoidHandler) => subscribe(logsClearedHandlers, h), [subscribe]);
  const onSubscriptionChanged = useCallback((h: SubscriptionChangedHandler) => subscribe(subscriptionChangedHandlers, h), [subscribe]);
  const onReconnected = useCallback((h: VoidHandler) => subscribe(reconnectedHandlers, h), [subscribe]);

  const value = useMemo<WebSocketContextValue>(
    () => ({
      connectionState,
      isConnected: connectionState === 'connected',
      reconnect,
      disconnect,
      onLog,
      onAutomationLog,
      onAutomationsUpdated,
      onDevicesUpdated,
      onCharacteristicUpdated,
      onLogsCleared,
      onSubscriptionChanged,
      onReconnected,
    }),
    [connectionState, reconnect, disconnect, onLog, onAutomationLog, onAutomationsUpdated, onDevicesUpdated, onCharacteristicUpdated, onLogsCleared, onSubscriptionChanged, onReconnected],
  );

  return (
    <WebSocketContext.Provider value={value}>
      {children}
    </WebSocketContext.Provider>
  );
}

export function useWebSocket(): WebSocketContextValue {
  const ctx = useContext(WebSocketContext);
  if (!ctx) throw new Error('useWebSocket must be used within WebSocketProvider');
  return ctx;
}
