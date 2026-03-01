import { useState, useMemo, useEffect, useCallback } from 'react';
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
import { LogCategory } from '@/types/state-change-log';
import type { StateChangeLog } from '@/types/state-change-log';
import type { WorkflowExecutionLog } from '@/types/workflow-log';
import './LogsPage.css';

interface LogGroup {
  date: string;
  label: string;
  logs: StateChangeLog[];
}

function workflowExecToStateChangeLog(e: WorkflowExecutionLog): StateChangeLog {
  const isError = e.status === 'failure' || e.status === 'cancelled';
  return {
    id: e.id,
    timestamp: e.triggeredAt,
    deviceId: e.workflowId,
    deviceName: e.workflowName,
    characteristicType: isError ? 'workflow-error' : 'workflow-execution',
    category: isError ? LogCategory.WorkflowError : LogCategory.WorkflowExecution,
    newValue: e.status,
    workflowExecution: e,
  };
}

export function LogsPage() {
  const polling = usePolling();
  const ws = useWebSocket();
  const { config } = useConfig();
  const api = useApi();

  const [selectedCategories, setSelectedCategories] = useState<Set<string>>(new Set());
  const [selectedDevices, setSelectedDevices] = useState<Set<string>>(new Set());
  const [selectedRooms, setSelectedRooms] = useState<Set<string>>(new Set());
  const [searchText, setSearchText] = useState('');
  const [dateFrom, setDateFrom] = useState<string | null>(null);
  const [dateTo, setDateTo] = useState<string | null>(null);

  const debouncedSearch = useDebounce(searchText, 300);

  // Build query params for server-side filtering
  const buildQueryParams = useCallback(() => {
    const params: { categories?: string[]; device_name?: string; from?: string; to?: string } = {};
    if (selectedCategories.size > 0) {
      params.categories = Array.from(selectedCategories);
    }
    if (dateFrom) params.from = dateFrom;
    if (dateTo) params.to = dateTo;
    return params;
  }, [selectedCategories, dateFrom, dateTo]);

  const fetchWithFilters = useCallback(() => {
    polling.loadFresh(buildQueryParams());
  }, [polling, buildQueryParams]);

  // Initial load + polling
  useEffect(() => {
    fetchWithFilters();
    if (config.pollingInterval > 0) {
      polling.startPolling();
    }
    return () => polling.stopPolling();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // WebSocket subscriptions
  useEffect(() => {
    const unsubs = [
      ws.onLog((log) => {
        polling.injectLog(log);
      }),
      ws.onWorkflowLog(({ type, data }) => {
        const entry = workflowExecToStateChangeLog(data);
        if (type === 'new') {
          polling.injectLog(entry);
        } else {
          polling.updateLog(entry);
        }
      }),
      ws.onLogsCleared(() => {
        polling.clearAll();
      }),
      ws.onReconnected(() => {
        fetchWithFilters();
      }),
    ];
    return () => unsubs.forEach(fn => fn());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ws]);

  // Derived: available devices and rooms from loaded logs
  const availableDevices = useMemo(() => {
    const devices = new Set<string>();
    for (const log of polling.logs) {
      if (log.deviceName && log.deviceName !== 'REST API') {
        devices.add(log.deviceName);
      }
    }
    return Array.from(devices).sort();
  }, [polling.logs]);

  const availableRooms = useMemo(() => {
    const rooms = new Set<string>();
    for (const log of polling.logs) {
      if (log.roomName) rooms.add(log.roomName);
    }
    return Array.from(rooms).sort();
  }, [polling.logs]);

  // Client-side filtering
  const filteredLogs = useMemo(() => {
    let logs = polling.logs;
    const search = debouncedSearch.toLowerCase();

    if (search) {
      logs = logs.filter(l =>
        l.deviceName.toLowerCase().includes(search) ||
        l.characteristicType.toLowerCase().includes(search) ||
        (l.serviceName && l.serviceName.toLowerCase().includes(search)) ||
        (l.errorDetails && l.errorDetails.toLowerCase().includes(search)) ||
        (l.requestBody && l.requestBody.toLowerCase().includes(search)) ||
        (l.responseBody && l.responseBody.toLowerCase().includes(search))
      );
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
      logs = logs.filter(l => selectedDevices.has(l.deviceName));
    }

    if (selectedRooms.size > 0) {
      logs = logs.filter(l => l.roomName && selectedRooms.has(l.roomName));
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

  function onCategoriesChange(cats: Set<string>) {
    setSelectedCategories(cats);
    // Re-fetch with new categories
    const params: { categories?: string[]; from?: string; to?: string } = {};
    if (cats.size > 0) params.categories = Array.from(cats);
    if (dateFrom) params.from = dateFrom;
    if (dateTo) params.to = dateTo;
    polling.loadFresh(params);
  }

  function onDateRangeChange(range: { from: string | null; to: string | null }) {
    setDateFrom(range.from);
    setDateTo(range.to);
    const params: { categories?: string[]; from?: string; to?: string } = {};
    if (selectedCategories.size > 0) params.categories = Array.from(selectedCategories);
    if (range.from) params.from = range.from;
    if (range.to) params.to = range.to;
    polling.loadFresh(params);
  }

  function onClearAll() {
    setSelectedCategories(new Set());
    setSelectedDevices(new Set());
    setSelectedRooms(new Set());
    setSearchText('');
    setDateFrom(null);
    setDateTo(null);
    polling.loadFresh({});
  }

  const [showClearConfirm, setShowClearConfirm] = useState(false);

  function onClearLogs() {
    setShowClearConfirm(true);
  }

  function confirmClearLogs() {
    api.clearLogs().then(() => {
      polling.clearAll();
    });
    setShowClearConfirm(false);
  }

  function loadMore() {
    polling.loadMore(buildQueryParams());
  }

  return (
    <div className="logs-page">
      {/* Page header */}
      <div className="page-header">
        <h1 className="page-title">Activity Log</h1>
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
          message="Logs will appear here when devices change state, workflows execute, or API calls are made."
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
              <button className="load-more-btn" onClick={loadMore} disabled={polling.isLoading}>
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
        message="This will permanently delete all activity logs and workflow execution history on the server."
        confirmLabel="Clear All"
        destructive
        onConfirm={confirmClearLogs}
        onCancel={() => setShowClearConfirm(false)}
      />
    </div>
  );
}
