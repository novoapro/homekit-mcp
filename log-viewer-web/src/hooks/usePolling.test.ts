import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { usePolling } from './usePolling';
import type { StateChangeLog } from '@/types/state-change-log';
import { LogCategory } from '@/types/state-change-log';
import type { WorkflowExecutionLog, ExecutionStatus } from '@/types/workflow-log';

/** Create a minimal valid WorkflowExecutionLog. */
function makeWorkflowExec(status: ExecutionStatus = 'success'): WorkflowExecutionLog {
  return {
    id: 'exec-1',
    workflowId: 'wf-1',
    workflowName: 'Test Workflow',
    triggeredAt: new Date().toISOString(),
    blockResults: [],
    status,
  };
}

/** Create a minimal valid StateChangeLog for use in tests. */
function makeLog(overrides: Partial<StateChangeLog> & { id: string }): StateChangeLog {
  return {
    deviceId: 'device-1',
    deviceName: 'Test Device',
    characteristicType: 'On',
    category: LogCategory.StateChange,
    timestamp: new Date().toISOString(),
    ...overrides,
  };
}

// Mock the useApi hook
vi.mock('./useApi', () => ({
  useApi: vi.fn(),
}));

// Mock the ConfigContext
vi.mock('@/contexts/ConfigContext', () => ({
  useConfig: vi.fn(),
}));

import { useApi } from './useApi';
import { useConfig } from '@/contexts/ConfigContext';

