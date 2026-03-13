import { useState } from 'react';
import { Icon } from '@/components/Icon';
import type { ConditionResult } from '@/types/workflow-log';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

interface ConditionResultTreeProps {
  result: ConditionResult;
  depth?: number;
  isLast?: boolean;
  isFirst?: boolean;
}

export function ConditionResultTree({ result, depth = 0, isLast = true, isFirst = true }: ConditionResultTreeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const hasChildren = (result.subResults?.length ?? 0) > 0;
  const lineX = depth * 20 + 25;

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

        <span className="tree-icon">
          <Icon
            name={result.passed ? 'checkmark-circle-fill' : 'xmark-circle-fill'}
            size={16}
            style={{ color: result.passed ? 'var(--status-active)' : 'var(--status-error)' }}
          />
        </span>

        {result.logicOperator && (
          <span className="logic-badge">{result.logicOperator.toUpperCase()}</span>
        )}

        <div className="tree-info">
          <span className="tree-name">
            {result.conditionDescription}
            {collapsed && hasChildren && (
              <span className="collapsed-hint">{result.subResults!.length} nested</span>
            )}
          </span>
        </div>
      </div>

      {!collapsed && result.subResults?.map((sub, i) => (
        <ConditionResultTree
          key={i}
          result={sub}
          depth={depth + 1}
          isFirst={i === 0}
          isLast={i === result.subResults!.length - 1}
        />
      ))}
    </div>
  );
}
