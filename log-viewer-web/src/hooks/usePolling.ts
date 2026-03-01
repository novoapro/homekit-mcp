import { useReducer, useRef, useEffect, useCallback } from 'react';
import { useApi } from './useApi';
import { useConfig } from '@/contexts/ConfigContext';
import type { StateChangeLog } from '@/types/state-change-log';
import type { LogQueryParams } from '@/types/api-response';

interface PollingState {
  logs: StateChangeLog[];
  totalCount: number;
  isLoading: boolean;
  isPolling: boolean;
  lastPollTime: Date | null;
  error: string | null;
}

type PollingAction =
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_POLLING'; payload: boolean }
  | { type: 'SET_LOGS'; payload: { logs: StateChangeLog[]; total: number } }
  | { type: 'APPEND_LOGS'; payload: { logs: StateChangeLog[]; total: number } }
  | { type: 'INJECT_LOG'; payload: StateChangeLog }
  | { type: 'UPDATE_LOG'; payload: StateChangeLog }
  | { type: 'CLEAR_ALL' }
  | { type: 'SET_ERROR'; payload: string | null }
  | { type: 'SET_POLL_TIME'; payload: Date };

const TERMINAL_STATUSES = new Set(['success', 'failure', 'skipped', 'conditionNotMet', 'cancelled']);

function pollingReducer(state: PollingState, action: PollingAction): PollingState {
  switch (action.type) {
    case 'SET_LOADING':
      return { ...state, isLoading: action.payload };
    case 'SET_POLLING':
      return { ...state, isPolling: action.payload };
    case 'SET_LOGS':
      return {
        ...state,
        logs: action.payload.logs,
        totalCount: action.payload.total,
        isLoading: false,
        error: null,
        lastPollTime: new Date(),
      };
    case 'APPEND_LOGS':
      return {
        ...state,
        logs: [...state.logs, ...action.payload.logs],
        totalCount: action.payload.total,
        isLoading: false,
      };
    case 'INJECT_LOG': {
      if (state.logs.some(l => l.id === action.payload.id)) return state;
      return {
        ...state,
        logs: [action.payload, ...state.logs],
        totalCount: state.totalCount + 1,
      };
    }
    case 'UPDATE_LOG': {
      const idx = state.logs.findIndex(l => l.id === action.payload.id);
      if (idx === -1) {
        // Not in list — inject as new
        if (state.logs.some(l => l.id === action.payload.id)) return state;
        return {
          ...state,
          logs: [action.payload, ...state.logs],
          totalCount: state.totalCount + 1,
        };
      }
      // Don't let stale "running" overwrite terminal status
      const existingStatus = state.logs[idx]?.workflowExecution?.status;
      const incomingStatus = action.payload.workflowExecution?.status;
      if (existingStatus && TERMINAL_STATUSES.has(existingStatus) && incomingStatus === 'running') {
        return state;
      }
      const updated = [...state.logs];
      updated[idx] = action.payload;
      return { ...state, logs: updated };
    }
    case 'CLEAR_ALL':
      return { ...state, logs: [], totalCount: 0 };
    case 'SET_ERROR':
      return { ...state, error: action.payload, isLoading: false };
    case 'SET_POLL_TIME':
      return { ...state, lastPollTime: action.payload };
    default:
      return state;
  }
}

const initialState: PollingState = {
  logs: [],
  totalCount: 0,
  isLoading: false,
  isPolling: false,
  lastPollTime: null,
  error: null,
};

