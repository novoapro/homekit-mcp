import { useState, useEffect, useCallback, useMemo, useRef, useReducer } from 'react';
import { useParams, useNavigate } from 'react-router';
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import {
  SortableContext,
  verticalListSortingStrategy,
  sortableKeyboardCoordinates,
} from '@dnd-kit/sortable';
import { Icon } from '@/components/Icon';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { useApi } from '@/hooks/useApi';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { useWorkflowDraft } from './useWorkflowDraft';
import { TriggerEditor } from './TriggerEditor';
import { ConditionEditor } from './ConditionEditor';
import { ConditionGroupEditor } from './ConditionGroupEditor';
import { BlockCard } from './BlockCard';
import { AddBlockSheet } from './AddBlockSheet';
import { newBlockDraft, containerTargets, moveBlockToContainer, cloneBlockDraft, BLOCK_TYPE_LABELS, BLOCK_ICONS } from './block-helpers';
import { validateDraft } from './workflow-editor-validation';
import { draftToPayload, definitionToDraft, triggerAutoName, conditionAutoName, collectAllBlockInfos } from './workflow-editor-utils';
import type { BlockInfo } from './workflow-editor-utils';
import { newUUID } from './workflow-editor-types';
import type { WorkflowTriggerDraft, WorkflowConditionDraft, WorkflowBlockDraft } from './workflow-editor-types';
import './WorkflowEditorPage.css';

const TRIGGER_ICONS: Record<string, string> = {
  deviceStateChange: 'house',
  schedule: 'clock',
  sunEvent: 'sun-max',
  webhook: 'globe',
  workflow: 'arrow-triangle-branch',
};

const TRIGGER_BADGES: Record<string, string> = {
  deviceStateChange: 'Device',
  schedule: 'Schedule',
  sunEvent: 'Sun',
  webhook: 'Webhook',
  workflow: 'Callable',
};

interface PanelFrame {
  type: 'trigger' | 'condition' | 'conditionGroup';
  title: string;
  triggerIndex?: number;
  conditionPath?: number[];
}

interface NestingFrame {
  blockId: string;
  field: string;
  label: string;
}

