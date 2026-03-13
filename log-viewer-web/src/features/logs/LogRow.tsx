import { memo, useState, useMemo } from 'react';
import { Link } from 'react-router';
import { Icon } from '@/components/Icon';
import { CategoryIcon } from '@/components/CategoryIcon';
import { LogDetailPanel } from './LogDetailPanel';
import { BlockResultTree } from '@/features/workflows/BlockResultTree';
import { ConditionResultTree } from '@/features/workflows/ConditionResultTree';
import { characteristicDisplayName, formatCharacteristicValue } from '@/utils/characteristic-types';
import { getServiceIcon } from '@/utils/service-icons';
import { formatTime } from '@/utils/date-utils';
import {
  LogCategory, CATEGORY_META,
  getLogDisplayName, getLogRoomName, getLogServiceName,
  getLogSummary, getLogResult,
  getLogDetailedRequest, getLogDetailedResponse, isLogExpandable,
} from '@/types/state-change-log';
import type { StateChangeLog } from '@/types/state-change-log';
import type { ExecutionStatus } from '@/types/workflow-log';
import './LogRow.css';

const ROOM_COLORS: [string, string][] = [
  ['#dbeafe', '#1e3a8a'],
  ['#dcfce7', '#14532d'],
  ['#fef9c3', '#713f12'],
  ['#ffe4e6', '#881337'],
  ['#f3e8ff', '#4c1d95'],
  ['#ffedd5', '#7c2d12'],
  ['#cffafe', '#164e63'],
  ['#fce7f3', '#831843'],
  ['#d1fae5', '#064e3b'],
  ['#e0e7ff', '#1e1b4b'],
  ['#fef3c7', '#78350f'],
  ['#f1f5f9', '#1e293b'],
];

function hashName(name: string): number {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }
  return hash % ROOM_COLORS.length;
}

const STATUS_COLOR_MAP: Record<ExecutionStatus, string> = {
  running: 'var(--status-running, var(--status-active))',
  success: 'var(--status-active)',
  failure: 'var(--status-error)',
  skipped: 'var(--text-secondary)',
  conditionNotMet: 'var(--text-secondary)',
  cancelled: 'var(--text-secondary)',
};

const STATUS_LABEL_MAP: Record<ExecutionStatus, string> = {
  running: 'Running',
  success: 'Success',
  failure: 'Failed',
  skipped: 'Skipped',
  conditionNotMet: 'Skipped',
  cancelled: 'Cancelled',
};

interface LogRowProps {
  log: StateChangeLog;
  index: number;
}

