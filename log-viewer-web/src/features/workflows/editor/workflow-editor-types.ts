import type { TriggerCondition, ComparisonOperator } from '@/types/workflow-definition';

export function newUUID(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

// Draft types add _draftId for local tracking; stripped before API calls

export interface WorkflowTriggerDraft {
  _draftId: string;
  type: 'deviceStateChange' | 'schedule' | 'webhook' | 'workflow' | 'sunEvent' | 'compound';
  name?: string;
  // deviceStateChange
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  condition?: TriggerCondition;
  retriggerPolicy?: string;
  // schedule
  scheduleType?: string;
  scheduleDate?: string;
  scheduleTime?: { hour: number; minute: number };
  scheduleDays?: number[];
  scheduleIntervalSeconds?: number;
  // webhook
  token?: string;
  // sunEvent
  event?: 'sunrise' | 'sunset';
  offsetMinutes?: number;
}

export interface WorkflowConditionDraft {
  _draftId: string;
  type: 'deviceState' | 'timeCondition' | 'sceneActive' | 'blockResult' | 'and' | 'or' | 'not';
  // deviceState
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  comparison?: ComparisonOperator;
  // timeCondition
  mode?: string;
  startTime?: { hour: number; minute: number };
  endTime?: { hour: number; minute: number };
  // sceneActive
  sceneId?: string;
  isActive?: boolean;
  // blockResult
  blockResultScope?: { scope: string; blockId?: string };
  expectedStatus?: string;
  // and / or
  conditions?: WorkflowConditionDraft[];
  // not
  condition?: WorkflowConditionDraft;
}

export interface WorkflowBlockDraft {
  _draftId: string;
  block: 'action' | 'flowControl';
  type: string;
  name?: string;
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  value?: unknown;
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  body?: unknown;
  message?: string;
  sceneId?: string;
  seconds?: number;
  condition?: WorkflowConditionDraft;
  timeoutSeconds?: number;
  thenBlocks?: WorkflowBlockDraft[];
  elseBlocks?: WorkflowBlockDraft[];
  count?: number;
  blocks?: WorkflowBlockDraft[];
  delayBetweenSeconds?: number;
  maxIterations?: number;
  label?: string;
  outcome?: string;
  targetWorkflowId?: string;
  executionMode?: string;
}

export interface WorkflowDraft {
  name: string;
  description: string;
  isEnabled: boolean;
  continueOnError: boolean;
  tags: string[];
  triggers: WorkflowTriggerDraft[];
  conditions: WorkflowConditionDraft[];
  blocks: WorkflowBlockDraft[];
}

export function emptyDraft(): WorkflowDraft {
  return {
    name: '',
    description: '',
    isEnabled: true,
    continueOnError: false,
    tags: [],
    triggers: [],
    conditions: [],
    blocks: [],
  };
}