export function usePolling() {
  const [state, dispatch] = useReducer(pollingReducer, initialState);
  const api = useApi();
  const { config } = useConfig();

  const latestTimestampRef = useRef<string | null>(null);
  const activeParamsRef = useRef<Partial<LogQueryParams>>({});
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const isDocumentVisibleRef = useRef(true);

  // Track document visibility
  useEffect(() => {
    const handler = () => {
      isDocumentVisibleRef.current = document.visibilityState === 'visible';
    };
    document.addEventListener('visibilitychange', handler);
    return () => document.removeEventListener('visibilitychange', handler);
  }, []);

  const fetchLogs = useCallback(async () => {
    if (!isDocumentVisibleRef.current) return;

    try {
      const params: LogQueryParams = {
        ...activeParamsRef.current,
        ...(latestTimestampRef.current ? { from: latestTimestampRef.current } : {}),
        limit: 200,
      };

      const res = await api.getLogs(params);

      if (latestTimestampRef.current && res.logs.length > 0) {
        // Merge — dispatch will handle dedup at the reducer level
        // But we filter here to avoid large dispatches
        dispatch({ type: 'SET_LOGS', payload: { logs: res.logs, total: res.total } });
      } else if (!latestTimestampRef.current) {
        dispatch({ type: 'SET_LOGS', payload: { logs: res.logs, total: res.total } });
      }

      if (res.logs.length > 0 && res.logs[0]) {
        latestTimestampRef.current = res.logs[0].timestamp;
      }
    } catch (err) {
      dispatch({ type: 'SET_ERROR', payload: err instanceof Error ? err.message : 'Polling failed' });
    }
  }, [api]);

  const startPolling = useCallback(() => {
    if (pollTimerRef.current) clearInterval(pollTimerRef.current);

    const interval = config.pollingInterval;
    if (interval <= 0) return;

    dispatch({ type: 'SET_POLLING', payload: true });
    fetchLogs(); // Initial fetch
    pollTimerRef.current = setInterval(fetchLogs, interval * 1000);
  }, [config.pollingInterval, fetchLogs]);

  const stopPolling = useCallback(() => {
    if (pollTimerRef.current) {
      clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
    dispatch({ type: 'SET_POLLING', payload: false });
  }, []);

  const loadFresh = useCallback(async (params: Partial<LogQueryParams> = {}) => {
    activeParamsRef.current = params;
    latestTimestampRef.current = null;
    dispatch({ type: 'SET_LOADING', payload: true });

    try {
      const res = await api.getLogs({ ...params, limit: 200 });
      dispatch({ type: 'SET_LOGS', payload: { logs: res.logs, total: res.total } });
      if (res.logs.length > 0 && res.logs[0]) {
        latestTimestampRef.current = res.logs[0].timestamp;
      }
    } catch (err) {
      dispatch({ type: 'SET_ERROR', payload: err instanceof Error ? err.message : 'Failed to fetch logs' });
    }
  }, [api]);

  const loadMore = useCallback(async (params: Partial<LogQueryParams> = {}) => {
    dispatch({ type: 'SET_LOADING', payload: true });

    try {
      const res = await api.getLogs({ ...params, offset: state.logs.length, limit: 50 });
      dispatch({ type: 'APPEND_LOGS', payload: { logs: res.logs, total: res.total } });
    } catch (err) {
      dispatch({ type: 'SET_ERROR', payload: err instanceof Error ? err.message : 'Failed to load more' });
    }
  }, [api, state.logs.length]);

  const injectLog = useCallback((log: StateChangeLog) => {
    dispatch({ type: 'INJECT_LOG', payload: log });
  }, []);

  const updateLog = useCallback((log: StateChangeLog) => {
    dispatch({ type: 'UPDATE_LOG', payload: log });
  }, []);

  const clearAll = useCallback(() => {
    dispatch({ type: 'CLEAR_ALL' });
    latestTimestampRef.current = null;
  }, []);

  const refresh = useCallback(() => {
    fetchLogs();
  }, [fetchLogs]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (pollTimerRef.current) clearInterval(pollTimerRef.current);
    };
  }, []);

  return {
    ...state,
    startPolling,
    stopPolling,
    loadFresh,
    loadMore,
    injectLog,
    updateLog,
    clearAll,
    refresh,
  };
}
