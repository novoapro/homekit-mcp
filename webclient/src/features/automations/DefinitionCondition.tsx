import { useState, useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type {
  AutomationConditionDef, DeviceStateConditionDef, TimeConditionDef,
  BlockResultConditionDef, EngineStateConditionDef,
  LogicAndConditionDef, LogicOrConditionDef, LogicNotConditionDef,
} from '@/types/automation-definition';
import { formatComparisonOperator, formatTimeConditionMode } from '@/utils/automation-definition-utils';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

interface DefinitionConditionProps {
  condition: AutomationConditionDef;
  depth?: number;
  isLast?: boolean;
  isFirst?: boolean;
}

function getChildConditions(condition: AutomationConditionDef): AutomationConditionDef[] {
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

export function DefinitionCondition({ condition, depth = 0, isLast = true, isFirst = true }: DefinitionConditionProps) {
  const registry = useDeviceRegistry();
  const [collapsed, setCollapsed] = useState(false);

  const children = getChildConditions(condition);
  const hasChildren = children.length > 0;
  const lineX = depth * 20 + 25;

  const displayName = useMemo(() => {
    switch (condition.type) {
      case 'deviceState': {
        const d = condition as DeviceStateConditionDef;
        return registry.lookupDevice(d.deviceId)?.name || d.deviceId;
      }
      case 'timeCondition': return 'Time Condition';
      case 'blockResult': return 'Block Result';
      case 'engineState': {
        const e = condition as EngineStateConditionDef;
        return e.variableRef?.name || 'Global Value';
      }
      case 'and': return 'All conditions (AND)';
      case 'or': return 'Any condition (OR)';
      case 'not': return 'NOT';
      default: return (condition as AutomationConditionDef).type;
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
      case 'blockResult': {
        const b = condition as BlockResultConditionDef;
        const scope = b.blockResultScope.scope === 'specific' ? `Block ${b.blockResultScope.blockId}` : 'Last block';
        return `${scope} is ${b.expectedStatus}`;
      }
      case 'engineState': {
        const e = condition as EngineStateConditionDef;
        return formatComparisonOperator(e.comparison);
      }
      default: return undefined;
    }
  }, [condition, registry]);

  const conditionIcon = isLogicOperator(condition.type) ? null : 'checkmark-circle';

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

        {isLogicOperator(condition.type) ? (
          <span className="logic-badge">{condition.type.toUpperCase()}</span>
        ) : (
          <span className="tree-icon" style={{ color: 'var(--tint-main)' }}>
            <Icon name={conditionIcon!} size={16} />
          </span>
        )}

        <div className="tree-info">
          <span className="tree-name">
            {displayName}
            {collapsed && hasChildren && (
              <span className="collapsed-hint">{children.length} nested</span>
            )}
            {collapsed && detailText && (
              <span className="tree-detail-inline">{detailText}</span>
            )}
          </span>
          {!collapsed && detailText && <span className="tree-detail">{detailText}</span>}
        </div>
      </div>

      {!collapsed && children.map((sub, i) => (
        <DefinitionCondition
          key={i}
          condition={sub}
          depth={depth + 1}
          isFirst={i === 0}
          isLast={i === children.length - 1}
        />
      ))}
    </div>
  );
}
