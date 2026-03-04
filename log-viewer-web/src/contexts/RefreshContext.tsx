import {
  createContext,
  useContext,
  useState,
  useCallback,
  useRef,
  useEffect,
  useMemo,
  type ReactNode,
} from 'react';
import { useWebSocket } from './WebSocketContext';

interface RefreshContextValue {
  isRefreshing: boolean;
  triggerRefresh: () => Promise<void>;
  registerRefresh: (cb: () => Promise<void>) => void;
  unregisterRefresh: () => void;
}

const RefreshContext = createContext<RefreshContextValue | null>(null);

export function RefreshProvider({ children }: { children: ReactNode }) {
  const [isRefreshing, setIsRefreshing] = useState(false);
  const refreshCallbackRef = useRef<(() => Promise<void>) | null>(null);
  const ws = useWebSocket();

  const registerRefresh = useCallback((cb: () => Promise<void>) => {
    refreshCallbackRef.current = cb;
  }, []);

  const unregisterRefresh = useCallback(() => {
    refreshCallbackRef.current = null;
  }, []);

  const triggerRefresh = useCallback(async () => {
    if (isRefreshing) return;
    setIsRefreshing(true);
    try {
      // Check WebSocket connectivity and reconnect if needed
      if (ws.connectionState === 'disconnected') {
        ws.reconnect();
      }
      // Call the page-specific refresh callback
      if (refreshCallbackRef.current) {
        await refreshCallbackRef.current();
      }
    } finally {
      setIsRefreshing(false);
    }
  }, [isRefreshing, ws]);

  const value = useMemo<RefreshContextValue>(
    () => ({ isRefreshing, triggerRefresh, registerRefresh, unregisterRefresh }),
    [isRefreshing, triggerRefresh, registerRefresh, unregisterRefresh],
  );

  return (
    <RefreshContext.Provider value={value}>
      {children}
    </RefreshContext.Provider>
  );
}

export function useRefresh(): RefreshContextValue {
  const ctx = useContext(RefreshContext);
  if (!ctx) throw new Error('useRefresh must be used within RefreshProvider');
  return ctx;
}

/**
 * Hook for pages to register their refresh callback.
 * Automatically unregisters on unmount.
 */
export function useRegisterRefresh(callback: () => Promise<void>) {
  const { registerRefresh, unregisterRefresh } = useRefresh();

  useEffect(() => {
    registerRefresh(callback);
    return () => unregisterRefresh();
  }, [callback, registerRefresh, unregisterRefresh]);
}
