import { useMemo, useState, useEffect } from 'react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { useApi } from '@/hooks/useApi';
import { BlockEditor } from './BlockEditor';
import type { AutomationBlockDraft } from './automation-editor-types';
import { blockAutoName, type StateDisplayNames } from './automation-editor-utils';
import { BLOCK_ICONS } from './block-helpers';
import './BlockCard.css';

interface BlockCardProps {
  block: AutomationBlockDraft;
  index: number;
  ordinal?: number;
  expandedId: string | null;
  onToggleExpand: (id: string) => void;
  onChange: (updated: AutomationBlockDraft) => void;
  onNavigateToNested?: (blockId: string, info: { field: string; label: string }) => void;
  reorderMode: boolean;
  currentAutomationId?: string;
}

export function BlockCard({
  block,
  index,
  ordinal,
  expandedId,
  onToggleExpand,
  onChange,
  onNavigateToNested,
  reorderMode,
  currentAutomationId,
}: BlockCardProps) {
  const registry = useDeviceRegistry();
  const api = useApi();
  const isExpanded = expandedId === block._draftId && !reorderMode;

  // Load global value display names for auto-names
  const [stateNames, setStateNames] = useState<StateDisplayNames>({});
  useEffect(() => {
    let cancelled = false;
    api.getStateVariables().then(vars => {
      if (cancelled) return;
      const map: StateDisplayNames = {};
      for (const v of vars) map[v.name] = v.displayName || v.name;
      setStateNames(map);
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [api]);

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: block._draftId, disabled: !reorderMode });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  const autoName = useMemo(
    () => block.name || blockAutoName(block, registry, stateNames),
    [block, registry, stateNames],
  );

  const icon = BLOCK_ICONS[block.type] || 'square';

  const childSummary = useMemo((): string | null => {
    if (block.type === 'conditional') {
      const t = block.thenBlocks?.length || 0;
      const e = block.elseBlocks?.length || 0;
      if (t + e === 0) return null;
      const parts: string[] = [];
      if (t > 0) parts.push(`${t} then`);
      if (e > 0) parts.push(`${e} else`);
      return parts.join(', ');
    }
    if (['repeat', 'repeatWhile', 'group'].includes(block.type)) {
      const c = block.blocks?.length || 0;
      return c > 0 ? `${c} block${c > 1 ? 's' : ''}` : null;
    }
    return null;
  }, [block]);

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`block-card${isExpanded ? ' expanded' : ''}${block.block === 'flowControl' ? ' flow-control' : ''}${isDragging ? ' dragging' : ''}`}
    >
      <div className="block-card-header" onClick={() => !reorderMode && onToggleExpand(block._draftId)}>
        {reorderMode && (
          <div className="bc-drag-handle" {...attributes} {...listeners}>
            <Icon name="line-3-horizontal" size={16} />
          </div>
        )}
        <span className={`bc-ordinal ${block.block}`}>{ordinal ?? index + 1}</span>
        <span className={`bc-icon-wrap ${block.block}`}>
          <Icon name={icon} size={15} />
        </span>
        <div className="bc-info">
          <span className="bc-name">{autoName}</span>
          {!isExpanded && childSummary && (
            <span className="bc-children">{childSummary}</span>
          )}
        </div>
        <span className={`bc-type-badge ${block.block}`}>
          {block.block === 'action' ? 'Action' : 'Flow'}
        </span>
        {!reorderMode && (
          <Icon name={isExpanded ? 'chevron-down' : 'chevron-right'} size={12} className="bc-chevron" />
        )}
      </div>

      {isExpanded && (
        <div className="block-card-body">
          <BlockEditor
            draft={block}
            showHeader={false}
            currentAutomationId={currentAutomationId}
            onChange={onChange}
            onNavigateToNested={onNavigateToNested ? (info) => onNavigateToNested(block._draftId, info) : undefined}
          />
        </div>
      )}
    </div>
  );
}
