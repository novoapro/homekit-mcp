import { useState, useMemo, useEffect, useCallback, useRef } from 'react';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { useRegisterRefresh } from '@/contexts/RefreshContext';
import { usePolling } from '@/hooks/usePolling';
import { useWebSocket } from '@/contexts/WebSocketContext';
import { useConfig } from '@/contexts/ConfigContext';
import { useDebounce } from '@/hooks/useDebounce';
import { getDayKey, getDayLabel } from '@/utils/date-utils';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { FilterBar } from '@/features/logs/FilterBar';
import { LogRow } from '@/features/logs/LogRow';
import { useApi } from '@/hooks/useApi';
import { LogCategory, getLogDisplayName, getLogRoomName, getLogSearchableText } from '@/types/state-change-log';
import type { StateChangeLog, AutomationLog } from '@/types/state-change-log';
import type { AutomationExecutionLog } from '@/types/automation-log';
import './LogsPage.css';

interface LogGroup {
  date: string;
  label: string;
  logs: StateChangeLog[];
}

function automationExecToStateChangeLog(e: AutomationExecutionLog): AutomationLog {
  const isError = e.status === 'failure';
  return {
    id: e.id,
    timestamp: e.triggeredAt,
    category: isError ? LogCategory.AutomationError : LogCategory.AutomationExecution,
    automationExecution: e,
  } as AutomationLog;
}

const FILTERS_STORAGE_KEY = 'logs-filters';

interface StoredFilters {
  categories: string[];
  devices: string[];
  rooms: string[];
  searchText: string;
  dateFrom: string | null;
  dateTo: string | null;
}

