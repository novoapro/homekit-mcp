import type { AutomationDraft, AutomationBlockDraft } from './automation-editor-types';

export function validateDraft(draft: AutomationDraft): string[] {
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

  // Validate execution guards — if present, must have actual conditions
  for (const cond of draft.conditions) {
    if (!isConditionComplete(cond)) {
      errors.push('Execution guard has no conditions — add conditions or remove it');
      break;
    }
  }

  // Validate trigger guard conditions
  for (const trigger of draft.triggers) {
    if (trigger.conditions?.length) {
      for (const cond of trigger.conditions) {
        if (!isConditionComplete(cond)) {
          errors.push(`Trigger guard for "${trigger.name || trigger.type}" has no conditions — add conditions or remove it`);
          break;
        }
      }
    }
  }

  validateBlocksConditions(draft.blocks, errors);

  if (hasBlockResultConditions(draft) && !draft.continueOnError) {
    errors.push('Block Result conditions require "Continue on Error" to be enabled');
  }

  return errors;
}

function validateBlocksConditions(blocks: AutomationBlockDraft[], errors: string[]): void {
  for (const block of blocks) {
    if (block.type === 'conditional' && !isConditionComplete(block.condition)) {
      errors.push('Conditional block requires a condition');
    }
    if ((block.type === 'waitForCondition' || block.type === 'loop') && block.condition && !isConditionComplete(block.condition)) {
      const label = block.type === 'waitForCondition' ? 'Wait block' : 'Loop block';
      errors.push(`${label} condition is empty — add conditions or remove it`);
    }
    if (block.thenBlocks?.length) validateBlocksConditions(block.thenBlocks, errors);
    if (block.elseBlocks?.length) validateBlocksConditions(block.elseBlocks, errors);
    if (block.blocks?.length) validateBlocksConditions(block.blocks, errors);
  }
}

function isConditionComplete(condition: AutomationBlockDraft['condition']): boolean {
  if (!condition) return false;
  switch (condition.type) {
    case 'deviceState':
      return !!(condition.deviceId && condition.characteristicId);
    case 'timeCondition':
      return !!condition.mode;
    case 'blockResult':
      return !!(condition.blockResultScope && condition.expectedStatus);
    case 'engineState':
      return !!(condition.variableRef?.name || condition.variableRef?.id);
    case 'and':
    case 'or':
      return (condition.conditions?.length ?? 0) > 0 && condition.conditions!.every(isConditionComplete);
    case 'not':
      return isConditionComplete(condition.condition);
    default:
      return false;
  }
}

function hasBlockResultConditions(draft: AutomationDraft): boolean {
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
