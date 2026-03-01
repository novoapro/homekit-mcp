import { useMemo, useCallback } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type { WorkflowConditionDraft } from './workflow-editor-types';
import { newUUID } from './workflow-editor-types';
import { newConditionLeaf, conditionAutoName } from './workflow-editor-utils';
import type { BlockInfo } from './workflow-editor-utils';
import './ConditionGroupEditor.css';

const CONDITION_ICONS: Record<string, string> = {
  deviceState: 'house',
  timeCondition: 'clock',
  sceneActive: 'sparkles',
  blockResult: 'checkmark-circle',
  and: 'arrow-triangle-branch',
  or: 'arrow-triangle-branch',
  not: 'exclamation-triangle',
};

const LEAF_TYPE_OPTIONS = [
  { value: 'deviceState', label: 'Device State' },
  { value: 'timeCondition', label: 'Time Window' },
  { value: 'sceneActive', label: 'Scene Active' },
  { value: 'blockResult', label: 'Block Result' },
];

interface ConditionGroupEditorProps {
  draft: WorkflowConditionDraft;
  allowBlockResult?: boolean;
  allBlocks?: BlockInfo[];
  currentBlockDraftId?: string;
  continueOnError?: boolean;
  onChange: (updated: WorkflowConditionDraft) => void;
  onEditNestedCondition: (info: { field: string; index: number; label: string }) => void;
}

