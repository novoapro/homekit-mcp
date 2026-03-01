import { useState, useMemo } from 'react';
import { Link } from 'react-router';
import { Icon } from '@/components/Icon';
import { CategoryIcon } from '@/components/CategoryIcon';
import { LogDetailPanel } from './LogDetailPanel';
import { BlockResultTree } from '@/features/workflows/BlockResultTree';
import { ConditionResultTree } from '@/features/workflows/ConditionResultTree';
import { characteristicDisplayName, formatCharacteristicValue } from '@/utils/characteristic-types';
import { formatTime } from '@/utils/date-utils';
import { LogCategory, CATEGORY_META } from '@/types/state-change-log';
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

function getServiceIcon(serviceName: string | undefined): string | null {
  const name = serviceName?.toLowerCase();
  if (!name) return null;

  if (name.includes('lightbulb') || name.includes('light')) return 'hk-lightbulb';
  if (name.includes('switch') || name.includes('button')) return 'hk-switch';
  if (name.includes('outlet') || name.includes('plug')) return 'hk-outlet';
  if (name.includes('fan')) return 'hk-fan';
  if (name.includes('thermostat') || name.includes('heater') || name.includes('cooler') || name.includes('ac')) return 'hk-thermostat';
  if (name.includes('garage')) return 'hk-garage';
  if (name.includes('lock')) return 'hk-lock';
  if (name.includes('window') || name.includes('blind') || name.includes('shade')) return 'hk-window-covering';
  if (name.includes('motion')) return 'hk-motion';
  if (name.includes('occupancy') || name.includes('presence')) return 'hk-occupancy';
  if (name.includes('temperature') || name.includes('temp')) return 'hk-temperature';
  if (name.includes('humidity')) return 'hk-humidity';
  if (name.includes('contact') || name.includes('door')) return 'hk-contact';
  if (name.includes('leak') || name.includes('water')) return 'hk-leak';
  if (name.includes('smoke') || name.includes('monoxide') || name.includes('dioxide')) return 'hk-smoke';
  if (name.includes('security') || name.includes('alarm')) return 'hk-security';
  if (name.includes('camera') || name.includes('video')) return 'hk-camera';
  if (name.includes('tv') || name.includes('television')) return 'hk-tv';
  if (name.includes('speaker') || name.includes('audio')) return 'hk-speaker';
  if (name.includes('valve') || name.includes('faucet') || name.includes('irrigation')) return 'hk-valve';
  if (name.includes('doorbell') || name.includes('bell')) return 'hk-doorbell';
  if (name.includes('purifier') || name.includes('air purifier')) return 'hk-air-purifier';
  if (name.includes('air quality') || name.includes('airquality') || name.includes('air_quality')) return 'hk-air-quality';
  if (name.includes('battery')) return 'hk-battery';
  if (name.includes('microphone') || name.includes('mic')) return 'hk-microphone';
  if (name.includes('filter')) return 'hk-filter';
  if (name.includes('robot') || name.includes('vacuum') || name.includes('roomba')) return 'hk-robot-vacuum';
  if (name.includes('curtain') || name.includes('drape')) return 'hk-curtain';

  return null;
}

const STATUS_COLOR_MAP: Record<ExecutionStatus, string> = {
  running: 'var(--status-running, var(--status-active))',
  success: 'var(--status-active)',
  failure: 'var(--status-error)',
  skipped: 'var(--text-secondary)',
  conditionNotMet: 'var(--status-warning)',
  cancelled: 'var(--status-warning)',
};

const STATUS_LABEL_MAP: Record<ExecutionStatus, string> = {
  running: 'Running',
  success: 'Success',
  failure: 'Failed',
  skipped: 'Skipped',
  conditionNotMet: 'Condition Not Met',
  cancelled: 'Cancelled',
};

function formatValue(val: unknown): string {
  if (val === undefined || val === null) return '\u2014';
  if (typeof val === 'boolean') return val ? 'on' : 'off';
  if (typeof val === 'number') return String(val);
  if (typeof val === 'string') return val;
  return JSON.stringify(val);
}

interface LogRowProps {
  log: StateChangeLog;
  index: number;
}