function loadStoredFilters(): StoredFilters | null {
  try {
    const raw = sessionStorage.getItem(FILTERS_STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as StoredFilters;
  } catch {
    return null;
  }
}

function saveFilters(filters: StoredFilters) {
  sessionStorage.setItem(FILTERS_STORAGE_KEY, JSON.stringify(filters));
}

export function LogsPage() {
  const polling = usePolling();
  const { startPolling, stopPolling, loadFresh, loadMore: pollingLoadMore, injectLog, updateLog, clearAll: clearPolling } = polling;
  const ws = useWebSocket();
  const { config } = useConfig();
  const api = useApi();

  const stored = useRef(loadStoredFilters());
  const [selectedCategories, setSelectedCategories] = useState<Set<string>>(
    () => new Set(stored.current?.categories ?? [])
  );
  const [selectedDevices, setSelectedDevices] = useState<Set<string>>(
    () => new Set(stored.current?.devices ?? [])
  );
  const [selectedRooms, setSelectedRooms] = useState<Set<string>>(
    () => new Set(stored.current?.rooms ?? [])
  );
  const [searchText, setSearchText] = useState(stored.current?.searchText ?? '');
  const [dateFrom, setDateFrom] = useState<string | null>(stored.current?.dateFrom ?? null);
  const [dateTo, setDateTo] = useState<string | null>(stored.current?.dateTo ?? null);

  // Persist filters to sessionStorage on change
  useEffect(() => {
    saveFilters({
      categories: Array.from(selectedCategories),
      devices: Array.from(selectedDevices),
      rooms: Array.from(selectedRooms),
      searchText,
      dateFrom,
      dateTo,
    });
  }, [selectedCategories, selectedDevices, selectedRooms, searchText, dateFrom, dateTo]);

  const debouncedSearch = useDebounce(searchText, 300);

  // Build query params for server-side filtering
  const buildQueryParams = useCallback((overrides?: { categories?: Set<string>; from?: string | null; to?: string | null }) => {
    const cats = overrides?.categories ?? selectedCategories;
    const from = overrides?.from !== undefined ? overrides.from : dateFrom;
    const to = overrides?.to !== undefined ? overrides.to : dateTo;
    const params: { categories?: string[]; device_name?: string; from?: string; to?: string } = {};
    if (cats.size > 0) params.categories = Array.from(cats);
    if (from) params.from = from;
    if (to) params.to = to;
    return params;
  }, [selectedCategories, dateFrom, dateTo]);

  const fetchWithFilters = useCallback(() => {
    loadFresh(buildQueryParams());
  }, [loadFresh, buildQueryParams]);

  useRegisterRefresh(useCallback(async () => {
    fetchWithFilters();
  }, [fetchWithFilters]));

  // Initial load (runs once)
  const hasLoadedRef = useRef(false);
  useEffect(() => {
    if (!hasLoadedRef.current) {
      hasLoadedRef.current = true;
      fetchWithFilters();
    }
  }, [fetchWithFilters]);

  // Polling lifecycle (restarts when interval changes)
  useEffect(() => {
    if (config.pollingInterval > 0) {
      startPolling();
    }
    return () => stopPolling();
  }, [config.pollingInterval, startPolling, stopPolling]);

  // WebSocket subscriptions
  useEffect(() => {
    const unsubs = [
      ws.onLog((log) => {
        injectLog(log);
      }),
      ws.onAutomationLog(({ type, data }) => {
        const entry = automationExecToStateChangeLog(data);
        if (type === 'new') {
          injectLog(entry);
        } else {
          updateLog(entry);
        }
      }),
      ws.onLogsCleared(() => {
        clearPolling();
      }),
      ws.onReconnected(() => {
        fetchWithFilters();
      }),
    ];
    return () => unsubs.forEach(fn => fn());
  }, [ws, injectLog, updateLog, clearPolling, fetchWithFilters]);

  // Derived: available devices and rooms from loaded logs
  const availableDevices = useMemo(() => {
    const devices = new Set<string>();
    for (const log of polling.logs) {
      const name = getLogDisplayName(log);
      if (name && name !== 'REST API') {
        devices.add(name);
      }
    }
    return Array.from(devices).sort();
  }, [polling.logs]);

  const availableRooms = useMemo(() => {
    const rooms = new Set<string>();
    for (const log of polling.logs) {
      const room = getLogRoomName(log);
      if (room) rooms.add(room);
    }
    return Array.from(rooms).sort();
  }, [polling.logs]);

  // Client-side filtering
  const filteredLogs = useMemo(() => {
    let logs = polling.logs;
    const search = debouncedSearch.toLowerCase();

    if (search) {
      logs = logs.filter(l => getLogSearchableText(l).includes(search));
    }

    const cats = selectedCategories;
    if (cats.size > 0) {
      logs = logs.filter(l => cats.has(l.category));
    }

    if (dateFrom) {
      const fromMs = new Date(dateFrom).getTime();
      logs = logs.filter(l => new Date(l.timestamp).getTime() >= fromMs);
    }
    if (dateTo) {
      const toMs = new Date(dateTo).getTime();
      logs = logs.filter(l => new Date(l.timestamp).getTime() <= toMs);
    }

    if (selectedDevices.size > 0) {
      logs = logs.filter(l => selectedDevices.has(getLogDisplayName(l)));
    }

    if (selectedRooms.size > 0) {
      logs = logs.filter(l => {
        const room = getLogRoomName(l);
        return room != null && selectedRooms.has(room);
      });
    }

    return logs;
  }, [polling.logs, debouncedSearch, selectedCategories, dateFrom, dateTo, selectedDevices, selectedRooms]);

  // Group logs by date
  const groupedLogs = useMemo<LogGroup[]>(() => {
    const groups = new Map<string, StateChangeLog[]>();

    for (const log of filteredLogs) {
      const key = getDayKey(log.timestamp);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key)!.push(log);
    }

    return Array.from(groups.entries())
      .sort((a, b) => b[0].localeCompare(a[0]))
      .map(([dateKey, logs]) => ({
        date: dateKey,
        label: getDayLabel(dateKey),
        logs,
      }));
  }, [filteredLogs]);

  const logCount = filteredLogs.length;
  const hasMore = polling.logs.length < polling.totalCount;
  useSetTopBar('Activity Log', logCount > 0 ? logCount : null, polling.isLoading);

  function onCategoriesChange(cats: Set<string>) {
    setSelectedCategories(cats);
    loadFresh(buildQueryParams({ categories: cats }));
  }

  function onDateRangeChange(range: { from: string | null; to: string | null }) {
    setDateFrom(range.from);
    setDateTo(range.to);
    loadFresh(buildQueryParams({ from: range.from, to: range.to }));
  }

  function onClearAll() {
    setSelectedCategories(new Set());
    setSelectedDevices(new Set());
    setSelectedRooms(new Set());
    setSearchText('');
    setDateFrom(null);
    setDateTo(null);
    loadFresh({});
  }

  const [showClearConfirm, setShowClearConfirm] = useState(false);

  function onClearLogs() {
    setShowClearConfirm(true);
  }

  function confirmClearLogs() {
    api.clearLogs().then(() => {
      clearPolling();
    });
    setShowClearConfirm(false);
  }

  function handleLoadMore() {
    pollingLoadMore(buildQueryParams());
  }

  return (
    <div className="logs-page">
      {/* Page header */}
      <div className="logs-page-header">
        <h1 className="logs-page-title">Activity Log</h1>
        <span className="log-count-badge">{logCount}</span>
        {polling.isLoading && <span className="loading-dot" />}
      </div>

      {/* Filter Bar */}
      <FilterBar
        availableDevices={availableDevices}
        availableRooms={availableRooms}
        selectedCategories={selectedCategories}
        selectedDevices={selectedDevices}
        selectedRooms={selectedRooms}
        searchText={searchText}
        logCount={logCount}
        onCategoriesChange={onCategoriesChange}
        onDevicesChange={setSelectedDevices}
        onRoomsChange={setSelectedRooms}
        onSearchTextChange={setSearchText}
        onDateRangeChange={onDateRangeChange}
        onClearAll={onClearAll}
        onClearLogs={onClearLogs}
      />

      {/* Error */}
      {polling.error && (
        <div className="error-banner animate-fade-in">
          <Icon name="exclamation-triangle" size={16} />
          <span>{polling.error}</span>
        </div>
      )}

      {/* Skeleton loading */}
      {polling.isLoading && groupedLogs.length === 0 && !polling.error && (
        <div className="skeleton-list">
          {Array.from({ length: 12 }, (_, i) => (
            <div key={i} className="skeleton-card skeleton" style={{ animationDelay: `${i * 100}ms` }} />
          ))}
        </div>
      )}

      {/* Empty state */}
      {groupedLogs.length === 0 && !polling.isLoading && (
        <EmptyState
          icon="bolt-circle-fill"
          title="No logs yet"
          message="Logs will appear here when devices change state, automations execute, or API calls are made."
        />
      )}

      {/* Log List */}
      {groupedLogs.length > 0 && (
        <div className="log-list">
          {groupedLogs.map((group) => (
            <div key={group.date} className="date-group">
              <div className="date-header">{group.label}</div>
              {group.logs.map((log, i) => (
                <LogRow key={log.id} log={log} index={i} />
              ))}
            </div>
          ))}

          {/* Load More */}
          {hasMore && (
            <div className="load-more">
              <button className="load-more-btn" onClick={handleLoadMore} disabled={polling.isLoading}>
                {polling.isLoading ? (
                  <>
                    <Icon name="spinner" size={16} />
                    <span>Loading...</span>
                  </>
                ) : (
                  <span>Load More</span>
                )}
              </button>
            </div>
          )}
        </div>
      )}

      <ConfirmDialog
        open={showClearConfirm}
        title="Clear All Logs"
        message="This will permanently delete all activity logs and automation execution history on the server."
        confirmLabel="Clear All"
        destructive
        onConfirm={confirmClearLogs}
        onCancel={() => setShowClearConfirm(false)}
      />
    </div>
  );
}
