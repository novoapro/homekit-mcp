import { useState } from 'react';
import { Icon } from '@/components/Icon';
import type { BlockResult, ExecutionStatus } from '@/types/workflow-log';
import { formatBlockType, blockTypeIcon } from '@/utils/workflow-definition-utils';
import { formatDuration } from '@/utils/date-utils';
import { useTick } from '@/hooks/useTick';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

const STATUS_ICONS: Record<ExecutionStatus, { name: string; color: string }> = {
  success: { name: 'checkmark-circle-fill', color: 'var(--status-active)' },
  failure: { name: 'xmark-circle-fill', color: 'var(--status-error)' },
  running: { name: 'refresh-circle-fill', color: 'var(--status-running)' },
  skipped: { name: 'forward-circle-fill', color: 'var(--status-inactive)' },
  conditionNotMet: { name: 'forward-circle-fill', color: 'var(--status-inactive)' },
  cancelled: { name: 'xmark-circle-fill', color: 'var(--status-inactive)' },
};

const CONTAINER_TYPES = new Set(['conditional', 'repeat', 'repeatWhile', 'group']);

interface BlockResultTreeProps {
  result: BlockResult;
  depth?: number;
  isLast?: boolean;
  isFirst?: boolean;
}

export function BlockResultTree({ result, depth = 0, isLast = true, isFirst = true }: BlockResultTreeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const isRunning = result.status === 'running';
  const tick = useTick(isRunning);
  const hasChildren = (result.nestedResults?.length ?? 0) > 0;
  const isContainer = CONTAINER_TYPES.has(result.blockType);
  const statusIcon = STATUS_ICONS[result.status] ?? STATUS_ICONS.skipped;
  const icon = blockTypeIcon(result.blockType, result.blockKind);
  const lineX = depth * 20 + 25;

  void tick;
  const duration = (result.completedAt || isRunning)
    ? formatDuration(result.startedAt, result.completedAt ?? undefined)
    : null;

  return (
    <div className="tree-node">
      {!isFirst && (
        <div
          className="tree-vline tree-vline--above"
          style={{ left: `${lineX}px`, '--line-color': DEPTH_COLORS[depth % DEPTH_COLORS.length] } as React.CSSProperties}
        />
      )}
      {!isLast && (
        <div
          className="tree-vline tree-vline--below"
          style={{ left: `${lineX}px`, '--line-color': DEPTH_COLORS[depth % DEPTH_COLORS.length] } as React.CSSProperties}
        />
      )}

      <div
        className={`tree-row ${hasChildren ? 'collapsible' : ''}`}
        style={{ paddingLeft: depth * 20 }}
        onClick={() => hasChildren && setCollapsed(v => !v)}
      >
        {hasChildren ? (
          <span className={`tree-chevron ${collapsed ? 'collapsed' : ''}`}>
            <Icon name="chevron-down" size={12} />
          </span>
        ) : (
          <span className="tree-chevron-spacer" />
        )}

        <span className="tree-icon" style={{ color: statusIcon.color }}>
          <Icon name={statusIcon.name} size={16} />
        </span>

        {isContainer && (
          <span className="tree-icon" style={{ color: 'var(--text-tertiary)' }}>
            <Icon name={icon} size={14} />
          </span>
        )}

        <div className="tree-info">
          <span className="tree-name">
            {result.blockName || formatBlockType(result.blockType)}
            {collapsed && hasChildren && (
              <span className="collapsed-hint">{result.nestedResults!.length} steps</span>
            )}
            {collapsed && result.detail && (
              <span className="tree-detail-inline">{result.detail}</span>
            )}
          </span>
          {!collapsed && result.detail && <span className="tree-detail">{result.detail}</span>}
          {result.errorMessage && <span className="tree-error">{result.errorMessage}</span>}
          {duration && <span className="tree-duration">{duration}</span>}
        </div>
      </div>

      {!collapsed && result.nestedResults?.map((sub, i) => (
        <BlockResultTree
          key={sub.id}
          result={sub}
          depth={depth + 1}
          isFirst={i === 0}
          isLast={i === result.nestedResults!.length - 1}
        />
      ))}
    </div>
  );
}
