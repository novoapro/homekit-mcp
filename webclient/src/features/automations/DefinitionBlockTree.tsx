import { useState, useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type { AutomationBlockDef } from '@/types/automation-definition';
import { formatBlockType, blockTypeIcon, isBlockingType, formatDurationShort, formatConditionSummary } from '@/utils/automation-definition-utils';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

const FLOW_CONTROL_TYPES = new Set(['conditional', 'repeat', 'repeatWhile', 'group']);

function iconColor(block: AutomationBlockDef): string {
  if (isBlockingType(block.type)) return 'var(--status-warning)';
  if (FLOW_CONTROL_TYPES.has(block.type)) return 'var(--tint-secondary)';
  return 'var(--tint-main)';
}

interface DefinitionBlockTreeProps {
  block: AutomationBlockDef;
  depth?: number;
  index?: number;
  isLast?: boolean;
  isFirst?: boolean;
}

export function DefinitionBlockTree({ block, depth = 0, index, isLast = true, isFirst = true }: DefinitionBlockTreeProps) {
  const registry = useDeviceRegistry();
  const [collapsed, setCollapsed] = useState(false);

  const nestedBlocks = useMemo(() => {
    const result: { label?: string; blocks: AutomationBlockDef[] }[] = [];
    if (block.type === 'conditional') {
      if (block.thenBlocks?.length) result.push({ label: 'Then', blocks: block.thenBlocks });
      if (block.elseBlocks?.length) result.push({ label: 'Else', blocks: block.elseBlocks });
    } else if (block.blocks?.length) {
      result.push({ blocks: block.blocks });
    }
    return result;
  }, [block]);

  const hasChildren = nestedBlocks.some(g => g.blocks.length > 0);
  const icon = blockTypeIcon(block.type, block.block);
  const color = iconColor(block);
  const lineX = depth * 20 + 25;

  const displayName = useMemo(() => {
    if (block.name) return block.name;
    switch (block.type) {
      case 'controlDevice': {
        const device = block.deviceId ? registry.lookupDevice(block.deviceId) : undefined;
        return device?.name || 'Control Device';
      }
      case 'timedControl': {
        return 'Timed Control';
      }
      case 'runScene': {
        const scene = block.sceneId ? registry.lookupScene(block.sceneId) : undefined;
        return scene?.name || 'Run Scene';
      }
      case 'conditional': {
        if (!block.condition) return 'If …';
        const summary = formatConditionSummary(
          block.condition,
          (id) => registry.lookupDevice(id),
          (dId, cId) => registry.lookupCharacteristic(dId, cId),
        );
        return summary ? `If ${summary}` : 'If …';
      }
      default: return formatBlockType(block.type);
    }
  }, [block, registry]);

  const detailText = useMemo(() => {
    switch (block.type) {
      case 'controlDevice': {
        if (!block.deviceId) return undefined;
        const device = registry.lookupDevice(block.deviceId);
        const char = block.characteristicId
          ? registry.lookupCharacteristic(block.deviceId, block.characteristicId)
          : undefined;
        const parts: string[] = [];
        if (device?.room) parts.push(device.room);
        if (char) {
          const valDisplay = block.valueRef?.name
            ? `${block.valueRef.name} (Global)`
            : String(block.value ?? '?');
          parts.push(`${char.name} → ${valDisplay}`);
        }
        return parts.join(' · ') || undefined;
      }
      case 'timedControl': {
        const count = block.changes?.length ?? 0;
        const secs = block.durationRef?.name
          ? `${block.durationRef.name} (Global)`
          : block.durationSeconds != null
            ? formatDurationShort(block.durationSeconds)
            : undefined;
        if (!secs) return `${count} change(s)`;
        return `${count} change(s) · hold ${secs}`;
      }
      case 'delay':
        return block.seconds ? formatDurationShort(block.seconds) : undefined;
      case 'webhook':
        return block.url ? `${block.method || 'POST'} ${block.url}` : undefined;
      case 'log':
        return block.message || undefined;
      case 'repeat':
        return block.count ? `${block.count} times` : undefined;
      case 'return':
        return block.outcome || undefined;
      case 'executeAutomation':
        return block.executionMode || undefined;
      case 'conditional':
        // condition info is already in displayName for conditionals
        return undefined;
      case 'waitForState':
      case 'repeatWhile':
        return block.condition
          ? formatConditionSummary(
              block.condition,
              (id) => registry.lookupDevice(id),
              (dId, cId) => registry.lookupCharacteristic(dId, cId),
            )
          : undefined;
      default:
        return undefined;
    }
  }, [block, registry]);

  const totalNested = nestedBlocks.reduce((sum, g) => sum + g.blocks.length, 0);

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

        <span className="tree-icon" style={{ color }}>
          <Icon name={icon} size={16} />
        </span>

        <div className="tree-info">
          <span className="tree-name">
            {index !== undefined && (
              <span style={{ color: 'var(--text-tertiary)', marginRight: 4, fontWeight: 'var(--font-weight-normal)' }}>
                {index + 1}.
              </span>
            )}
            {displayName}

            {collapsed && hasChildren && (
              <span className="collapsed-hint">{totalNested} blocks</span>
            )}
          </span>
          {detailText && <span className="tree-detail">{detailText}</span>}
        </div>
      </div>

      {!collapsed && nestedBlocks.map((group, gi) => {
        if (group.label) {
          // Render label as a proper tree node with a dot icon
          const labelDepth = depth + 1;
          return (
            <div key={gi} className="tree-node">
              <div className="tree-row" style={{ paddingLeft: labelDepth * 20 }}>
                <span className="tree-chevron-spacer" />
                <span className="tree-icon" style={{ color: group.label === 'Then' ? 'var(--status-active)' : 'var(--status-error)', width: 16, justifyContent: 'center', marginTop: 4 }}>
                  <Icon name="circle" size={8} />
                </span>
                <div className="tree-info">
                  <span className="tree-name" style={{
                    fontSize: 'var(--font-size-xs)',
                    fontWeight: 'var(--font-weight-bold)',
                    color: group.label === 'Then' ? 'var(--status-active)' : 'var(--status-error)',
                    textTransform: 'uppercase',
                    letterSpacing: '0.05em',
                  }}>
                    {group.label}
                  </span>
                </div>
              </div>

              {group.blocks.map((sub, i) => (
                <DefinitionBlockTree
                  key={sub.blockId}
                  block={sub}
                  depth={labelDepth + 1}
                  index={i}
                  isFirst={i === 0}
                  isLast={i === group.blocks.length - 1}
                />
              ))}
            </div>
          );
        }

        // Non-labeled groups (repeat, group, etc.) — render blocks directly
        return (
          <div key={gi}>
            {group.blocks.map((sub, i) => (
              <DefinitionBlockTree
                key={sub.blockId}
                block={sub}
                depth={depth + 1}
                index={i}
                isFirst={i === 0}
                isLast={i === group.blocks.length - 1}
              />
            ))}
          </div>
        );
      })}
    </div>
  );
}
