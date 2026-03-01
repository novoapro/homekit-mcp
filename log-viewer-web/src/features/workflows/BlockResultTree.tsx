import { useState } from 'react';
import { Icon } from '@/components/Icon';
import type { BlockResult, ExecutionStatus } from '@/types/workflow-log';
import { formatBlockType, blockTypeIcon } from '@/utils/workflow-definition-utils';
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
  conditionNotMet: { name: 'slash-circle-fill', color: 'var(--status-warning)' },
  cancelled: { name: 'xmark-circle-fill', color: 'var(--status-inactive)' },
};

function computeDuration(block: BlockResult): string | null {
  if (!block.completedAt) return null;
  const ms = new Date(block.completedAt).getTime() - new Date(block.startedAt).getTime();
  if (ms < 1000) return `${ms}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  return `${Math.round(s / 60)}m ${Math.round(s % 60)}s`;
}

const CONTAINER_TYPES = new Set(['conditional', 'repeat', 'repeatWhile', 'group']);

interface BlockResultTreeProps {
  result: BlockResult;
  depth?: number;
}

export function BlockResultTree({ result, depth = 0 }: BlockResultTreeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const hasChildren = (result.nestedResults?.length ?? 0) > 0;
  const isContainer = CONTAINER_TYPES.has(result.blockType);
  const depthRange = Array.from({ length: depth }, (_, i) => i);
  const statusIcon = STATUS_ICONS[result.status] ?? STATUS_ICONS.skipped;
  const icon = blockTypeIcon(result.blockType, result.blockKind);
  const duration = computeDuration(result);

  return (
    <div className="tree-node">
      <div
        className={`tree-row ${hasChildren ? 'collapsible' : ''}`}
        onClick={() => hasChildren && setCollapsed(v => !v)}
      >
        {depthRange.map(i => (
          <div
            key={i}
            className="connector-line"
            style={{ backgroundColor: DEPTH_COLORS[i % DEPTH_COLORS.length] }}
          />
        ))}

        {hasChildren && (
          <span className={`tree-chevron ${collapsed ? 'collapsed' : ''}`}>
            <Icon name="chevron-down" size={12} />
          </span>
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
          </span>
          {result.detail && <span className="tree-detail">{result.detail}</span>}
          {result.errorMessage && <span className="tree-error">{result.errorMessage}</span>}
          {duration && <span className="tree-duration">{duration}</span>}
          {collapsed && hasChildren && (
            <span className="collapsed-hint">{result.nestedResults!.length} steps</span>
          )}
        </div>
      </div>

      {!collapsed && result.nestedResults?.map((sub) => (
        <BlockResultTree key={sub.id} result={sub} depth={depth + 1} />
      ))}
    </div>
  );
}
