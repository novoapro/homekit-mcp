import { useState, useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type {
  WorkflowConditionDef, DeviceStateConditionDef, TimeConditionDef,
  SceneActiveConditionDef, BlockResultConditionDef,
  LogicAndConditionDef, LogicOrConditionDef, LogicNotConditionDef,
} from '@/types/workflow-definition';
import { formatComparisonOperator, formatTimeConditionMode } from '@/utils/workflow-definition-utils';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

interface DefinitionConditionProps {
  condition: WorkflowConditionDef;
  depth?: number;
}

function getChildConditions(condition: WorkflowConditionDef): WorkflowConditionDef[] {
  switch (condition.type) {
    case 'and': return (condition as LogicAndConditionDef).conditions;
    case 'or': return (condition as LogicOrConditionDef).conditions;
    case 'not': return [(condition as LogicNotConditionDef).condition];
    default: return [];
  }
}

function isLogicOperator(type: string): boolean {
  return type === 'and' || type === 'or' || type === 'not';
}

export function DefinitionCondition({ condition, depth = 0 }: DefinitionConditionProps) {
  const registry = useDeviceRegistry();
  const [collapsed, setCollapsed] = useState(false);

  const children = getChildConditions(condition);
  const hasChildren = children.length > 0;
  const depthRange = Array.from({ length: depth }, (_, i) => i);

  const displayName = useMemo(() => {
    switch (condition.type) {
      case 'deviceState': {
        const d = condition as DeviceStateConditionDef;
        return registry.lookupDevice(d.deviceId)?.name || d.deviceId;
      }
      case 'timeCondition': return 'Time Condition';
      case 'sceneActive': {
        const s = condition as SceneActiveConditionDef;
        const scene = registry.lookupScene(s.sceneId);
        return scene?.name || s.sceneId;
      }
      case 'blockResult': return 'Block Result';
      case 'and': return 'All conditions (AND)';
      case 'or': return 'Any condition (OR)';
      case 'not': return 'NOT';
      default: return (condition as WorkflowConditionDef).type;
    }
  }, [condition, registry]);

  const detailText = useMemo(() => {
    switch (condition.type) {
      case 'deviceState': {
        const d = condition as DeviceStateConditionDef;
        const device = registry.lookupDevice(d.deviceId);
        const char = registry.lookupCharacteristic(d.deviceId, d.characteristicId);
        const charLabel = char?.name || d.characteristicId;
        const parts: string[] = [];
        if (device?.room) parts.push(device.room);
        parts.push(`${charLabel} ${formatComparisonOperator(d.comparison)}`);
        return parts.join(' · ');
      }
      case 'timeCondition': {
        const t = condition as TimeConditionDef;
        return formatTimeConditionMode(t.mode, t.startTime, t.endTime);
      }
      case 'sceneActive': {
        const s = condition as SceneActiveConditionDef;
        return s.isActive ? 'Is active' : 'Is not active';
      }
      case 'blockResult': {
        const b = condition as BlockResultConditionDef;
        const scope = b.blockResultScope.scope === 'specific' ? `Block ${b.blockResultScope.blockId}` : 'Last block';
        return `${scope} is ${b.expectedStatus}`;
      }
      default: return undefined;
    }
  }, [condition, registry]);

  const conditionIcon = isLogicOperator(condition.type) ? null : 'checkmark-circle';

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

        {isLogicOperator(condition.type) ? (
          <span className="logic-badge">{condition.type.toUpperCase()}</span>
        ) : (
          <span className="tree-icon" style={{ color: 'var(--tint-main)' }}>
            <Icon name={conditionIcon!} size={16} />
          </span>
        )}

        <div className="tree-info">
          <span className="tree-name">{displayName}</span>
          {detailText && <span className="tree-detail">{detailText}</span>}
          {collapsed && hasChildren && (
            <span className="collapsed-hint">{children.length} nested</span>
          )}
        </div>
      </div>

      {!collapsed && children.map((sub, i) => (
        <DefinitionCondition key={i} condition={sub} depth={depth + 1} />
      ))}
    </div>
  );
}
