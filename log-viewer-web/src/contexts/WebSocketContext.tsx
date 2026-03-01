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
import type { WorkflowExecutionLog, Workflow } from '@/types/workflow-log';

export type WSConnectionState = 'disconnected' | 'connecting' | 'connected';

type LogHandler = (log: StateChangeLog) => void;
type WorkflowLogHandler = (event: { type: 'new' | 'updated'; data: WorkflowExecutionLog }) => void;
type WorkflowsUpdatedHandler = (workflows: Workflow[]) => void;
type VoidHandler = () => void;

interface WebSocketContextValue {
  connectionState: WSConnectionState;
  isConnected: boolean;
  reconnect: () => void;
  disconnect: () => void;
  onLog: (handler: LogHandler) => () => void;
  onWorkflowLog: (handler: WorkflowLogHandler) => () => void;
  onWorkflowsUpdated: (handler: WorkflowsUpdatedHandler) => () => void;
  onDevicesUpdated: (handler: VoidHandler) => () => void;
  onLogsCleared: (handler: VoidHandler) => () => void;
  onReconnected: (handler: VoidHandler) => () => void;
}

const WebSocketContext = createContext<WebSocketContextValue | null>(null);

const MAX_RECONNECT_ATTEMPTS = 10;
const BASE_RECONNECT_DELAY = 1000;
const MAX_RECONNECT_DELAY = 30000;

export function WebSocketProvider({ children }: { children: ReactNode }) {
  const { config } = useConfig();
  const [connectionState, setConnectionState] = useState<WSConnectionState>('disconnected');

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectAttemptsRef = useRef(0);
  const intentionalCloseRef = useRef(false);

  // Event handler registries
  const logHandlers = useRef(new Set<LogHandler>());
  const workflowLogHandlers = useRef(new Set<WorkflowLogHandler>());
  const workflowsUpdatedHandlers = useRef(new Set<WorkflowsUpdatedHandler>());
  const devicesUpdatedHandlers = useRef(new Set<VoidHandler>());
  const logsClearedHandlers = useRef(new Set<VoidHandler>());
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
    const url = `ws://${cfg.serverAddress}:${cfg.serverPort}/ws?token=${token}`;

    let socket: WebSocket;
    try {
      socket = new WebSocket(url);
    } catch {
      setConnectionState('disconnected');
      scheduleReconnect();
      return;
    }

    wsRef.current = socket;

    socket.onopen = () => {
      setConnectionState('connected');
      if (reconnectAttemptsRef.current > 0) {
        reconnectedHandlers.current.forEach(h => h());
      }
      reconnectAttemptsRef.current = 0;
    };

    socket.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data as string) as { type: string; data: unknown };
        switch (msg.type) {
          case 'log':
            logHandlers.current.forEach(h => h(msg.data as StateChangeLog));
            break;
          case 'workflow_log':
            workflowLogHandlers.current.forEach(h =>
              h({ type: 'new', data: msg.data as WorkflowExecutionLog }),
            );
            break;
          case 'workflow_log_updated':
            workflowLogHandlers.current.forEach(h =>
              h({ type: 'updated', data: msg.data as WorkflowExecutionLog }),
            );
            break;
          case 'workflows_updated':
            workflowsUpdatedHandlers.current.forEach(h => h(msg.data as Workflow[]));
            break;
          case 'devices_updated':
            devicesUpdatedHandlers.current.forEach(h => h());
            break;
          case 'logs_cleared':
            logsClearedHandlers.current.forEach(h => h());
            break;
        }
      } catch {
        // Ignore malformed messages
      }
    };

    socket.onclose = () => {
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

  // Subscription helpers
  const subscribe = useCallback(
    function subscribeToSet<T>(set: React.RefObject<Set<T>>, handler: T): () => void {
      set.current.add(handler);
      return () => { set.current.delete(handler); };
    },
    [],
  );

  const onLog = useCallback((h: LogHandler) => subscribe(logHandlers, h), [subscribe]);
  const onWorkflowLog = useCallback((h: WorkflowLogHandler) => subscribe(workflowLogHandlers, h), [subscribe]);
  const onWorkflowsUpdated = useCallback((h: WorkflowsUpdatedHandler) => subscribe(workflowsUpdatedHandlers, h), [subscribe]);
  const onDevicesUpdated = useCallback((h: VoidHandler) => subscribe(devicesUpdatedHandlers, h), [subscribe]);
  const onLogsCleared = useCallback((h: VoidHandler) => subscribe(logsClearedHandlers, h), [subscribe]);
  const onReconnected = useCallback((h: VoidHandler) => subscribe(reconnectedHandlers, h), [subscribe]);

  const value = useMemo<WebSocketContextValue>(
    () => ({
      connectionState,
      isConnected: connectionState === 'connected',
      reconnect,
      disconnect,
      onLog,
      onWorkflowLog,
      onWorkflowsUpdated,
      onDevicesUpdated,
      onLogsCleared,
      onReconnected,
    }),
    [connectionState, reconnect, disconnect, onLog, onWorkflowLog, onWorkflowsUpdated, onDevicesUpdated, onLogsCleared, onReconnected],
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
