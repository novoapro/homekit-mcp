import { useReducer, useCallback, useRef, useMemo } from 'react';
import { produce } from 'immer';
import type {
  WorkflowDraft,
  WorkflowTriggerDraft,
  WorkflowConditionDraft,
  WorkflowBlockDraft,
} from './workflow-editor-types';
import { emptyDraft, newUUID } from './workflow-editor-types';

/** Serialize draft for dirty comparison, stripping _draftId fields */
function serializeForComparison(draft: WorkflowDraft): string {
  return JSON.stringify(draft, (key, value) => (key === '_draftId' ? undefined : value));
}

// --- Action types ---

type DraftAction =
  | { type: 'RESET'; draft: WorkflowDraft }
  | { type: 'PATCH'; changes: Partial<WorkflowDraft> }
  | { type: 'SET_TRIGGER'; index: number; trigger: WorkflowTriggerDraft }
  | { type: 'ADD_TRIGGER'; trigger: WorkflowTriggerDraft }
  | { type: 'REMOVE_TRIGGER'; index: number }
  | { type: 'SET_CONDITION'; path: number[]; condition: WorkflowConditionDraft }
  | { type: 'SET_ROOT_CONDITIONS'; conditions: WorkflowConditionDraft[] }
  | { type: 'SET_BLOCK'; index: number; block: WorkflowBlockDraft }
  | { type: 'ADD_BLOCK'; block: WorkflowBlockDraft }
  | { type: 'REMOVE_BLOCK'; index: number }
  | { type: 'MOVE_BLOCK'; fromIndex: number; toIndex: number }
  | { type: 'SET_NESTED_BLOCKS'; path: number[]; field: string; blocks: WorkflowBlockDraft[] };

function draftReducer(state: WorkflowDraft, action: DraftAction): WorkflowDraft {
  return produce(state, (draft) => {
    switch (action.type) {
      case 'RESET':
        return action.draft;

      case 'PATCH':
        Object.assign(draft, action.changes);
        break;

      case 'SET_TRIGGER':
        draft.triggers[action.index] = action.trigger;
        break;

      case 'ADD_TRIGGER':
        draft.triggers.push(action.trigger);
        break;

      case 'REMOVE_TRIGGER':
        draft.triggers.splice(action.index, 1);
        break;

      case 'SET_ROOT_CONDITIONS':
        draft.conditions = action.conditions;
        break;

      case 'SET_CONDITION': {
        // Navigate to the condition at the given path and replace it
        const { path, condition } = action;
        if (path.length === 1) {
          draft.conditions[path[0]!] = condition;
        } else {
          let current = draft.conditions[path[0]!]!;
          for (let i = 1; i < path.length - 1; i++) {
            if (current.conditions) {
              current = current.conditions[path[i]!]!;
            } else if (current.condition) {
              current = current.condition;
            }
          }
          const lastIdx = path[path.length - 1]!;
          if (current.conditions) {
            current.conditions[lastIdx] = condition;
          }
        }
        break;
      }

      case 'SET_BLOCK':
        draft.blocks[action.index] = action.block;
        break;

      case 'ADD_BLOCK':
        draft.blocks.push(action.block);
        break;

      case 'REMOVE_BLOCK':
        draft.blocks.splice(action.index, 1);
        break;

      case 'MOVE_BLOCK': {
        const { fromIndex, toIndex } = action;
        const [moved] = draft.blocks.splice(fromIndex, 1);
        if (moved) draft.blocks.splice(toIndex, 0, moved);
        break;
      }

      case 'SET_NESTED_BLOCKS': {
        // Navigate path to reach the right block, then set the field
        let target: WorkflowBlockDraft = draft.blocks[action.path[0]!]!;
        for (let i = 1; i < action.path.length; i++) {
          const container =
            (target as WorkflowBlockDraft).thenBlocks ??
            (target as WorkflowBlockDraft).elseBlocks ??
            (target as WorkflowBlockDraft).blocks ??
            [];
          target = container[action.path[i]!]!;
        }
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (target as any)[action.field] = action.blocks;
        break;
      }
    }
  });
}

export function useWorkflowDraft(initial?: WorkflowDraft) {
  const [draft, dispatch] = useReducer(draftReducer, initial ?? emptyDraft());
  const savedSnapshotRef = useRef<string>(serializeForComparison(initial ?? emptyDraft()));

  const isDirty = useMemo(
    () => serializeForComparison(draft) !== savedSnapshotRef.current,
    [draft],
  );

  const reset = useCallback((d: WorkflowDraft) => {
    dispatch({ type: 'RESET', draft: d });
    savedSnapshotRef.current = serializeForComparison(d);
  }, []);

  const markSaved = useCallback(() => {
    savedSnapshotRef.current = serializeForComparison(draft);
  }, [draft]);

  const patchDraft = useCallback((changes: Partial<WorkflowDraft>) => dispatch({ type: 'PATCH', changes }), []);

  const setTrigger = useCallback(
    (index: number, trigger: WorkflowTriggerDraft) => dispatch({ type: 'SET_TRIGGER', index, trigger }),
    [],
  );

  const addTrigger = useCallback(
    (type: WorkflowTriggerDraft['type'] = 'deviceStateChange') =>
      dispatch({
        type: 'ADD_TRIGGER',
        trigger: {
          _draftId: newUUID(),
          type,
          ...(type === 'schedule' ? { scheduleType: 'daily' } : {}),
          ...(type === 'sunEvent' ? { event: 'sunrise' as const, offsetMinutes: 0 } : {}),
        },
      }),
    [],
  );

  const removeTrigger = useCallback((index: number) => dispatch({ type: 'REMOVE_TRIGGER', index }), []);

  const setRootConditions = useCallback(
    (conditions: WorkflowConditionDraft[]) => dispatch({ type: 'SET_ROOT_CONDITIONS', conditions }),
    [],
  );

  const setCondition = useCallback(
    (path: number[], condition: WorkflowConditionDraft) => dispatch({ type: 'SET_CONDITION', path, condition }),
    [],
  );

  const setBlock = useCallback(
    (index: number, block: WorkflowBlockDraft) => dispatch({ type: 'SET_BLOCK', index, block }),
    [],
  );

  const addBlock = useCallback(
    (block: WorkflowBlockDraft) => dispatch({ type: 'ADD_BLOCK', block }),
    [],
  );

  const removeBlock = useCallback((index: number) => dispatch({ type: 'REMOVE_BLOCK', index }), []);

  const moveBlock = useCallback(
    (fromIndex: number, toIndex: number) => dispatch({ type: 'MOVE_BLOCK', fromIndex, toIndex }),
    [],
  );

  return {
    draft,
    isDirty,
    dispatch,
    reset,
    markSaved,
    patchDraft,
    setTrigger,
    addTrigger,
    removeTrigger,
    setRootConditions,
    setCondition,
    setBlock,
    addBlock,
    removeBlock,
    moveBlock,
  };
}