export function ConditionGroupEditor({
  draft,
  allowBlockResult = true,
  allBlocks,
  currentBlockDraftId,
  continueOnError,
  onChange,
  onEditNestedCondition,
}: ConditionGroupEditorProps) {
  const registry = useDeviceRegistry();

  const leafTypeOptions = useMemo(() => {
    const currentOrdinal = allBlocks?.find((b) => b._draftId === currentBlockDraftId)?.ordinal;
    const isFirstBlock = currentOrdinal === 1;
    const hasPreceding = currentOrdinal !== undefined && currentOrdinal > 1;
    const shouldHide = !allowBlockResult || !continueOnError || isFirstBlock || !hasPreceding;
    return shouldHide
      ? LEAF_TYPE_OPTIONS.filter((o) => o.value !== 'blockResult')
      : LEAF_TYPE_OPTIONS;
  }, [allowBlockResult, allBlocks, currentBlockDraftId, continueOnError]);

  const isNegated = draft.type === 'not';

  const innerGroup = useMemo((): WorkflowConditionDraft => {
    if (draft.type === 'not' && draft.condition && (draft.condition.type === 'and' || draft.condition.type === 'or')) {
      return draft.condition;
    }
    return draft;
  }, [draft]);

  const operator = (innerGroup.type as 'and' | 'or') || 'and';
  const children = innerGroup.conditions || [];

  // --- Helpers ---

  function isGroup(c: WorkflowConditionDraft): boolean {
    return c.type === 'and' || c.type === 'or' || c.type === 'not';
  }

  function childName(c: WorkflowConditionDraft): string {
    if (c.type === 'and' || c.type === 'or') return `${c.type.toUpperCase()} Group`;
    if (c.type === 'not') {
      const inner = c.condition;
      if (inner && (inner.type === 'and' || inner.type === 'or')) return `NOT ${inner.type.toUpperCase()} Group`;
      return `NOT ${inner ? conditionAutoName(inner, registry, allBlocks) : '...'}`;
    }
    return conditionAutoName(c, registry, allBlocks);
  }

  function groupMeta(c: WorkflowConditionDraft): string {
    let count = 0;
    if (c.type === 'and' || c.type === 'or') {
      count = c.conditions?.length || 0;
    } else if (c.type === 'not' && c.condition) {
      if (c.condition.type === 'and' || c.condition.type === 'or') {
        count = c.condition.conditions?.length || 0;
      } else {
        return '1 condition';
      }
    }
    return `${count} condition${count !== 1 ? 's' : ''}`;
  }

  function badgeFor(c: WorkflowConditionDraft): string {
    if (c.type === 'and' || c.type === 'or') return c.type.toUpperCase();
    if (c.type === 'not') return 'NOT';
    return c.type;
  }

  // --- Mutations ---

  const patchInner = useCallback(
    (changes: Partial<WorkflowConditionDraft>) => {
      const inner: WorkflowConditionDraft = { ...innerGroup, ...changes };
      if (isNegated) {
        onChange({ ...draft, condition: inner });
      } else {
        onChange(inner);
      }
    },
    [innerGroup, isNegated, draft, onChange],
  );

  const setOperator = useCallback(
    (op: 'and' | 'or') => {
      if (op === operator) return;
      const updated: WorkflowConditionDraft = { ...innerGroup, type: op };
      if (isNegated) {
        onChange({ ...draft, condition: updated });
      } else {
        onChange(updated);
      }
    },
    [operator, innerGroup, isNegated, draft, onChange],
  );

  const toggleNot = useCallback(() => {
    if (isNegated) {
      onChange({ ...innerGroup });
    } else {
      onChange({ _draftId: draft._draftId, type: 'not', condition: { ...draft } });
    }
  }, [isNegated, innerGroup, draft, onChange]);

  const removeChild = useCallback(
    (index: number) => {
      const conditions = (innerGroup.conditions || []).filter((_, i) => i !== index);
      patchInner({ conditions });
    },
    [innerGroup.conditions, patchInner],
  );

  const addLeaf = useCallback(
    (type: string) => {
      const leaf = newConditionLeaf(type);
      const conditions = [...(innerGroup.conditions || []), leaf];
      patchInner({ conditions });
      const idx = conditions.length - 1;
      const label = leafTypeOptions.find((o) => o.value === type)?.label || type;
      requestAnimationFrame(() => {
        onEditNestedCondition({ field: 'conditions', index: idx, label });
      });
    },
    [innerGroup.conditions, patchInner, leafTypeOptions, onEditNestedCondition],
  );

  const addGroup = useCallback(() => {
    const oppositeOp = operator === 'and' ? 'or' : 'and';
    const group: WorkflowConditionDraft = { _draftId: newUUID(), type: oppositeOp, conditions: [] };
    const conditions = [...(innerGroup.conditions || []), group];
    patchInner({ conditions });
    const idx = conditions.length - 1;
    const label = `${oppositeOp.toUpperCase()} Group`;
    requestAnimationFrame(() => {
      onEditNestedCondition({ field: 'conditions', index: idx, label });
    });
  }, [operator, innerGroup.conditions, patchInner, onEditNestedCondition]);

  return (
    <div className="group-editor">
      {/* Operator toggle */}
      <div className="operator-section">
        <span className="operator-label">Match</span>
        <div className="operator-toggle-group">
          <button
            type="button"
            className={`operator-toggle${operator === 'and' ? ' active' : ''}`}
            onClick={() => setOperator('and')}
          >
            All (AND)
          </button>
          <button
            type="button"
            className={`operator-toggle${operator === 'or' ? ' active' : ''}`}
            onClick={() => setOperator('or')}
          >
            Any (OR)
          </button>
        </div>
        <button type="button" className={`not-btn${isNegated ? ' active' : ''}`} onClick={toggleNot}>
          NOT
        </button>
      </div>

      <p className="group-hint">
        {isNegated ? (
          <>
            All children must <strong>NOT</strong> {operator === 'and' ? 'all be true' : 'any be true'}
          </>
        ) : operator === 'and' ? (
          'All conditions must be true'
        ) : (
          'At least one condition must be true'
        )}
      </p>

      {/* Children list */}
      <div className="children-list">
        {children.map((child, i) => (
          <div key={child._draftId} className="child-node" onClick={() => onEditNestedCondition({ field: 'conditions', index: i, label: childName(child) })}>
            <Icon name={CONDITION_ICONS[child.type] || 'questionmark-circle'} size={15} className="child-icon" />
            <div className="child-info">
              <span className="child-name">{childName(child)}</span>
              {isGroup(child) && <span className="child-meta">{groupMeta(child)}</span>}
            </div>
            <span className={`child-badge${isGroup(child) ? ' logic' : ''}`}>{badgeFor(child)}</span>
            <button
              className="child-remove-btn"
              onClick={(e) => { e.stopPropagation(); removeChild(i); }}
              title="Remove"
              type="button"
            >
              <Icon name="xmark-circle-fill" size={14} />
            </button>
            <Icon name="chevron-down" size={12} className="child-chevron" />
          </div>
        ))}

        {children.length === 0 && <div className="cge-empty-hint">No conditions yet. Add one below.</div>}
      </div>

      {/* Add buttons */}
      <div className="cge-add-buttons">
        <button type="button" className="cge-add-btn" onClick={() => addLeaf('deviceState')}>
          <Icon name="plus-circle" size={14} />
          Add Condition
        </button>
        <button type="button" className="cge-add-btn group-btn" onClick={addGroup}>
          <Icon name="folder-badge-plus" size={14} />
          Add Group
        </button>
      </div>
    </div>
  );
}
