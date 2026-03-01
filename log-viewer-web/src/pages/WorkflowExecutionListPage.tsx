import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { WorkflowLogRow } from '@/features/workflows/WorkflowLogRow';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from '@/contexts/WebSocketContext';
import type { WorkflowExecutionLog } from '@/types/workflow-log';
import './WorkflowExecutionListPage.css';

export function WorkflowExecutionListPage() {
  const { workflowId } = useParams<{ workflowId: string }>();
  const navigate = useNavigate();
  const api = useApi();
  const ws = useWebSocket();

  const [logs, setLogs] = useState<WorkflowExecutionLog[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadLogs = useCallback(async () => {
    if (!workflowId) return;
    setIsLoading(true);
    setError(null);
    try {
      const result = await api.getWorkflowLogs(workflowId, 100);
      setLogs(result);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load execution logs');
    } finally {
      setIsLoading(false);
    }
  }, [api, workflowId]);

  useEffect(() => {
    loadLogs();
  }, [loadLogs]);

  // WebSocket: real-time workflow log updates
  useEffect(() => {
    const unsubLog = ws.onWorkflowLog((msg) => {
      if (msg.data.workflowId !== workflowId) return;

      setLogs(current => {
        if (msg.type === 'new') {
          if (current.some(l => l.id === msg.data.id)) return current;
          return [msg.data, ...current];
        } else if (msg.type === 'updated') {
          const idx = current.findIndex(l => l.id === msg.data.id);
          if (idx < 0) return current;
          // Don't overwrite a completed status with running
          if (current[idx]!.status !== 'running' && msg.data.status === 'running') return current;
          const updated = [...current];
          updated[idx] = msg.data;
          return updated;
        }
        return current;
      });
    });

    const unsubCleared = ws.onLogsCleared(() => {
      setLogs([]);
    });

    return () => { unsubLog(); unsubCleared(); };
  }, [ws, workflowId]);

  const goBack = useCallback(() => {
    if (window.history.length > 1) {
      navigate(-1);
    } else {
      navigate(`/workflows/${workflowId}/definition`);
    }
  }, [navigate, workflowId]);

  return (
    <div className="wfel-page">
      <button className="wfel-back-btn" onClick={goBack}>
        <span style={{ transform: 'rotate(90deg)', display: 'inline-flex' }}>
          <Icon name="chevron-down" size={14} />
        </span>
        <span>Back to Workflows</span>
      </button>

      <div className="wfel-page-header">
        <h1 className="wfel-page-title">Execution Logs</h1>
        {isLoading && <span className="wfel-loading-dot" />}
      </div>

      {error && (
        <div className="wfel-error-banner animate-fade-in">
          <Icon name="exclamation-triangle" size={16} />
          <span>{error}</span>
        </div>
      )}

      {isLoading && logs.length === 0 && (
        <div className="wfel-skeleton-list">
          {Array.from({ length: 10 }, (_, i) => (
            <div key={i} className="wfel-skeleton-card skeleton" style={{ animationDelay: `${i * 100}ms` }} />
          ))}
        </div>
      )}

      {!isLoading && logs.length === 0 && !error && (
        <EmptyState
          icon="bolt-circle-fill"
          title="No executions"
          message="This workflow hasn't been executed yet. Trigger it and execution logs will appear here."
        />
      )}

      {logs.length > 0 && (
        <div className="wfel-log-list">
          {logs.map((log, i) => (
            <WorkflowLogRow
              key={log.id}
              log={log}
              index={i}
              onClick={() => navigate(`/workflows/${workflowId}/${log.id}`)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
