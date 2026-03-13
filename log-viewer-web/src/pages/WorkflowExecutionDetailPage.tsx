import { useState, useEffect, useCallback, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { Icon } from '@/components/Icon';
import { StatusBadge } from '@/components/StatusBadge';
import { ConditionResultTree } from '@/features/workflows/ConditionResultTree';
import { BlockResultTree } from '@/features/workflows/BlockResultTree';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from '@/contexts/WebSocketContext';
import type { WorkflowExecutionLog, ExecutionStatus } from '@/types/workflow-log';
import { formatDuration } from '@/utils/date-utils';
import { useTick } from '@/hooks/useTick';
import './WorkflowExecutionDetailPage.css';

const STATUS_COLORS: Record<ExecutionStatus, string> = {
  running: 'var(--status-running)',
  success: 'var(--status-active)',
  failure: 'var(--status-error)',
  skipped: 'var(--status-inactive)',
  conditionNotMet: 'var(--status-inactive)',
  cancelled: 'var(--status-inactive)',
};

const STATUS_ICONS: Record<ExecutionStatus, string> = {
  running: 'spinner',
  success: 'checkmark-circle-fill',
  failure: 'xmark-circle-fill',
  skipped: 'forward-circle-fill',
  conditionNotMet: 'forward-circle-fill',
  cancelled: 'slash-circle-fill',
};

function formatValue(val: unknown): string {
  if (val === undefined || val === null) return '—';
  if (typeof val === 'boolean') return val ? 'on' : 'off';
  return String(val);
}

export function WorkflowExecutionDetailPage() {
  const { workflowId, logId } = useParams<{ workflowId: string; logId: string }>();
  const navigate = useNavigate();
  const api = useApi();
  const ws = useWebSocket();

  const [log, setLog] = useState<WorkflowExecutionLog | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  useSetTopBar('Execution Detail', null, isLoading);

  const loadDetail = useCallback(async () => {
    if (!workflowId || !logId) return;
    setIsLoading(true);
    setError(null);
    try {
      const logs = await api.getWorkflowLogs(workflowId, 100);
      const found = logs.find(l => l.id === logId);
      setLog(found || null);
      if (!found) setError('Execution log not found');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load execution log');
    } finally {
      setIsLoading(false);
    }
  }, [api, workflowId, logId]);

  useEffect(() => {
    loadDetail();
  }, [loadDetail]);

  // Live updates via WebSocket
  useEffect(() => {
    const unsubLog = ws.onWorkflowLog((msg) => {
      if (msg.data.id !== logId) return;
      if (msg.type === 'updated') {
        setLog(current => {
          if (!current) return msg.data;
          // Don't overwrite terminal status with running
          if (current.status !== 'running' && msg.data.status === 'running') return current;
          return msg.data;
        });
      }
    });
    const unsubReconnected = ws.onReconnected(() => loadDetail());
    return () => { unsubLog(); unsubReconnected(); };
  }, [ws, logId, loadDetail]);

  const goBack = useCallback(() => {
    if (window.history.length > 1) {
      navigate(-1);
    } else {
      navigate('/workflows');
    }
  }, [navigate]);

  const statusColor = log ? (STATUS_COLORS[log.status] || 'var(--text-secondary)') : 'var(--text-secondary)';
  const statusIcon = log ? (STATUS_ICONS[log.status] || 'bolt-circle-fill') : 'bolt-circle-fill';

  const triggerValueChange = useMemo(() => {
    const te = log?.triggerEvent;
    if (!te) return null;
    if (te.oldValue === undefined && te.newValue === undefined) return null;
    return {
      charName: te.characteristicName || 'Value',
      newVal: formatValue(te.newValue),
    };
  }, [log]);

  const tick = useTick(log?.status === 'running');
  const duration = useMemo(() => {
    if (!log) return null;
    if (!log.completedAt && log.status !== 'running') return null;
    return formatDuration(log.triggeredAt, log.completedAt ?? undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [log, tick]);

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleString(undefined, {
      month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
  }

  const outcomeClass = log?.status === 'failure' ? 'error'
    : log?.status === 'success' ? 'success'
    : log?.status === 'cancelled' ? 'cancelled'
    : '';

  return (
    <div className="wfed-page">
      <button className="wfed-back-btn" onClick={goBack}>
        <span style={{ transform: 'rotate(90deg)', display: 'inline-flex' }}>
          <Icon name="chevron-down" size={14} />
        </span>
        <span>Back to Workflows</span>
      </button>

      {isLoading && (
        <div className="wfed-loading">
          <Icon name="spinner" size={24} className="animate-spin" />
          <span>Loading...</span>
        </div>
      )}

      {error && (
        <div className="wfed-error-banner animate-fade-in">
          <Icon name="exclamation-triangle" size={16} />
          <span>{error}</span>
        </div>
      )}

      {log && (
        <>
          {/* Header Section */}
          <div className="wfed-section wfed-header-section animate-fade-in">
            <div className="wfed-header-row">
              <span className="wfed-header-icon" style={{ color: statusColor }}>
                {log.status === 'running' ? (
                  <span className="animate-pulse-custom">
                    <Icon name={statusIcon} size={32} />
                  </span>
                ) : (
                  <Icon name={statusIcon} size={32} />
                )}
              </span>
              <div className="wfed-header-info">
                <h2 className="wfed-workflow-name">{log.workflowName}</h2>
                <div className="wfed-header-meta">
                  <StatusBadge status={log.status} />
                  {duration && <span className="wfed-duration">{duration}</span>}
                </div>
              </div>
            </div>
            <div className="wfed-timestamp">
              Triggered {formatDate(log.triggeredAt)}
              {log.completedAt && (
                <>
                  <span className="wfed-sep">&middot;</span>
                  Completed {formatDate(log.completedAt)}
                </>
              )}
            </div>
            {log.errorMessage && (
              <div className={`wfed-outcome ${outcomeClass}`}>
                <Icon
                  name={
                    log.status === 'success' ? 'checkmark-circle-fill'
                      : log.status === 'cancelled' ? 'xmark-circle-fill'
                      : 'exclamation-circle-fill'
                  }
                  size={14}
                />
                <span>{log.errorMessage}</span>
              </div>
            )}
          </div>

          {/* Trigger Section */}
          {log.triggerEvent && (
            <div className="wfed-section animate-fade-in">
              <h3 className="wfed-section-title">Trigger</h3>
              <div className="wfed-trigger-content">
                {log.triggerEvent.deviceName && (
                  <div className="wfed-trigger-row">
                    <Icon name="house" size={14} style={{ color: 'var(--text-tertiary)' }} />
                    <span>{log.triggerEvent.deviceName}</span>
                  </div>
                )}
                {log.triggerEvent.roomName && (
                  <div className="wfed-trigger-row">
                    <Icon name="map-pin" size={14} style={{ color: 'var(--text-tertiary)' }} />
                    <span>{log.triggerEvent.roomName}</span>
                  </div>
                )}
                {log.triggerEvent.serviceName && (
                  <div className="wfed-trigger-row">
                    <Icon name="cpu" size={14} style={{ color: 'var(--text-tertiary)' }} />
                    <span>{log.triggerEvent.serviceName}</span>
                  </div>
                )}
                {triggerValueChange && (
                  <div className="wfed-trigger-row wfed-value-change">
                    <span className="wfed-characteristic">{triggerValueChange.charName}</span>
                    <Icon name="arrow-right" size={12} />
                    <span className="wfed-new-val">{triggerValueChange.newVal}</span>
                  </div>
                )}
                {log.triggerEvent.triggerDescription && (
                  <div className="wfed-trigger-desc">{log.triggerEvent.triggerDescription}</div>
                )}
              </div>
            </div>
          )}

          {/* Conditions Section */}
          {log.conditionResults && log.conditionResults.length > 0 && (
            <div className="wfed-section animate-fade-in">
              <h3 className="wfed-section-title">Conditions</h3>
              <div className="wfed-tree-content">
                {log.conditionResults.map((condition, i) => (
                  <ConditionResultTree key={i} result={condition} depth={0} isFirst={i === 0} isLast={i === log.conditionResults!.length - 1} />
                ))}
              </div>
            </div>
          )}

          {/* Steps/Blocks Section */}
          {log.blockResults.length > 0 && (
            <div className="wfed-section animate-fade-in">
              <h3 className="wfed-section-title">
                Steps <span className="wfed-step-count">({log.blockResults.length})</span>
              </h3>
              <div className="wfed-tree-content">
                {log.blockResults.map((block, i) => (
                  <BlockResultTree key={block.id} result={block} depth={0} isFirst={i === 0} isLast={i === log.blockResults.length - 1} />
                ))}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