export function LogRow({ log, index }: LogRowProps) {
  const [expanded, setExpanded] = useState(false);

  const isExpandable = useMemo(() => {
    if (log.workflowExecution) return true;
    return !!(log.detailedRequestBody || log.requestBody || log.responseBody);
  }, [log]);

  const isError = useMemo(() => {
    const cat = log.category;
    if (cat === LogCategory.WorkflowError) {
      const status = log.workflowExecution?.status;
      if (status === 'success' || status === 'cancelled' || status === 'running') return false;
    }
    return cat === LogCategory.WebhookError ||
      cat === LogCategory.ServerError ||
      cat === LogCategory.WorkflowError ||
      cat === LogCategory.SceneError;
  }, [log]);

  const categoryColor = useMemo(() => {
    if (log.category === LogCategory.WorkflowError) {
      const status = log.workflowExecution?.status;
      if (status === 'success') return 'var(--status-active)';
      if (status === 'cancelled') return 'var(--status-warning)';
    }
    const meta = CATEGORY_META[log.category];
    return meta?.color || 'var(--tint-main)';
  }, [log]);

  const displayCharacteristicType = useMemo(() => characteristicDisplayName(log.characteristicType), [log.characteristicType]);

  const isBooleanChange = useMemo(() => {
    if (log.category !== LogCategory.StateChange) return false;
    return typeof log.newValue === 'boolean' || typeof log.oldValue === 'boolean';
  }, [log]);

  const timeStr = useMemo(() => formatTime(log.timestamp), [log.timestamp]);

  const formattedNewValue = useMemo(() => {
    if (log.category === LogCategory.StateChange) {
      return formatCharacteristicValue(log.newValue, log.characteristicType);
    }
    return formatValue(log.newValue);
  }, [log]);

  const showValueChange = useMemo(() => {
    return log.category === LogCategory.StateChange && (log.oldValue !== undefined || log.newValue !== undefined);
  }, [log]);

  const roomBadgeColors = useMemo((): [string, string] => {
    if (!log.roomName) return ['transparent', 'inherit'];
    return ROOM_COLORS[hashName(log.roomName)] ?? ['transparent', 'inherit'];
  }, [log.roomName]);

  const serviceBadgeColors = useMemo((): [string, string] => {
    if (!log.serviceName) return ['transparent', 'inherit'];
    return ROOM_COLORS[hashName(log.serviceName)] ?? ['transparent', 'inherit'];
  }, [log.serviceName]);

  const showServiceBadge = useMemo(() => {
    return log.serviceName &&
      log.category !== LogCategory.McpCall &&
      log.category !== LogCategory.RestCall;
  }, [log]);

  const serviceIcon = useMemo(() => getServiceIcon(log.serviceName), [log.serviceName]);

  const workflowStatus = log.workflowExecution?.status ?? null;
  const workflowStatusColor = workflowStatus ? (STATUS_COLOR_MAP[workflowStatus] || 'var(--text-secondary)') : 'var(--status-active)';
  const workflowStatusLabel = workflowStatus ? (STATUS_LABEL_MAP[workflowStatus] || workflowStatus) : '';

  const workflowTriggerDescription = useMemo(() => {
    const e = log.workflowExecution;
    if (!e) return log.requestBody ?? null;
    if (e.triggerEvent?.triggerDescription) return e.triggerEvent.triggerDescription;
    const te = e.triggerEvent;
    if (te?.deviceName) {
      const oldStr = te.oldValue !== undefined ? String(te.oldValue) : '?';
      const newStr = te.newValue !== undefined ? String(te.newValue) : '?';
      return `${te.deviceName}: ${oldStr} \u2192 ${newStr}`;
    }
    return null;
  }, [log]);

  const parsedResponseBody = useMemo(() => {
    const body = log.responseBody;
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
  }, [log.responseBody]);

  const backupSubtype = useMemo(() => {
    if (log.category !== LogCategory.BackupRestore) return '';
    return log.characteristicType
      .replace(/-/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }, [log]);

  const toggle = () => {
    if (isExpandable) setExpanded(prev => !prev);
  };

  const cardClasses = [
    'log-card',
    isExpandable ? 'expandable' : '',
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
            <span className="device-name">{log.deviceName}</span>
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
        ) : (showServiceBadge || log.roomName) ? (
          <div className="room-row">
            {log.roomName && (
              <span
                className="room-badge"
                style={{ background: roomBadgeColors[0], color: roomBadgeColors[1] }}
              >{log.roomName}</span>
            )}
            {showServiceBadge && (
              serviceIcon ? (
                <span
                  className="service-badge-icon"
                  style={{ color: categoryColor }}
                  title={log.serviceName}
                >
                  <Icon name={serviceIcon} size={20} />
                </span>
              ) : (
                <span
                  className="service-badge"
                  style={{ background: serviceBadgeColors[0], color: serviceBadgeColors[1] }}
                >{log.serviceName}</span>
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
              <Icon name="arrow-right" size={10} />
              <span className="new">{formattedNewValue}</span>
            </div>
          ) : null
        )}

        {log.category === LogCategory.McpCall && (
          <>
            <div className="api-content">
              <span className="method-badge mcp">MCP</span>
              {log.requestBody && <span className="api-text">{log.requestBody}</span>}
            </div>
            {parsedResponseBody && (
              <div className="api-result">
                {parsedResponseBody.code && (
                  <span className="result-status" style={{ color: parsedResponseBody.color }}>{parsedResponseBody.code} -&gt;</span>
                )}
                {parsedResponseBody.rest && (
                  <span className="result-text" style={{ color: parsedResponseBody.color }}>{parsedResponseBody.rest}</span>
                )}
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.RestCall && (
          <>
            <div className="api-content">
              <span className="method-badge rest">{log.characteristicType || 'REST'}</span>
            </div>
            {parsedResponseBody && (
              <div className="api-result">
                {parsedResponseBody.code && (
                  <span className="result-status" style={{ color: parsedResponseBody.color }}>{parsedResponseBody.code} -&gt;</span>
                )}
                {parsedResponseBody.rest && (
                  <span className="result-text" style={{ color: parsedResponseBody.color }}>{parsedResponseBody.rest}</span>
                )}
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.WebhookCall && (
          <>
            <div className="api-content">
              <span className="method-badge webhook">Webhook</span>
              {log.requestBody && <span className="api-text">{log.requestBody}</span>}
            </div>
            {parsedResponseBody && (
              <div className="api-result">
                {parsedResponseBody.code && (
                  <span className="result-status" style={{ color: parsedResponseBody.color }}>{parsedResponseBody.code} -&gt;</span>
                )}
                {parsedResponseBody.rest && (
                  <span className="result-text" style={{ color: parsedResponseBody.color }}>{parsedResponseBody.rest}</span>
                )}
              </div>
            )}
          </>
        )}

        {log.category === LogCategory.WebhookError && (
          <>
            {log.requestBody && (
              <div className="api-content">
                <span className="method-badge webhook">Webhook</span>
                <span className="api-text">{log.requestBody}</span>
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
            {log.workflowExecution?.errorMessage && (
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
            {log.workflowExecution?.errorMessage ? (
              <div className="error-banner-inline">
                <Icon name="exclamation-circle-fill" size={14} />
                <span>{log.workflowExecution.errorMessage}</span>
              </div>
            ) : isError ? (
              <div className="error-banner-inline">
                <Icon name="exclamation-circle-fill" size={14} />
                <span>{log.errorDetails || 'Workflow error'}</span>
              </div>
            ) : null}
          </>
        )}

        {log.category === LogCategory.SceneExecution && log.requestBody && (
          <div className="sub-content">{log.requestBody}</div>
        )}

        {log.category === LogCategory.SceneError && (
          <>
            {log.requestBody && (
              <div className="sub-content error-text">{log.requestBody}</div>
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
            {log.errorDetails && (
              <div className={`sub-content ${log.characteristicType === 'orphan-detection' ? 'error-text' : ''}`}>
                {log.errorDetails}
              </div>
            )}
          </>
        )}

        {/* Default: show responseBody if category not handled above */}
        {![
          LogCategory.StateChange, LogCategory.McpCall, LogCategory.RestCall,
          LogCategory.WebhookCall, LogCategory.WebhookError, LogCategory.ServerError,
          LogCategory.WorkflowExecution, LogCategory.WorkflowError,
          LogCategory.SceneExecution, LogCategory.SceneError, LogCategory.BackupRestore,
        ].includes(log.category) && log.responseBody && (
          <div className="sub-content">{log.responseBody}</div>
        )}

        {isExpandable && (
          <div className="interact-hint">
            <span className="hint-text">{expanded ? 'Collapse details' : 'View full details'}</span>
            <Icon name={expanded ? 'chevron-up' : 'chevron-down'} size={12} />
          </div>
        )}
      </div>

      {/* Expandable Detail Panel */}
      {expanded && isExpandable && (
        <div className="detail-inline">
          {log.workflowExecution ? (
            <div className="workflow-execution-detail" onClick={(e) => e.stopPropagation()}>
              {log.workflowExecution.conditionResults && log.workflowExecution.conditionResults.length > 0 && (
                <>
                  <div className="execution-section-label">Conditions</div>
                  <div className="execution-tree-content">
                    {log.workflowExecution.conditionResults.map((cond, i) => (
                      <ConditionResultTree key={i} result={cond} depth={0} />
                    ))}
                  </div>
                </>
              )}
              {log.workflowExecution.blockResults.length > 0 && (
                <>
                  <div className="execution-section-label">Steps ({log.workflowExecution.blockResults.length})</div>
                  <div className="execution-tree-content">
                    {log.workflowExecution.blockResults.map((block) => (
                      <BlockResultTree key={block.id} result={block} depth={0} />
                    ))}
                  </div>
                </>
              )}
              {log.workflowExecution.blockResults.length === 0 &&
                (!log.workflowExecution.conditionResults || log.workflowExecution.conditionResults.length === 0) && (
                  <span className="sub-content">No steps executed.</span>
                )}
              <Link
                className="view-detail-link"
                to={`/workflows/${log.workflowExecution.workflowId}/${log.workflowExecution.id}`}
                onClick={(e) => e.stopPropagation()}
              >
                <Icon name="arrow-right-circle" size={14} />
                View full execution details
              </Link>
            </div>
          ) : (
            <LogDetailPanel
              requestBody={log.detailedRequestBody || log.requestBody || ''}
              responseBody={log.responseBody || ''}
            />
          )}
        </div>
      )}
    </div>
  );
}
