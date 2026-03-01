import type { WorkflowDraft } from './workflow-editor-types';

export function validateDraft(draft: WorkflowDraft): string[] {
  const errors: string[] = [];

  if (!draft.name.trim()) {
    errors.push('Name is required');
  }

  if (draft.triggers.length === 0) {
    errors.push('At least one trigger is required');
  }

  if (draft.blocks.length === 0) {
    errors.push('At least one block is required');
  }

  for (const trigger of draft.triggers) {
    if (trigger.type === 'deviceStateChange') {
      if (!trigger.deviceId) errors.push('Device trigger: a device is required');
      if (!trigger.characteristicId) errors.push('Device trigger: a characteristic is required');
    }
    if (trigger.type === 'schedule' && trigger.scheduleType === 'weekly') {
      if (!trigger.scheduleDays?.length) errors.push('Weekly schedule: select at least one day');
    }
  }

  if (hasBlockResultConditions(draft) && !draft.continueOnError) {
    errors.push('Block Result conditions require "Continue on Error" to be enabled');
  }

  return errors;
}

function hasBlockResultConditions(draft: WorkflowDraft): boolean {
  return draft.blocks.some((b) => blockHasBlockResult(b));
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function blockHasBlockResult(block: any): boolean {
  if (block.type === 'conditional') {
    const cond = block.condition;
    if (cond && conditionHasBlockResult(cond)) return true;
  }
  if (block.thenBlocks?.some(blockHasBlockResult)) return true;
  if (block.elseBlocks?.some(blockHasBlockResult)) return true;
  if (block.blocks?.some(blockHasBlockResult)) return true;
  return false;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function conditionHasBlockResult(cond: any): boolean {
  if (cond?.type === 'blockResult') return true;
  if (cond?.conditions?.some(conditionHasBlockResult)) return true;
  if (cond?.condition && conditionHasBlockResult(cond.condition)) return true;
  return false;
}
