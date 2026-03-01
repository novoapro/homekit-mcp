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
}

export function ConditionResultTree({ result, depth = 0 }: ConditionResultTreeProps) {
  const [collapsed, setCollapsed] = useState(false);
  const hasChildren = (result.subResults?.length ?? 0) > 0;

  const depthRange = Array.from({ length: depth }, (_, i) => i);

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
          <span className="tree-name">{result.conditionDescription}</span>
          {collapsed && hasChildren && (
            <span className="collapsed-hint">{result.subResults!.length} nested</span>
          )}
        </div>
      </div>

      {!collapsed && result.subResults?.map((sub, i) => (
        <ConditionResultTree key={i} result={sub} depth={depth + 1} />
      ))}
    </div>
  );
}
