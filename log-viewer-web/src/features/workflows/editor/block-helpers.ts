import type { WorkflowBlockDraft, WorkflowConditionDraft } from './workflow-editor-types';
import { newUUID } from './workflow-editor-types';

function newConditionDraft(): WorkflowConditionDraft {
  return { _draftId: newUUID(), type: 'and', conditions: [] };
}

export function newBlockDraft(type: string): WorkflowBlockDraft {
  const base: WorkflowBlockDraft = {
    _draftId: newUUID(),
    block: ['controlDevice', 'runScene', 'webhook', 'log'].includes(type) ? 'action' : 'flowControl',
    type,
  };
  switch (type) {
    case 'controlDevice': base.value = true; break;
    case 'webhook': base.url = ''; base.method = 'POST'; break;
    case 'log': base.message = ''; break;
    case 'delay': base.seconds = 1; break;
    case 'waitForState': base.condition = newConditionDraft(); base.timeoutSeconds = 30; break;
    case 'conditional': base.condition = newConditionDraft(); base.thenBlocks = []; base.elseBlocks = []; break;
    case 'repeat': base.count = 1; base.blocks = []; break;
    case 'repeatWhile': base.condition = newConditionDraft(); base.blocks = []; base.maxIterations = 10; break;
    case 'group': base.label = ''; base.blocks = []; break;
    case 'stop': base.outcome = 'success'; break;
    case 'executeWorkflow': base.executionMode = 'async'; break;
  }
  return base;
}

export const BLOCK_ICONS: Record<string, string> = {
  controlDevice: 'house', runScene: 'sparkles', webhook: 'link', log: 'doc-text',
  delay: 'clock', waitForState: 'clock', conditional: 'arrow-triangle-branch',
  repeat: 'arrow-2-squarepath', repeatWhile: 'arrow-2-squarepath',
  group: 'folder', stop: 'xmark-circle', executeWorkflow: 'arrow-right-circle',
};

export const BLOCK_TYPE_LABELS: Record<string, string> = {
  controlDevice: 'Control Device', runScene: 'Run Scene', webhook: 'Webhook', log: 'Log',
  delay: 'Delay', waitForState: 'Wait for State', conditional: 'If / Else',
  repeat: 'Repeat', repeatWhile: 'Repeat While', group: 'Group', stop: 'Stop',
  executeWorkflow: 'Execute Workflow',
};

// --- Move to container ---

export interface MoveTarget {
  containerDraftId: string;
  field: string;        // 'thenBlocks' | 'elseBlocks' | 'blocks'
  description: string;  // e.g. "#3 If/Else → Then"
  icon: string;
}

export function containerTargets(
  excludeDraftId: string,
  siblings: WorkflowBlockDraft[],
  ordinalMap?: Map<string, number>,
): MoveTarget[] {
  const targets: MoveTarget[] = [];
  for (const block of siblings) {
    if (block._draftId === excludeDraftId) continue;
    const ord = ordinalMap?.get(block._draftId);
    const prefix = ord ? `#${ord} ` : '';
    const name = block.name || BLOCK_TYPE_LABELS[block.type] || block.type;
    const label = `${prefix}${name}`;

    const icon = BLOCK_ICONS[block.type] || 'square';
    switch (block.type) {
      case 'conditional':
        targets.push({ containerDraftId: block._draftId, field: 'thenBlocks', description: `${label} → Then`, icon });
        targets.push({ containerDraftId: block._draftId, field: 'elseBlocks', description: `${label} → Else`, icon });
        break;
      case 'repeat':
        targets.push({ containerDraftId: block._draftId, field: 'blocks', description: `${label} → Blocks`, icon });
        break;
      case 'repeatWhile':
        targets.push({ containerDraftId: block._draftId, field: 'blocks', description: `${label} → Blocks`, icon });
        break;
      case 'group':
        targets.push({ containerDraftId: block._draftId, field: 'blocks', description: `${label} → Blocks`, icon });
        break;
    }
  }
  return targets;
}

export function moveBlockToContainer(
  blockDraftId: string,
  targetContainerDraftId: string,
  targetField: string,
  blocks: WorkflowBlockDraft[],
): WorkflowBlockDraft[] {
  const sourceIndex = blocks.findIndex((b) => b._draftId === blockDraftId);
  if (sourceIndex < 0) return blocks;

  const result = [...blocks];
  const [moved] = result.splice(sourceIndex, 1);
  if (!moved) return blocks;

  const targetIndex = result.findIndex((b) => b._draftId === targetContainerDraftId);
  if (targetIndex < 0) {
    // Safety: put block back
    result.splice(Math.min(sourceIndex, result.length), 0, moved);
    return result;
  }

  const target = { ...result[targetIndex]! };
  if (targetField === 'thenBlocks') {
    target.thenBlocks = [...(target.thenBlocks ?? []), moved];
  } else if (targetField === 'elseBlocks') {
    target.elseBlocks = [...(target.elseBlocks ?? []), moved];
  } else {
    target.blocks = [...(target.blocks ?? []), moved];
  }
  result[targetIndex] = target;
  return result;
}

// --- Clone block ---

function regenerateConditionIds(condition: WorkflowConditionDraft): WorkflowConditionDraft {
  const clone: WorkflowConditionDraft = { ...condition, _draftId: newUUID() };
  if (clone.conditions) {
    clone.conditions = clone.conditions.map(regenerateConditionIds);
  }
  if (clone.condition) {
    clone.condition = regenerateConditionIds(clone.condition);
  }
  return clone;
}

export function cloneBlockDraft(block: WorkflowBlockDraft): WorkflowBlockDraft {
  const clone: WorkflowBlockDraft = JSON.parse(JSON.stringify(block));
  clone._draftId = newUUID();
  if (clone.name) clone.name = `${clone.name} (copy)`;
  if (clone.condition) clone.condition = regenerateConditionIds(clone.condition);
  if (clone.thenBlocks) clone.thenBlocks = clone.thenBlocks.map(cloneBlockDraft);
  if (clone.elseBlocks) clone.elseBlocks = clone.elseBlocks.map(cloneBlockDraft);
  if (clone.blocks) clone.blocks = clone.blocks.map(cloneBlockDraft);
  return clone;
}

export const HTTP_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

export const OUTCOMES = [
  { value: 'success', label: 'Success' },
  { value: 'failure', label: 'Failure' },
  { value: 'skipped', label: 'Skipped' },
];

export const EXEC_MODES = [
  { value: 'async', label: 'Async (fire & forget)' },
  { value: 'sync', label: 'Sync (wait for completion)' },
];