export const LogRow = memo(function LogRow({ log, index }: LogRowProps) {
  const [expanded, setExpanded] = useState(false);

  const expandable = useMemo(() => isLogExpandable(log), [log]);

  const isError = useMemo(() => {
    const cat = log.category;
    return cat === LogCategory.WebhookError ||
      cat === LogCategory.ServerError ||
      cat === LogCategory.WorkflowError ||
      cat === LogCategory.SceneError ||
      cat === LogCategory.AIInteractionError;
  }, [log]);

  const categoryColor = useMemo(() => {
    const meta = CATEGORY_META[log.category];
    return meta?.color || 'var(--tint-main)';
  }, [log]);

  const displayName = useMemo(() => getLogDisplayName(log), [log]);
  const roomName = useMemo(() => getLogRoomName(log), [log]);
  const serviceName = useMemo(() => getLogServiceName(log), [log]);
  const timeStr = useMemo(() => formatTime(log.timestamp), [log.timestamp]);

  const displayCharacteristicType = useMemo(() => {
    if (log.category === LogCategory.StateChange ||
        log.category === LogCategory.WebhookCall ||
        log.category === LogCategory.WebhookError) {
      return characteristicDisplayName(log.characteristicType);
    }
    return '';
  }, [log]);

  const isBooleanChange = useMemo(() => {
    if (log.category !== LogCategory.StateChange) return false;
    return typeof log.newValue === 'boolean' || typeof log.oldValue === 'boolean';
  }, [log]);

  const formattedNewValue = useMemo(() => {
    if (log.category === LogCategory.StateChange) {
      const val = formatCharacteristicValue(log.newValue, log.characteristicType);
      return log.unit && val !== '--' && val !== 'On' && val !== 'Off' ? `${val}${log.unit}` : val;
    }
    return '';
  }, [log]);

  const formattedOldValue = useMemo(() => {
    if (log.category === LogCategory.StateChange) {
      const val = formatCharacteristicValue(log.oldValue, log.characteristicType);
      return log.unit && val !== '--' && val !== 'On' && val !== 'Off' ? `${val}${log.unit}` : val;
    }
    return '';
  }, [log]);

  const showValueChange = useMemo(() => {
    return log.category === LogCategory.StateChange && (log.oldValue !== undefined || log.newValue !== undefined);
  }, [log]);

  const roomBadgeColors = useMemo((): [string, string] => {
    if (!roomName) return ['transparent', 'inherit'];
    return ROOM_COLORS[hashName(roomName)] ?? ['transparent', 'inherit'];
  }, [roomName]);

  const serviceBadgeColors = useMemo((): [string, string] => {
    if (!serviceName) return ['transparent', 'inherit'];
    return ROOM_COLORS[hashName(serviceName)] ?? ['transparent', 'inherit'];
  }, [serviceName]);

  const serviceIcon = useMemo(() => getServiceIcon(serviceName), [serviceName]);

  const workflowStatus = (log.category === LogCategory.WorkflowExecution || log.category === LogCategory.WorkflowError)
    ? log.workflowExecution.status
    : null;
  const workflowStatusColor = workflowStatus ? (STATUS_COLOR_MAP[workflowStatus] || 'var(--text-secondary)') : 'var(--status-active)';
  const workflowStatusLabel = workflowStatus ? (STATUS_LABEL_MAP[workflowStatus] || workflowStatus) : '';

  const workflowTriggerDescription = useMemo(() => {
    if (log.category !== LogCategory.WorkflowExecution && log.category !== LogCategory.WorkflowError) return null;
    const e = log.workflowExecution;
    if (e.triggerEvent?.triggerDescription) return e.triggerEvent.triggerDescription;
    const te = e.triggerEvent;
    if (te?.deviceName) {
      const oldStr = te.oldValue !== undefined ? String(te.oldValue) : '?';
      const newStr = te.newValue !== undefined ? String(te.newValue) : '?';
      return `${te.deviceName}: ${oldStr} \u2192 ${newStr}`;
    }
    return null;
  }, [log]);

  const parsedResult = useMemo(() => {
    const body = getLogResult(log);
    if (!body) return null;
    const match = body.match(/^(\d{3})(\s.*|$)/s);
    if (!match) return { code: null, color: '', rest: body };
    const code = parseInt(match[1]!, 10);
    const color = code < 300
      ? 'var(--status-active)'
      : code < 400
        ? 'var(--status-warning)'
        : 'var(--status-error)';
    return { code: match[1]!, color, rest: (match[2] ?? '').trim() };
  }, [log]);

  const backupSubtype = useMemo(() => {
    if (log.category !== LogCategory.BackupRestore) return '';
    return log.subtype
      .replace(/-/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }, [log]);

  const toggle = () => {
    if (expandable) setExpanded(prev => !prev);
  };

  const cardClasses = [
    'log-card',
    expandable ? 'expandable' : '',
    expanded ? 'expanded' : '',
    isError ? 'error' : '',
  ].filter(Boolean).join(' ');

  return (
    <div
      className={cardClasses}
      style={{ '--accent-color': categoryColor, animationDelay: `${index * 30}ms` } as React.CSSProperties}
      onClick={toggle}
    >
      <div className="content">
        <div className="header-row">
          <div className="header-left">
            <CategoryIcon category={log.category} size={24} />
            <span className="device-name">{displayName}</span>
          </div>
          <div className="header-end">
            <div className="header-right">
              <span className="time">{timeStr}</span>
            </div>
          </div>
        </div>

        {workflowStatus ? (
          <div className="status-row">
            <span
              className="status-badge"
              style={{ color: workflowStatusColor, backgroundColor: `${workflowStatusColor}22` }}
            >{workflowStatusLabel}</span>
          </div>
        ) : (serviceName || roomName) ? (
          <div className="room-row">
            {roomName && (
              <span
                className="room-badge"
                style={{ background: roomBadgeColors[0], color: roomBadgeColors[1] }}
              >{roomName}</span>
            )}
            {serviceName && (
              serviceIcon ? (
                <span
                  className="service-badge-icon"
                  style={{ color: categoryColor }}
                  title={serviceName}
                >
                  <Icon name={serviceIcon} size={20} />
                </span>
              ) : (
                <span
                  className="service-badge"
                  style={{ background: serviceBadgeColors[0], color: serviceBadgeColors[1] }}
                >{serviceName}</span>
              )
            )}
          </div>
        ) : null}

        {/* Category-specific content */}
        {log.category === LogCategory.StateChange && (
          isBooleanChange ? (
            <div className={`toggle-indicator ${log.newValue === true ? 'on' : 'off'}`}>
              <span className="toggle-dot" />
              <span className="characteristic">{displayCharacteristicType}</span>
              <span className="toggle-label">{log.newValue === true ? 'On' : 'Off'}</span>
            </div>
          ) : showValueChange ? (
            <div className="value-indicator">
              <span className="characteristic">{displayCharacteristicType}</span>
              <span className="old">{formattedOldValue}</span>
              <Icon name="arrow-right" size={10} />
              <span className="new">{formattedNewValue}</span>
            </div>
          ) : null
        )}

        {log.category === LogCategory.McpCall && (
          <>
            <div className="api-content">
              <span className="method-badge mcp">MCP</span>
              {log.summary && <span className="api-text">{log.summary}</span>}
            </div>
            {parsedResult && (
              <div className="api-result">
                {parsedResult.code && (
                  <span className="result-status" style={{ color: parsedResult.color }}>{parsedResult.code} -&gt;</span>
                )}
                {parsedResult.rest && (
                  <span className="result-text" style={{ color: parsedResult.color }}>{parsedResult.rest}</span>
                )}
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.RestCall && (
          <>
            <div className="api-content">
              <span className="method-badge rest">{log.method || 'REST'}</span>
            </div>
            {parsedResult && (
              <div className="api-result">
                {parsedResult.code && (
                  <span className="result-status" style={{ color: parsedResult.color }}>{parsedResult.code} -&gt;</span>
                )}
                {parsedResult.rest && (
                  <span className="result-text" style={{ color: parsedResult.color }}>{parsedResult.rest}</span>
                )}
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.WebhookCall && (
          <>
            <div className="api-content">
              <span className="method-badge webhook">Webhook</span>
              {log.summary && <span className="api-text">{log.summary}</span>}
            </div>
            {parsedResult && (
              <div className="api-result">
                {parsedResult.code && (
                  <span className="result-status" style={{ color: parsedResult.color }}>{parsedResult.code} -&gt;</span>
                )}
                {parsedResult.rest && (
                  <span className="result-text" style={{ color: parsedResult.color }}>{parsedResult.rest}</span>
                )}
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.WebhookError && (
          <>
            {log.summary && (
              <div className="api-content">
                <span className="method-badge webhook">Webhook</span>
                <span className="api-text">{log.summary}</span>
              </div>
            )}
            <div className="error-banner-inline">
              <Icon name="exclamation-circle-fill" size={14} />
              <span>{log.errorDetails || 'Webhook failed'}</span>
            </div>
          </>
        )}

        {log.category === LogCategory.ServerError && (
          <div className="error-banner-inline">
            <Icon name="exclamation-circle-fill" size={14} />
            <span>{log.errorDetails || 'Server error'}</span>
          </div>
        )}

        {log.category === LogCategory.WorkflowExecution && (
          <>
            {workflowTriggerDescription && (
              <div className="api-content">
                <span className="api-text workflow-trigger">{workflowTriggerDescription}</span>
              </div>
            )}
            {log.workflowExecution.errorMessage && (
              <div className="api-result">
                <span className="result-text" style={{ color: workflowStatusColor }}>{log.workflowExecution.errorMessage}</span>
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.WorkflowError && (
          <>
            {workflowTriggerDescription && (
              <div className="api-content">
                <span className="api-text workflow-trigger">{workflowTriggerDescription}</span>
              </div>
            )}
            {log.workflowExecution.errorMessage ? (
              <div className="error-banner-inline">
                <Icon name="exclamation-circle-fill" size={14} />
                <span>{log.workflowExecution.errorMessage}</span>
              </div>
            ) : isError ? (
              <div className="error-banner-inline">
                <Icon name="exclamation-circle-fill" size={14} />
                <span>Workflow error</span>
              </div>
            ) : null}
          </>
        )}

        {log.category === LogCategory.SceneExecution && log.summary && (
          <div className="sub-content">{log.summary}</div>
        )}

        {log.category === LogCategory.SceneError && (
          <>
            {log.summary && (
              <div className="sub-content error-text">{log.summary}</div>
            )}
            <div className="error-banner-inline">
              <Icon name="exclamation-circle-fill" size={14} />
              <span>{log.errorDetails || 'Scene error'}</span>
            </div>
          </>
        )}

        {log.category === LogCategory.BackupRestore && (
          <>
            <div className="api-content">
              <span className="method-badge backup">{backupSubtype}</span>
            </div>
            {log.summary && (
              <div className={`sub-content ${log.subtype === 'orphan-detection' ? 'error-text' : ''}`}>
                {log.summary}
              </div>
            )}
          </>
        )}

        {(log.category === LogCategory.AIInteraction || log.category === LogCategory.AIInteractionError) && (
          <>
            <div className="api-content">
              <span className="method-badge ai">{log.aiInteractionPayload.operation}</span>
              <span className="api-text">{log.aiInteractionPayload.provider} / {log.aiInteractionPayload.model}</span>
              <span className="api-text" style={{ marginLeft: 'auto', opacity: 0.6 }}>{log.aiInteractionPayload.durationSeconds.toFixed(1)}s</span>
            </div>
            {log.aiInteractionPayload.errorMessage && (
              <div className="error-banner-inline">
                <Icon name="exclamation-circle-fill" size={14} />
                <span>{log.aiInteractionPayload.errorMessage}</span>
              </div>
            )}
          </>
        )}

        {expandable && (
          <div className="interact-hint">
            <span className="hint-text">{expanded ? 'Collapse details' : 'View full details'}</span>
            <Icon name={expanded ? 'chevron-up' : 'chevron-down'} size={12} />
          </div>
        )}
      </div>

      {/* Expandable Detail Panel */}
      {expanded && expandable && (
        <div className="detail-inline">
          {(log.category === LogCategory.AIInteraction || log.category === LogCategory.AIInteractionError) ? (
            <div className="ai-interaction-detail" onClick={(e) => e.stopPropagation()}>
              <div className="execution-section-label">User Message</div>
              <pre className="ai-detail-pre">{log.aiInteractionPayload.userMessage}</pre>
              {log.aiInteractionPayload.rawResponse && (
                <>
                  <div className="execution-section-label">Raw Response</div>
                  <pre className="ai-detail-pre">{log.aiInteractionPayload.rawResponse}</pre>
                </>
              )}
              <div className="execution-section-label">System Prompt</div>
              <pre className="ai-detail-pre ai-system-prompt">{log.aiInteractionPayload.systemPrompt}</pre>
            </div>
          ) : (log.category === LogCategory.WorkflowExecution || log.category === LogCategory.WorkflowError) ? (
            <div className="workflow-execution-detail" onClick={(e) => e.stopPropagation()}>
              {log.workflowExecution.conditionResults && log.workflowExecution.conditionResults.length > 0 && (
                <>
                  <div className="execution-section-label">Conditions</div>
                  <div className="execution-tree-content">
                    {log.workflowExecution.conditionResults.map((cond, i) => (
                      <ConditionResultTree key={i} result={cond} depth={0} isFirst={i === 0} isLast={i === log.workflowExecution.conditionResults!.length - 1} />
                    ))}
                  </div>
                </>
              )}
              {log.workflowExecution.blockResults.length > 0 && (
                <>
                  <div className="execution-section-label">Steps ({log.workflowExecution.blockResults.length})</div>
                  <div className="execution-tree-content">
                    {log.workflowExecution.blockResults.map((block, i) => (
                      <BlockResultTree key={block.id} result={block} depth={0} isFirst={i === 0} isLast={i === log.workflowExecution.blockResults.length - 1} />
                    ))}
                  </div>
                </>
              )}
              {log.workflowExecution.blockResults.length === 0 &&
                (!log.workflowExecution.conditionResults || log.workflowExecution.conditionResults.length === 0) && (
                  <span className="sub-content">No steps executed.</span>
                )}
              <div className="workflow-detail-links">
                <Link
                  className="view-detail-link"
                  to={`/workflows/${log.workflowExecution.workflowId}/${log.workflowExecution.id}`}
                  onClick={(e) => e.stopPropagation()}
                >
                  <Icon name="arrow-right-circle" size={14} />
                  View full execution details
                </Link>
                <Link
                  className="view-detail-link"
                  to={`/workflows/${log.workflowExecution.workflowId}/definition`}
                  onClick={(e) => e.stopPropagation()}
                >
                  <Icon name="doc-text" size={14} />
                  View workflow definition
                </Link>
              </div>
            </div>
          ) : (
            <LogDetailPanel
              requestBody={getLogDetailedRequest(log) || getLogSummary(log) || ''}
              responseBody={getLogDetailedResponse(log) || getLogResult(log) || ''}
            />
          )}
        </div>
      )}
    </div>
  );
});
