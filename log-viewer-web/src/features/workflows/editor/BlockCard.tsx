import { useMemo } from 'react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { BlockEditor } from './BlockEditor';
import type { WorkflowBlockDraft } from './workflow-editor-types';
import { blockAutoName } from './workflow-editor-utils';
import { BLOCK_ICONS } from './block-helpers';
import './BlockCard.css';

interface BlockCardProps {
  block: WorkflowBlockDraft;
  index: number;
  ordinal?: number;
  expandedId: string | null;
  onToggleExpand: (id: string) => void;
  onChange: (updated: WorkflowBlockDraft) => void;
  onNavigateToNested?: (blockId: string, info: { field: string; label: string }) => void;
  reorderMode: boolean;
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
}: BlockCardProps) {
  const registry = useDeviceRegistry();
  const isExpanded = expandedId === block._draftId && !reorderMode;

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
    () => block.name || blockAutoName(block, registry),
    [block, registry],
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
            onChange={onChange}
            onNavigateToNested={onNavigateToNested ? (info) => onNavigateToNested(block._draftId, info) : undefined}
          />
        </div>
      )}
    </div>
  );
}
