import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from './WebSocketContext';
import type { SubscriptionStatus } from '@/lib/api';

interface SubscriptionContextValue {
  tier: 'free' | 'pro';
  isPro: boolean;
  loading: boolean;
  refresh: () => void;
}

const SubscriptionContext = createContext<SubscriptionContextValue | null>(null);

export function SubscriptionProvider({ children }: { children: ReactNode }) {
  const api = useApi();
  const ws = useWebSocket();
  const [status, setStatus] = useState<SubscriptionStatus>({ tier: 'free', isPro: false });
  const [loading, setLoading] = useState(true);

  const fetchStatus = useCallback(() => {
    api.getSubscriptionStatus()
      .then((s) => {
        setStatus(s);
        setLoading(false);
      })
      .catch(() => {
        // Server may not be reachable or endpoint may not exist yet
        setLoading(false);
      });
  }, [api]);

  // Fetch on mount
  useEffect(() => {
    fetchStatus();
  }, [fetchStatus]);

  // Re-fetch when window regains focus
  useEffect(() => {
    const onFocus = () => fetchStatus();
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') onFocus();
    });
    return () => {
      document.removeEventListener('visibilitychange', onFocus);
    };
  }, [fetchStatus]);

  // Listen for WebSocket subscription_changed events
  useEffect(() => {
    const unsub = ws.onSubscriptionChanged((data) => {
      setStatus({ tier: data.tier as 'free' | 'pro', isPro: data.isPro });
    });
    return unsub;
  }, [ws]);

  // Re-fetch on WebSocket reconnect
  useEffect(() => {
    const unsub = ws.onReconnected(() => {
      fetchStatus();
    });
    return unsub;
  }, [ws, fetchStatus]);

  const value = useMemo<SubscriptionContextValue>(() => ({
    tier: status.tier,
    isPro: status.isPro,
    loading,
    refresh: fetchStatus,
  }), [status, loading, fetchStatus]);

  return (
    <SubscriptionContext.Provider value={value}>
      {children}
    </SubscriptionContext.Provider>
  );
}

export function useSubscription(): SubscriptionContextValue {
  const ctx = useContext(SubscriptionContext);
  if (!ctx) throw new Error('useSubscription must be used within SubscriptionProvider');
  return ctx;
}
