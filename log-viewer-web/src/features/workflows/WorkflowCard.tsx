import { useMemo } from 'react';
import { Icon } from '@/components/Icon';
import type { Workflow, TriggerTypeKey } from '@/types/workflow-log';
import { TRIGGER_TYPE_LABELS, TRIGGER_TYPE_ICONS } from '@/types/workflow-log';
import { relativeTime } from '@/utils/date-utils';
import './WorkflowCard.css';

interface WorkflowCardProps {
  workflow: Workflow;
  index?: number;
  onToggleEnabled: (enabled: boolean) => void;
  onDelete: () => void;
  onClick: () => void;
}

export function WorkflowCard({ workflow, index = 0, onToggleEnabled, onDelete, onClick }: WorkflowCardProps) {
  const triggerType: TriggerTypeKey = workflow.triggers.length > 0
    ? (workflow.triggers[0]?.type ?? 'deviceStateChange')
    : 'deviceStateChange';

  const triggerIcon = TRIGGER_TYPE_ICONS[triggerType];
  const triggerLabel = TRIGGER_TYPE_LABELS[triggerType];

  const statusColor = useMemo(() => {
    if (!workflow.isEnabled) return 'var(--status-inactive)';
    if (workflow.metadata.consecutiveFailures > 0) return 'var(--status-error)';
    if (workflow.metadata.totalExecutions > 0) return 'var(--status-active)';
    return 'var(--tint-main)';
  }, [workflow.isEnabled, workflow.metadata.consecutiveFailures, workflow.metadata.totalExecutions]);

  const statusBg = `color-mix(in srgb, ${statusColor} 15%, transparent)`;
  const pillBg = `color-mix(in srgb, ${statusColor} 12%, transparent)`;

  return (
    <div
      className="wf-card animate-card-enter"
      style={{ animationDelay: `${index * 40}ms` }}
      onClick={onClick}
    >
      <div className="wf-trigger-icon" style={{ color: statusColor }}>
        <div className="wf-trigger-icon-bg" style={{ background: statusBg }}>
          <Icon name={triggerIcon} size={18} />
        </div>
      </div>

      <div className="wf-content">
        <div className="wf-name-row">
          <span className="wf-name">{workflow.name}</span>
          {!workflow.isEnabled && <span className="wf-disabled-badge">Disabled</span>}
        </div>

        <div className="wf-stats-row">
          <span className="wf-trigger-pill" style={{ color: statusColor, background: pillBg }}>
            {triggerLabel}
          </span>
          <span className="wf-stat">
            <Icon name="bolt-circle-fill" size={12} />
            {workflow.triggers.length}
          </span>
          <span className="wf-stat">
            <Icon name="rectangles-group" size={12} />
            {workflow.blocks.length}
          </span>
          {workflow.metadata.totalExecutions > 0 && (
            <span className="wf-stat">
              <Icon name="play-circle-fill" size={12} />
              {workflow.metadata.totalExecutions}
            </span>
          )}
        </div>

        {workflow.description && (
          <div className="wf-description">{workflow.description}</div>
        )}

        {workflow.metadata.lastTriggeredAt && (
          <div className="wf-last-triggered">
            Last triggered {relativeTime(workflow.metadata.lastTriggeredAt)}
          </div>
        )}
      </div>

      <div className="wf-right-actions" onClick={e => e.stopPropagation()}>
        <button className="wf-delete-btn" onClick={onDelete} title="Delete workflow">
          <Icon name="trash" size={15} />
        </button>
        <label className="wf-toggle-wrapper">
          <input
            type="checkbox"
            checked={workflow.isEnabled}
            onChange={e => onToggleEnabled(e.target.checked)}
          />
          <span className="wf-toggle-track" />
        </label>
      </div>
    </div>
  );
}
