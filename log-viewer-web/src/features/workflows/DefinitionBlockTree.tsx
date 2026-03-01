import { useState, useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type { WorkflowBlockDef } from '@/types/workflow-definition';
import { formatBlockType, blockTypeIcon, isBlockingType, formatDurationShort } from '@/utils/workflow-definition-utils';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

const FLOW_CONTROL_TYPES = new Set(['conditional', 'repeat', 'repeatWhile', 'group']);

function iconColor(block: WorkflowBlockDef): string {
  if (isBlockingType(block.type)) return 'var(--status-warning)';
  if (FLOW_CONTROL_TYPES.has(block.type)) return 'var(--tint-secondary)';
  return 'var(--tint-main)';
}

interface DefinitionBlockTreeProps {
  block: WorkflowBlockDef;
  depth?: number;
  index?: number;
}

export function DefinitionBlockTree({ block, depth = 0, index }: DefinitionBlockTreeProps) {
  const registry = useDeviceRegistry();
  const [collapsed, setCollapsed] = useState(false);

  const nestedBlocks = useMemo(() => {
    const result: { label?: string; blocks: WorkflowBlockDef[] }[] = [];
    if (block.type === 'conditional') {
      if (block.thenBlocks?.length) result.push({ label: 'Then', blocks: block.thenBlocks });
      if (block.elseBlocks?.length) result.push({ label: 'Else', blocks: block.elseBlocks });
    } else if (block.blocks?.length) {
      result.push({ blocks: block.blocks });
    }
    return result;
  }, [block]);

  const hasChildren = nestedBlocks.some(g => g.blocks.length > 0);
  const depthRange = Array.from({ length: depth }, (_, i) => i);
  const icon = blockTypeIcon(block.type, block.block);
  const color = iconColor(block);

  const displayName = useMemo(() => {
    if (block.name) return block.name;
    switch (block.type) {
      case 'controlDevice': {
        const device = block.deviceId ? registry.lookupDevice(block.deviceId) : undefined;
        return device?.name || 'Control Device';
      }
      case 'runScene': {
        const scene = block.sceneId ? registry.lookupScene(block.sceneId) : undefined;
        return scene?.name || 'Run Scene';
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
        if (char) parts.push(`${char.name} → ${block.value ?? '?'}`);
        return parts.join(' · ') || undefined;
      }
      case 'delay':
        return block.seconds ? formatDurationShort(block.seconds) : undefined;
      case 'webhook':
        return block.url ? `${block.method || 'POST'} ${block.url}` : undefined;
      case 'log':
        return block.message || undefined;
      case 'repeat':
        return block.count ? `${block.count} times` : undefined;
      case 'stop':
      case 'return':
        return block.outcome || undefined;
      case 'executeWorkflow':
        return block.executionMode || undefined;
      default:
        return undefined;
    }
  }, [block, registry]);

  const totalNested = nestedBlocks.reduce((sum, g) => sum + g.blocks.length, 0);

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

        <span className="tree-icon" style={{ color }}>
          <Icon name={icon} size={16} />
        </span>

        {isBlockingType(block.type) && (
          <span className="blocking-badge">Blocking</span>
        )}

        <div className="tree-info">
          <span className="tree-name">
            {index !== undefined && (
              <span style={{ color: 'var(--text-tertiary)', marginRight: 4, fontWeight: 'var(--font-weight-normal)' }}>
                {index + 1}.
              </span>
            )}
            {displayName}
          </span>
          {detailText && <span className="tree-detail">{detailText}</span>}
          {collapsed && hasChildren && (
            <span className="collapsed-hint">{totalNested} blocks</span>
          )}
        </div>
      </div>

      {!collapsed && nestedBlocks.map((group, gi) => (
        <div key={gi}>
          {group.label && (
            <div style={{ paddingLeft: (depth + 1) * 14 + 6, paddingTop: 4, paddingBottom: 2 }}>
              <span style={{
                fontSize: 'var(--font-size-xs)',
                fontWeight: 'var(--font-weight-bold)',
                color: 'var(--text-tertiary)',
                textTransform: 'uppercase',
                letterSpacing: '0.05em',
              }}>
                {group.label}
              </span>
            </div>
          )}
          {group.blocks.map((sub, i) => (
            <DefinitionBlockTree key={sub.blockId} block={sub} depth={depth + 1} index={i} />
          ))}
        </div>
      ))}
    </div>
  );
}