describe('usePolling', () => {
  let mockApi: any;
  let mockConfig: any;

  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: false });
    vi.clearAllMocks();

    mockApi = {
      getLogs: vi.fn().mockResolvedValue({
        logs: [makeLog({ id: '1', workflowExecution: makeWorkflowExec('success') })],
        total: 1,
      }),
    };

    mockConfig = {
      pollingInterval: 5,
    };

    (useApi as any).mockReturnValue(mockApi);
    (useConfig as any).mockReturnValue({ config: mockConfig });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('initializes with default state', () => {
    const { result } = renderHook(() => usePolling());

    expect(result.current.logs).toEqual([]);
    expect(result.current.totalCount).toBe(0);
    expect(result.current.isLoading).toBe(false);
    expect(result.current.isPolling).toBe(false);
    expect(result.current.lastPollTime).toBeNull();
    expect(result.current.error).toBeNull();
  });

  it('provides polling control methods', () => {
    const { result } = renderHook(() => usePolling());

    expect(typeof result.current.startPolling).toBe('function');
    expect(typeof result.current.stopPolling).toBe('function');
    expect(typeof result.current.loadFresh).toBe('function');
    expect(typeof result.current.loadMore).toBe('function');
    expect(typeof result.current.injectLog).toBe('function');
    expect(typeof result.current.updateLog).toBe('function');
    expect(typeof result.current.clearAll).toBe('function');
    expect(typeof result.current.refresh).toBe('function');
  });

  it('loadFresh fetches logs with provided parameters', async () => {
    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh({ device_name: 'Kitchen Light' });
    });

    expect(mockApi.getLogs).toHaveBeenCalledWith(
      expect.objectContaining({
        device_name: 'Kitchen Light',
        limit: 200,
      }),
    );

    expect(result.current.logs).toHaveLength(1);
  });

  it('loadMore appends logs without replacing existing ones', async () => {
    mockApi.getLogs.mockResolvedValueOnce({
      logs: [
        makeLog({ id: '1', timestamp: '2024-01-01T00:00:00Z', workflowExecution: makeWorkflowExec('success') }),
      ],
      total: 3,
    });

    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    expect(result.current.logs).toHaveLength(1);

    mockApi.getLogs.mockResolvedValueOnce({
      logs: [
        makeLog({ id: '2', timestamp: '2024-01-01T00:01:00Z', workflowExecution: makeWorkflowExec('running') }),
      ],
      total: 3,
    });

    await act(async () => {
      await result.current.loadMore();
    });

    expect(result.current.logs).toHaveLength(2);
  });

  it('injectLog adds new log to the beginning', () => {
    const { result } = renderHook(() => usePolling());

    const log = makeLog({ id: 'new-log', workflowExecution: makeWorkflowExec('success') });

    act(() => {
      result.current.injectLog(log);
    });

    expect(result.current.logs[0]).toEqual(log);
    expect(result.current.totalCount).toBe(1);
  });

  it('does not inject duplicate logs', () => {
    const { result } = renderHook(() => usePolling());

    const log = makeLog({ id: 'duplicate-id', workflowExecution: makeWorkflowExec('success') });

    act(() => {
      result.current.injectLog(log);
      result.current.injectLog(log);
    });

    expect(result.current.logs).toHaveLength(1);
    expect(result.current.totalCount).toBe(1);
  });

  it('updateLog modifies existing log in place', () => {
    const log = makeLog({ id: 'log-1', workflowExecution: makeWorkflowExec('running') });

    const { result } = renderHook(() => usePolling());

    act(() => {
      result.current.injectLog(log);
    });

    const updatedLog = makeLog({ id: 'log-1', workflowExecution: makeWorkflowExec('success') });

    act(() => {
      result.current.updateLog(updatedLog);
    });

    expect(result.current.logs[0]?.workflowExecution?.status).toBe('success');
    expect(result.current.logs).toHaveLength(1);
  });

  it('does not overwrite terminal status with running status', () => {
    const log = makeLog({ id: 'log-1', workflowExecution: makeWorkflowExec('success') });

    const { result } = renderHook(() => usePolling());

    act(() => {
      result.current.injectLog(log);
    });

    const staleUpdate = makeLog({ id: 'log-1', workflowExecution: makeWorkflowExec('running') });

    act(() => {
      result.current.updateLog(staleUpdate);
    });

    expect(result.current.logs[0]?.workflowExecution?.status).toBe('success');
  });

  it('clearAll removes all logs', async () => {
    mockApi.getLogs.mockResolvedValue({
      logs: [
        makeLog({ id: '1', timestamp: '2024-01-01T00:00:00Z', workflowExecution: makeWorkflowExec('success') }),
      ],
      total: 1,
    });

    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    expect(result.current.logs).toHaveLength(1);

    act(() => {
      result.current.clearAll();
    });

    expect(result.current.logs).toHaveLength(0);
    expect(result.current.totalCount).toBe(0);
  });

  it('handles API errors gracefully in loadFresh', async () => {
    const errorMsg = 'Network error';
    mockApi.getLogs.mockRejectedValueOnce(new Error(errorMsg));

    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    expect(result.current.error).toBe(errorMsg);
    expect(result.current.isLoading).toBe(false);
  });

  it('tracks latest timestamp for delta polling', async () => {
    mockApi.getLogs.mockResolvedValue({
      logs: [
        makeLog({ id: '1', timestamp: '2024-01-01T00:00:10Z', workflowExecution: makeWorkflowExec('success') }),
      ],
      total: 1,
    });

    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    // Reset to check the subsequent call includes the timestamp
    mockApi.getLogs.mockClear();

    await act(async () => {
      result.current.refresh();
    });

    // Should include 'from' parameter with latest timestamp
    expect(mockApi.getLogs).toHaveBeenCalledWith(
      expect.objectContaining({
        from: '2024-01-01T00:00:10Z',
      }),
    );
  });

  it('handles error in loadMore', async () => {
    mockApi.getLogs.mockResolvedValueOnce({
      logs: [makeLog({ id: '1', timestamp: '2024-01-01T00:00:00Z', workflowExecution: makeWorkflowExec('success') })],
      total: 2,
    });

    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    mockApi.getLogs.mockRejectedValueOnce(new Error('Load more failed'));

    await act(async () => {
      await result.current.loadMore();
    });

    expect(result.current.error).toBe('Load more failed');
  });

  it('sets logs from API response', async () => {
    mockApi.getLogs.mockResolvedValue({
      logs: [
        makeLog({ id: '1', timestamp: '2024-01-01T00:00:00Z', workflowExecution: makeWorkflowExec('success') }),
        makeLog({ id: '2', timestamp: '2024-01-01T00:01:00Z', workflowExecution: makeWorkflowExec('running') }),
      ],
      total: 2,
    });

    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    expect(result.current.logs).toHaveLength(2);
    expect(result.current.totalCount).toBe(2);
  });

  it('refresh calls fetchLogs', async () => {
    const { result } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh({ device_name: 'Light' });
    });

    mockApi.getLogs.mockClear();

    await act(async () => {
      result.current.refresh();
    });

    expect(mockApi.getLogs).toHaveBeenCalled();
  });

  it('cleans up on unmount', async () => {
    const { result, unmount } = renderHook(() => usePolling());

    await act(async () => {
      await result.current.loadFresh();
    });

    expect(() => {
      unmount();
    }).not.toThrow();
  });
});