export function WorkflowEditorPage() {
  const { workflowId } = useParams<{ workflowId: string }>();
  const navigate = useNavigate();
  const api = useApi();
  const registry = useDeviceRegistry();

  const isEditMode = !!workflowId;

  const {
    draft,
    isDirty,
    reset,
    markSaved,
    patchDraft,
    setTrigger,
    addTrigger,
    removeTrigger,
    setRootConditions,
    setBlock,
    addBlock,
    removeBlock,
    moveBlock,
  } = useWorkflowDraft();

  const [isLoading, setIsLoading] = useState(isEditMode);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [panel, setPanel] = useState<PanelFrame | null>(null);
  const [expandedBlockId, setExpandedBlockId] = useState<string | null>(null);
  const [reorderMode, setReorderMode] = useState(false);
  const [showAddSheet, setShowAddSheet] = useState(false);
  const [nestingStack, setNestingStack] = useState<NestingFrame[]>([]);

  // Temp state for panel editing
  const panelTriggerRef = useRef<WorkflowTriggerDraft | null>(null);
  const panelConditionRef = useRef<WorkflowConditionDraft | null>(null);
  const editingBlockIdRef = useRef<string | null>(null);
  // Force re-render when condition ref changes (buttons derive state from draft prop)
  const [, forcePanel] = useReducer((x: number) => x + 1, 0);

  // --- Unsaved changes protection ---
  const [showLeaveDialog, setShowLeaveDialog] = useState(false);
  const pendingNavRef = useRef<(() => void) | null>(null);

  const guardedNavigate = useCallback(
    (navFn: () => void) => {
      if (isDirty && !isSaving) {
        pendingNavRef.current = navFn;
        setShowLeaveDialog(true);
      } else {
        navFn();
      }
    },
    [isDirty, isSaving],
  );

  // Browser close/refresh protection
  useEffect(() => {
    if (!isDirty) return;
    const handler = (e: BeforeUnloadEvent) => { e.preventDefault(); };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [isDirty]);

  // DnD sensors
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  // Load existing workflow for edit mode
  useEffect(() => {
    if (!isEditMode || !workflowId) return;
    (async () => {
      setIsLoading(true);
      try {
        const wf = await api.getWorkflow(workflowId);
        reset(definitionToDraft(wf));
      } catch (err: unknown) {
        setError(err instanceof Error ? err.message : 'Failed to load workflow');
      } finally {
        setIsLoading(false);
      }
    })();
  }, [api, workflowId, isEditMode, reset]);

  const validationErrors = useMemo(() => validateDraft(draft), [draft]);

  const allBlocks: BlockInfo[] = useMemo(
    () => collectAllBlockInfos(draft.blocks, registry),
    [draft.blocks, registry],
  );

  const ordinalMap = useMemo(() => {
    const map = new Map<string, number>();
    for (const b of allBlocks) map.set(b._draftId, b.ordinal);
    return map;
  }, [allBlocks]);

  const doGoBack = useCallback(() => {
    if (window.history.length > 1) {
      navigate(-1);
    } else {
      navigate('/workflows');
    }
  }, [navigate]);

  const goBack = useCallback(() => {
    guardedNavigate(doGoBack);
  }, [guardedNavigate, doGoBack]);

  // --- Resolve current block list (respecting nesting) ---

  const resolveNestedBlocks = useCallback((): WorkflowBlockDraft[] => {
    if (nestingStack.length === 0) return draft.blocks;

    let blocks = draft.blocks;
    for (const frame of nestingStack) {
      const parent = blocks.find((b) => b._draftId === frame.blockId);
      if (!parent) return [];
      if (frame.field === 'thenBlocks') blocks = parent.thenBlocks ?? [];
      else if (frame.field === 'elseBlocks') blocks = parent.elseBlocks ?? [];
      else blocks = parent.blocks ?? [];
    }
    return blocks;
  }, [draft.blocks, nestingStack]);

  const currentBlocks = useMemo(() => resolveNestedBlocks(), [resolveNestedBlocks]);

  // Selected block info for footer actions
  const selectedBlock = useMemo(() => {
    if (!expandedBlockId || reorderMode) return null;
    const idx = currentBlocks.findIndex((b) => b._draftId === expandedBlockId);
    if (idx < 0) return null;
    const block = currentBlocks[idx]!;
    const ordinal = ordinalMap.get(block._draftId);
    return { block, index: idx, ordinal };
  }, [expandedBlockId, reorderMode, currentBlocks, ordinalMap]);

  const selectedMoveTargets = useMemo(() => {
    if (!selectedBlock) return [];
    return containerTargets(selectedBlock.block._draftId, currentBlocks, ordinalMap);
  }, [selectedBlock, currentBlocks, ordinalMap]);

  const setNestedBlocks = useCallback(
    (blocks: WorkflowBlockDraft[]) => {
      if (nestingStack.length === 0) {
        // Replace all root blocks
        patchDraft({ blocks });
        return;
      }

      // Deep clone root blocks and navigate to the right container
      const rootBlocks: WorkflowBlockDraft[] = JSON.parse(JSON.stringify(draft.blocks));
      let container = rootBlocks;
      for (let i = 0; i < nestingStack.length; i++) {
        const frame = nestingStack[i]!;
        const parentIdx = container.findIndex((b) => b._draftId === frame.blockId);
        if (parentIdx < 0) return;
        const parent = container[parentIdx]!;
        if (i === nestingStack.length - 1) {
          // Last frame: set the blocks
          if (frame.field === 'thenBlocks') parent.thenBlocks = blocks;
          else if (frame.field === 'elseBlocks') parent.elseBlocks = blocks;
          else parent.blocks = blocks;
        } else {
          // Navigate deeper
          if (frame.field === 'thenBlocks') container = parent.thenBlocks ?? [];
          else if (frame.field === 'elseBlocks') container = parent.elseBlocks ?? [];
          else container = parent.blocks ?? [];
        }
      }
      patchDraft({ blocks: rootBlocks });
    },
    [draft.blocks, nestingStack, patchDraft],
  );

  // --- Block operations (respecting nesting) ---

  const handleBlockChange = useCallback(
    (index: number, updated: WorkflowBlockDraft) => {
      if (nestingStack.length === 0) {
        setBlock(index, updated);
      } else {
        const blocks = [...currentBlocks];
        blocks[index] = updated;
        setNestedBlocks(blocks);
      }
    },
    [nestingStack, currentBlocks, setBlock, setNestedBlocks],
  );

  const handleBlockRemove = useCallback(
    (index: number) => {
      if (nestingStack.length === 0) {
        removeBlock(index);
      } else {
        const blocks = currentBlocks.filter((_, i) => i !== index);
        setNestedBlocks(blocks);
      }
      setExpandedBlockId(null);
    },
    [nestingStack, currentBlocks, removeBlock, setNestedBlocks],
  );

  const handleBlockMoveUp = useCallback(
    (index: number) => {
      if (index <= 0) return;
      if (nestingStack.length === 0) {
        moveBlock(index, index - 1);
      } else {
        const blocks = [...currentBlocks];
        [blocks[index - 1], blocks[index]] = [blocks[index]!, blocks[index - 1]!];
        setNestedBlocks(blocks);
      }
    },
    [nestingStack, currentBlocks, moveBlock, setNestedBlocks],
  );

  const handleBlockMoveDown = useCallback(
    (index: number) => {
      if (index >= currentBlocks.length - 1) return;
      if (nestingStack.length === 0) {
        moveBlock(index, index + 1);
      } else {
        const blocks = [...currentBlocks];
        [blocks[index], blocks[index + 1]] = [blocks[index + 1]!, blocks[index]!];
        setNestedBlocks(blocks);
      }
    },
    [nestingStack, currentBlocks, moveBlock, setNestedBlocks],
  );

  const handleAddBlock = useCallback(
    (type: string) => {
      const block = newBlockDraft(type);
      if (nestingStack.length === 0) {
        addBlock(block);
      } else {
        setNestedBlocks([...currentBlocks, block]);
      }
    },
    [nestingStack, currentBlocks, addBlock, setNestedBlocks],
  );

  const handleMoveToContainer = useCallback(
    (blockDraftId: string, targetDraftId: string, field: string) => {
      const newBlocks = moveBlockToContainer(blockDraftId, targetDraftId, field, currentBlocks);
      if (nestingStack.length === 0) {
        patchDraft({ blocks: newBlocks });
      } else {
        setNestedBlocks(newBlocks);
      }
      setExpandedBlockId(null);
    },
    [currentBlocks, nestingStack, patchDraft, setNestedBlocks],
  );

  const handleBlockClone = useCallback(
    (index: number) => {
      const original = currentBlocks[index];
      if (!original) return;
      const clone = cloneBlockDraft(original);
      if (nestingStack.length === 0) {
        // Insert after original at root level
        const blocks = [...draft.blocks];
        blocks.splice(index + 1, 0, clone);
        patchDraft({ blocks });
      } else {
        const blocks = [...currentBlocks];
        blocks.splice(index + 1, 0, clone);
        setNestedBlocks(blocks);
      }
    },
    [currentBlocks, nestingStack, draft.blocks, patchDraft, setNestedBlocks],
  );

  const handleMoveToParent = useCallback(
    (index: number) => {
      if (nestingStack.length === 0) return; // Already at root
      const block = currentBlocks[index];
      if (!block) return;

      // Remove from current nested list
      const updatedCurrent = currentBlocks.filter((_, i) => i !== index);

      // Deep clone root blocks to modify
      const rootBlocks: WorkflowBlockDraft[] = JSON.parse(JSON.stringify(draft.blocks));

      // Navigate to the current nesting level and update it
      let container = rootBlocks;
      for (let i = 0; i < nestingStack.length; i++) {
        const frame = nestingStack[i]!;
        const parentIdx = container.findIndex((b) => b._draftId === frame.blockId);
        if (parentIdx < 0) return;
        const parent = container[parentIdx]!;
        if (i === nestingStack.length - 1) {
          // Last frame: update the nested blocks
          if (frame.field === 'thenBlocks') parent.thenBlocks = updatedCurrent;
          else if (frame.field === 'elseBlocks') parent.elseBlocks = updatedCurrent;
          else parent.blocks = updatedCurrent;
        } else {
          if (frame.field === 'thenBlocks') container = parent.thenBlocks ?? [];
          else if (frame.field === 'elseBlocks') container = parent.elseBlocks ?? [];
          else container = parent.blocks ?? [];
        }
      }

      // Now append the block to the parent level
      if (nestingStack.length === 1) {
        // Parent is root
        rootBlocks.push(JSON.parse(JSON.stringify(block)));
      } else {
        // Parent is one level up
        let parentContainer = rootBlocks;
        for (let i = 0; i < nestingStack.length - 1; i++) {
          const frame = nestingStack[i]!;
          const parentIdx = parentContainer.findIndex((b) => b._draftId === frame.blockId);
          if (parentIdx < 0) return;
          const parent = parentContainer[parentIdx]!;
          if (i === nestingStack.length - 2) {
            // This is the target parent level
            if (frame.field === 'thenBlocks') {
              parent.thenBlocks = [...(parent.thenBlocks ?? []), JSON.parse(JSON.stringify(block))];
            } else if (frame.field === 'elseBlocks') {
              parent.elseBlocks = [...(parent.elseBlocks ?? []), JSON.parse(JSON.stringify(block))];
            } else {
              parent.blocks = [...(parent.blocks ?? []), JSON.parse(JSON.stringify(block))];
            }
          } else {
            if (frame.field === 'thenBlocks') parentContainer = parent.thenBlocks ?? [];
            else if (frame.field === 'elseBlocks') parentContainer = parent.elseBlocks ?? [];
            else parentContainer = parent.blocks ?? [];
          }
        }
      }

      patchDraft({ blocks: rootBlocks });
      setExpandedBlockId(null);
    },
    [currentBlocks, nestingStack, draft.blocks, patchDraft],
  );

  const handleDragEnd = useCallback(
    (event: DragEndEvent) => {
      const { active, over } = event;
      if (!over || active.id === over.id) return;

      const oldIndex = currentBlocks.findIndex((b) => b._draftId === active.id);
      const newIndex = currentBlocks.findIndex((b) => b._draftId === over.id);
      if (oldIndex < 0 || newIndex < 0) return;

      if (nestingStack.length === 0) {
        moveBlock(oldIndex, newIndex);
      } else {
        const blocks = [...currentBlocks];
        const [moved] = blocks.splice(oldIndex, 1);
        if (moved) blocks.splice(newIndex, 0, moved);
        setNestedBlocks(blocks);
      }
    },
    [currentBlocks, nestingStack, moveBlock, setNestedBlocks],
  );

  // --- Nesting navigation ---

  const navigateToNested = useCallback(
    (blockId: string, info: { field: string; label: string }) => {
      if (info.field === 'condition') {
        // Open condition panel for this block
        const block = currentBlocks.find((b) => b._draftId === blockId);
        if (!block) return;

        let condDraft = block.condition
          ? (JSON.parse(JSON.stringify(block.condition)) as WorkflowConditionDraft)
          : { _draftId: newUUID(), type: 'and' as const, conditions: [] };

        // Wrap leaf conditions in an AND group for consistent editing
        if (condDraft.type !== 'and' && condDraft.type !== 'or' && condDraft.type !== 'not') {
          condDraft = { _draftId: newUUID(), type: 'and', conditions: [condDraft] };
        }

        editingBlockIdRef.current = blockId;
        panelConditionRef.current = condDraft;
        setPanel({ type: 'conditionGroup', title: info.label, conditionPath: [0] });
        return;
      }

      setNestingStack((prev) => [...prev, { blockId, field: info.field, label: info.label }]);
      setExpandedBlockId(null);
      setReorderMode(false);
    },
    [currentBlocks],
  );

  const navigateBack = useCallback(
    (toIndex: number) => {
      setNestingStack((prev) => prev.slice(0, toIndex));
      setExpandedBlockId(null);
      setReorderMode(false);
    },
    [],
  );

  const closePanel = useCallback(() => {
    setPanel(null);
    panelTriggerRef.current = null;
    panelConditionRef.current = null;
    editingBlockIdRef.current = null;
  }, []);

  // --- Trigger panel ---

  const openTriggerPanel = useCallback(
    (index: number) => {
      const trigger = draft.triggers[index];
      if (!trigger) return;
      panelTriggerRef.current = { ...trigger };
      setPanel({ type: 'trigger', title: `Trigger ${index + 1}`, triggerIndex: index });
    },
    [draft.triggers],
  );

  const applyTriggerPanel = useCallback(() => {
    if (panel?.triggerIndex !== undefined && panelTriggerRef.current) {
      setTrigger(panel.triggerIndex, panelTriggerRef.current);
    }
    closePanel();
  }, [panel, setTrigger, closePanel]);

  // --- Condition panel ---

  const openConditionGroupPanel = useCallback(() => {
    const root = draft.conditions[0];
    if (root) {
      panelConditionRef.current = JSON.parse(JSON.stringify(root));
    } else {
      panelConditionRef.current = { _draftId: newUUID(), type: 'and', conditions: [] };
    }
    setPanel({ type: 'conditionGroup', title: 'Guard Conditions', conditionPath: [0] });
  }, [draft.conditions]);

  const openNestedConditionPanel = useCallback(
    (info: { field: string; index: number; label: string }) => {
      const parent = panelConditionRef.current;
      if (!parent) return;

      let innerGroup = parent;
      if (parent.type === 'not' && parent.condition && (parent.condition.type === 'and' || parent.condition.type === 'or')) {
        innerGroup = parent.condition;
      }

      const child = innerGroup.conditions?.[info.index];
      if (!child) return;

      const isGroup = child.type === 'and' || child.type === 'or' || child.type === 'not';
      if (isGroup) {
        panelConditionRef.current = JSON.parse(JSON.stringify(child));
        setPanel({
          type: 'conditionGroup',
          title: info.label,
          conditionPath: [...(panel?.conditionPath ?? [0]), info.index],
        });
      } else {
        panelConditionRef.current = JSON.parse(JSON.stringify(child));
        setPanel({
          type: 'condition',
          title: info.label,
          conditionPath: [...(panel?.conditionPath ?? [0]), info.index],
        });
      }
    },
    [panel],
  );

  const applyConditionPanel = useCallback(() => {
    if (!panelConditionRef.current) { setPanel(null); return; }

    const path = panel?.conditionPath ?? [0];
    const blockId = editingBlockIdRef.current;

    if (blockId) {
      // Applying to a block's condition
      const blockIndex = currentBlocks.findIndex((b) => b._draftId === blockId);
      if (blockIndex >= 0) {
        if (path.length === 1) {
          handleBlockChange(blockIndex, { ...currentBlocks[blockIndex]!, condition: panelConditionRef.current });
        } else {
          const rootCopy: WorkflowConditionDraft = JSON.parse(JSON.stringify(
            currentBlocks[blockIndex]!.condition ?? { _draftId: newUUID(), type: 'and', conditions: [] }
          ));
          let current = rootCopy;
          for (let i = 1; i < path.length - 1; i++) {
            let inner = current;
            if (inner.type === 'not' && inner.condition && (inner.condition.type === 'and' || inner.condition.type === 'or')) {
              inner = inner.condition;
            }
            current = inner.conditions![path[i]!]!;
          }
          let innerTarget = current;
          if (innerTarget.type === 'not' && innerTarget.condition && (innerTarget.condition.type === 'and' || innerTarget.condition.type === 'or')) {
            innerTarget = innerTarget.condition;
          }
          innerTarget.conditions![path[path.length - 1]!] = panelConditionRef.current;
          handleBlockChange(blockIndex, { ...currentBlocks[blockIndex]!, condition: rootCopy });
        }
      }
      editingBlockIdRef.current = null;
    } else {
      // Applying to root guard conditions
      if (path.length === 1) {
        setRootConditions([panelConditionRef.current]);
      } else {
        const rootCopy: WorkflowConditionDraft = JSON.parse(JSON.stringify(draft.conditions[0] ?? { _draftId: newUUID(), type: 'and', conditions: [] }));
        let current = rootCopy;
        for (let i = 1; i < path.length - 1; i++) {
          let inner = current;
          if (inner.type === 'not' && inner.condition && (inner.condition.type === 'and' || inner.condition.type === 'or')) {
            inner = inner.condition;
          }
          current = inner.conditions![path[i]!]!;
        }
        let innerTarget = current;
        if (innerTarget.type === 'not' && innerTarget.condition && (innerTarget.condition.type === 'and' || innerTarget.condition.type === 'or')) {
          innerTarget = innerTarget.condition;
        }
        innerTarget.conditions![path[path.length - 1]!] = panelConditionRef.current;
        setRootConditions([rootCopy]);
      }
    }
    closePanel();
  }, [panel, draft.conditions, currentBlocks, setRootConditions, handleBlockChange, closePanel]);

  // --- Save ---

  const saveWorkflow = useCallback(async () => {
    if (validationErrors.length > 0) return;
    setIsSaving(true);
    setError(null);
    try {
      const payload = draftToPayload(draft);
      if (isEditMode && workflowId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await api.updateWorkflow(workflowId, payload as any);
        markSaved();
        navigate(`/workflows/${workflowId}/definition`, { replace: true });
      } else {
        const created = await api.createWorkflow(payload);
        markSaved();
        navigate(`/workflows/${created.id}/definition`, { replace: true });
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to save workflow');
    } finally {
      setIsSaving(false);
    }
  }, [validationErrors, draft, isEditMode, workflowId, api, navigate, markSaved]);

  // --- Render ---

  if (isLoading) {
    return (
      <div className="wfe-page">
        <div className="wfe-loading">
          <Icon name="spinner" size={24} className="animate-spin" />
          <span>Loading...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="wfe-page">
      <button className="wfe-back-btn" onClick={goBack} type="button">
        <span style={{ transform: 'rotate(90deg)', display: 'inline-flex' }}>
          <Icon name="chevron-down" size={14} />
        </span>
        <span>Back</span>
      </button>

      <h1 className="wfe-page-title">{isEditMode ? 'Edit Workflow' : 'New Workflow'}</h1>

      {error && (
        <div className="wfe-error-banner animate-fade-in">
          <Icon name="exclamation-triangle" size={16} />
          <span>{error}</span>
        </div>
      )}

      {/* Details Section */}
      <div className="wfe-section">
        <h3 className="wfe-section-title">Details</h3>
        <div className="wfe-detail-fields">
          <div className="editor-field">
            <label>Name</label>
            <input
              className="editor-input"
              value={draft.name}
              onChange={(e) => patchDraft({ name: e.target.value })}
              placeholder="Workflow name"
            />
          </div>
          <div className="editor-field">
            <label>Description</label>
            <input
              className="editor-input"
              value={draft.description}
              onChange={(e) => patchDraft({ description: e.target.value })}
              placeholder="Optional description"
            />
          </div>
          <div className="wfe-toggle-row">
            <div>
              <div className="wfe-toggle-label">Enabled</div>
              <div className="wfe-toggle-hint">Workflow will execute when triggered</div>
            </div>
            <button
              type="button"
              className={`wfe-switch${draft.isEnabled ? ' on' : ''}`}
              onClick={() => patchDraft({ isEnabled: !draft.isEnabled })}
              role="switch"
              aria-checked={draft.isEnabled}
            />
          </div>
          <div className="wfe-toggle-row">
            <div>
              <div className="wfe-toggle-label">Continue on Error</div>
              <div className="wfe-toggle-hint">Keep running blocks after a failure</div>
            </div>
            <button
              type="button"
              className={`wfe-switch${draft.continueOnError ? ' on' : ''}`}
              onClick={() => patchDraft({ continueOnError: !draft.continueOnError })}
              role="switch"
              aria-checked={draft.continueOnError}
            />
          </div>
        </div>
      </div>

      {/* Triggers Section */}
      <div className="wfe-section">
        <h3 className="wfe-section-title">
          Triggers <span className="wfe-section-count">({draft.triggers.length})</span>
        </h3>
        {draft.triggers.length > 0 && (
          <div className="wfe-trigger-list">
            {draft.triggers.map((trigger, i) => (
              <div key={trigger._draftId} className="wfe-trigger-node" onClick={() => openTriggerPanel(i)}>
                <Icon name={TRIGGER_ICONS[trigger.type] || 'bolt'} size={15} style={{ color: 'var(--text-tertiary)', opacity: 0.5 }} />
                <div className="wfe-trigger-node-info">
                  <span className="wfe-trigger-node-name">
                    {trigger.name || triggerAutoName(trigger, registry)}
                  </span>
                </div>
                <span className="wfe-trigger-badge">{TRIGGER_BADGES[trigger.type] || trigger.type}</span>
                <Icon name="chevron-down" size={12} style={{ color: 'var(--text-tertiary)', opacity: 0.25, transform: 'rotate(-90deg)' }} />
              </div>
            ))}
          </div>
        )}
        <button className="wfe-add-btn" onClick={() => { addTrigger(); openTriggerPanel(draft.triggers.length); }} type="button">
          <Icon name="plus-circle" size={14} />
          Add Trigger
        </button>
      </div>

      {/* Guard Conditions Section */}
      <div className="wfe-section">
        <h3 className="wfe-section-title">Guard Conditions</h3>
        {draft.conditions.length > 0 && draft.conditions[0] && (
          <div className="wfe-condition-node" onClick={openConditionGroupPanel}>
            <Icon name="arrow-triangle-branch" size={15} style={{ color: 'var(--text-tertiary)', opacity: 0.5 }} />
            <div className="wfe-trigger-node-info">
              <span className="wfe-trigger-node-name">
                {conditionAutoName(draft.conditions[0], registry, allBlocks)}
              </span>
            </div>
            <span className="child-badge logic">
              {draft.conditions[0].type === 'not' ? 'NOT' : draft.conditions[0].type.toUpperCase()}
            </span>
            <Icon name="chevron-down" size={12} style={{ color: 'var(--text-tertiary)', opacity: 0.25, transform: 'rotate(-90deg)' }} />
          </div>
        )}
        {draft.conditions.length === 0 && (
          <button className="wfe-condition-add-btn" onClick={openConditionGroupPanel} type="button">
            <Icon name="plus-circle" size={14} />
            Add Guard Conditions
          </button>
        )}
      </div>

      {/* Blocks Section */}
      <div className="wfe-section">
        <div className="wfe-blocks-header">
          <h3 className="wfe-section-title">
            Blocks <span className="wfe-section-count">({currentBlocks.length})</span>
          </h3>
          {currentBlocks.length >= 2 && (
            <button
              type="button"
              className={`wfe-reorder-btn${reorderMode ? ' active' : ''}`}
              onClick={() => { setReorderMode(!reorderMode); setExpandedBlockId(null); }}
            >
              <Icon name="line-3-horizontal" size={14} />
              {reorderMode ? 'Done' : 'Reorder'}
            </button>
          )}
        </div>

        {/* Breadcrumbs for nesting */}
        {nestingStack.length > 0 && (
          <div className="wfe-breadcrumbs">
            <button type="button" className="wfe-crumb" onClick={() => navigateBack(0)}>
              Root
            </button>
            {nestingStack.map((frame, i) => (
              <span key={i} className="wfe-crumb-item">
                <Icon name="chevron-down" size={10} style={{ transform: 'rotate(-90deg)', opacity: 0.3 }} />
                <button
                  type="button"
                  className={`wfe-crumb${i === nestingStack.length - 1 ? ' current' : ''}`}
                  onClick={() => navigateBack(i + 1)}
                >
                  {frame.label}
                </button>
              </span>
            ))}
          </div>
        )}

        {currentBlocks.length > 0 && (
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
            <SortableContext items={currentBlocks.map((b) => b._draftId)} strategy={verticalListSortingStrategy}>
              <div className="wfe-block-list">
                {currentBlocks.map((block, i) => (
                  <BlockCard
                    key={block._draftId}
                    block={block}
                    index={i}
                    ordinal={ordinalMap.get(block._draftId)}
                    expandedId={expandedBlockId}
                    onToggleExpand={(id) => setExpandedBlockId(expandedBlockId === id ? null : id)}
                    onChange={(updated) => handleBlockChange(i, updated)}
                    onNavigateToNested={navigateToNested}
                    reorderMode={reorderMode}
                  />
                ))}
              </div>
            </SortableContext>
          </DndContext>
        )}

        {currentBlocks.length === 0 && !reorderMode && (
          <div className="wfe-blocks-empty">
            <Icon name="square-stack-3d-up" size={24} style={{ opacity: 0.3 }} />
            <span>No blocks yet. Add one to get started.</span>
          </div>
        )}

        {!reorderMode && (
          <button className="wfe-add-btn" onClick={() => setShowAddSheet(true)} type="button">
            <Icon name="plus-circle" size={14} />
            Add Block
          </button>
        )}
      </div>

      {/* Add Block Sheet */}
      <AddBlockSheet
        open={showAddSheet}
        onClose={() => setShowAddSheet(false)}
        onAdd={handleAddBlock}
      />

      {/* Slide-over Panel */}
      {panel && (
        <>
          <div className="wfe-panel-overlay" onClick={closePanel} />
          <div className="wfe-panel">
            <div className="wfe-panel-header">
              <h3 className="wfe-panel-title">{panel.title}</h3>
              <button className="wfe-panel-close-btn" onClick={closePanel} type="button">
                <Icon name="xmark" size={16} />
              </button>
            </div>
            <div className="wfe-panel-body">
              {panel.type === 'trigger' && panel.triggerIndex !== undefined && panelTriggerRef.current && (
                <TriggerEditor
                  index={panel.triggerIndex}
                  draft={panelTriggerRef.current}
                  onChange={(updated) => { panelTriggerRef.current = updated; forcePanel(); }}
                  onRemove={() => {
                    removeTrigger(panel.triggerIndex!);
                    closePanel();
                  }}
                />
              )}
              {panel.type === 'conditionGroup' && panelConditionRef.current && (
                <ConditionGroupEditor
                  draft={panelConditionRef.current}
                  allBlocks={allBlocks}
                  currentBlockDraftId={editingBlockIdRef.current ?? undefined}
                  continueOnError={draft.continueOnError}
                  onChange={(updated) => { panelConditionRef.current = updated; forcePanel(); }}
                  onEditNestedCondition={openNestedConditionPanel}
                />
              )}
              {panel.type === 'condition' && panelConditionRef.current && (
                <ConditionEditor
                  draft={panelConditionRef.current}
                  allBlocks={allBlocks}
                  currentBlockDraftId={editingBlockIdRef.current ?? undefined}
                  continueOnError={draft.continueOnError}
                  onChange={(updated) => { panelConditionRef.current = updated; forcePanel(); }}
                />
              )}
            </div>
            <div className="wfe-panel-footer">
              <button className="wfe-panel-btn discard" onClick={closePanel} type="button">
                Discard
              </button>
              <button
                className="wfe-panel-btn apply"
                onClick={() => {
                  if (panel.type === 'trigger') applyTriggerPanel();
                  else applyConditionPanel();
                }}
                type="button"
              >
                Apply
              </button>
            </div>
          </div>
        </>
      )}

      {/* Sticky Footer */}
      <div className="wfe-footer">
        <div className="wfe-footer-inner">
          {selectedBlock && (
            <div className="wfe-footer-block" key={selectedBlock.block._draftId}>
              <div className="wfe-footer-block-row">
                <div className="wfe-footer-block-info">
                  <span className={`wfe-footer-block-icon ${selectedBlock.block.block}`}>
                    <Icon name={BLOCK_ICONS[selectedBlock.block.type] || 'square'} size={13} />
                  </span>
                  <span className="wfe-footer-block-label">
                    #{selectedBlock.ordinal ?? selectedBlock.index + 1}{' '}
                    {selectedBlock.block.name || BLOCK_TYPE_LABELS[selectedBlock.block.type] || selectedBlock.block.type}
                  </span>
                </div>
                <div className="wfe-footer-block-actions">
                  <button
                    className="wfe-footer-block-btn"
                    disabled={selectedBlock.index === 0}
                    onClick={() => handleBlockMoveUp(selectedBlock.index)}
                    title="Move up"
                    type="button"
                  >
                    <Icon name="chevron-up" size={14} />
                  </button>
                  <button
                    className="wfe-footer-block-btn"
                    disabled={selectedBlock.index === currentBlocks.length - 1}
                    onClick={() => handleBlockMoveDown(selectedBlock.index)}
                    title="Move down"
                    type="button"
                  >
                    <Icon name="chevron-down" size={14} />
                  </button>
                  <div className="wfe-footer-block-sep" />
                  <button
                    className="wfe-footer-block-btn"
                    onClick={() => handleBlockClone(selectedBlock.index)}
                    title="Duplicate"
                    type="button"
                  >
                    <Icon name="doc-on-doc" size={13} />
                  </button>
                  <button
                    className="wfe-footer-block-btn danger"
                    onClick={() => handleBlockRemove(selectedBlock.index)}
                    title="Delete"
                    type="button"
                  >
                    <Icon name="trash" size={13} />
                  </button>
                </div>
              </div>
              {(nestingStack.length > 0 || selectedMoveTargets.length > 0) && (
                <div className="wfe-footer-block-move">
                  {nestingStack.length > 0 && (
                    <button
                      className="wfe-footer-move-btn"
                      onClick={() => handleMoveToParent(selectedBlock.index)}
                      type="button"
                    >
                      <Icon name="arrow-up-circle" size={13} />
                      <span>Move to Parent</span>
                    </button>
                  )}
                  {selectedMoveTargets.length > 0 && (
                    <select
                      className="wfe-footer-move-select"
                      value=""
                      onChange={(e) => {
                        if (!e.target.value) return;
                        const [targetId, field] = e.target.value.split('::');
                        if (targetId && field) handleMoveToContainer(selectedBlock.block._draftId, targetId, field);
                      }}
                    >
                      <option value="" disabled>Move into...</option>
                      {selectedMoveTargets.map((t) => (
                        <option key={`${t.containerDraftId}::${t.field}`} value={`${t.containerDraftId}::${t.field}`}>
                          {t.description}
                        </option>
                      ))}
                    </select>
                  )}
                </div>
              )}
            </div>
          )}
          {validationErrors.length > 0 && (
            <div className="wfe-validation-errors">
              {validationErrors.map((err, i) => (
                <div key={i} className="wfe-validation-error">
                  <Icon name="exclamation-circle-fill" size={12} />
                  <span>{err}</span>
                </div>
              ))}
            </div>
          )}
          <div className="wfe-footer-actions">
            <button className="wfe-cancel-btn" onClick={goBack} type="button">Cancel</button>
            <button
              className="wfe-save-btn"
              disabled={validationErrors.length > 0 || isSaving}
              onClick={saveWorkflow}
              type="button"
            >
              {isSaving ? 'Saving...' : isEditMode ? 'Save Changes' : 'Create Workflow'}
            </button>
          </div>
        </div>
      </div>

      {/* Unsaved changes confirmation */}
      <ConfirmDialog
        open={showLeaveDialog}
        title="Unsaved Changes"
        message="You have unsaved changes. Are you sure you want to leave? Your changes will be lost."
        confirmLabel="Leave"
        cancelLabel="Stay"
        destructive
        onConfirm={() => {
          setShowLeaveDialog(false);
          pendingNavRef.current?.();
          pendingNavRef.current = null;
        }}
        onCancel={() => {
          setShowLeaveDialog(false);
          pendingNavRef.current = null;
        }}
      />
    </div>
  );
}
