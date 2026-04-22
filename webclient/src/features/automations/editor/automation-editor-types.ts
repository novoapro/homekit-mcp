import type { TriggerCondition, ComparisonOperator, TimePoint } from '@/types/automation-definition';

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

export interface AutomationTriggerDraft {
  _draftId: string;
  type: 'deviceStateChange' | 'schedule' | 'webhook' | 'automation' | 'sunEvent';
  name?: string;
  // deviceStateChange
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  matchOperator?: TriggerCondition;
  retriggerPolicy?: string;
  // per-trigger guard conditions
  conditions?: AutomationConditionDraft[];
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

export interface AutomationConditionDraft {
  _draftId: string;
  type: 'deviceState' | 'timeCondition' | 'blockResult' | 'engineState' | 'and' | 'or' | 'not';
  // deviceState
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  comparison?: ComparisonOperator;
  // timeCondition
  mode?: string;
  startTime?: TimePoint;
  endTime?: TimePoint;
  // blockResult
  blockResultScope?: { scope: string; blockId?: string };
  expectedStatus?: string;
  // engineState
  variableRef?: { type: string; name?: string; id?: string };
  compareToStateRef?: { type: string; name?: string; id?: string };
  stateCompareMode?: 'literal' | 'stateRef';
  dynamicDateValue?: string;
  // and / or
  conditions?: AutomationConditionDraft[];
  // not
  condition?: AutomationConditionDraft;
}

export interface AutomationBlockDraft {
  _draftId: string;
  block: 'action' | 'flowControl';
  type: string;
  name?: string;
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  value?: unknown;
  valueRef?: { type: string; name?: string; id?: string };
  valueSource?: 'local' | 'global';
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  body?: unknown;
  message?: string;
  sceneId?: string;
  seconds?: number;
  secondsRef?: { type: string; name?: string; id?: string };
  secondsSource?: 'local' | 'global';
  condition?: AutomationConditionDraft;
  timeoutSeconds?: number;
  thenBlocks?: AutomationBlockDraft[];
  elseBlocks?: AutomationBlockDraft[];
  count?: number;
  blocks?: AutomationBlockDraft[];
  delayBetweenSeconds?: number;
  maxIterations?: number;
  label?: string;
  outcome?: string;
  targetAutomationId?: string;
  executionMode?: string;
  // timedControl
  durationSeconds?: number;
  durationRef?: { type: string; name?: string; id?: string };
  durationSource?: 'local' | 'global';
  changes?: TimedChangeDraft[];
  // stateVariable
  operation?: {
    operation: string;
    name?: string;
    variableType?: string;
    initialValue?: unknown;
    variableRef?: { type: string; name?: string; id?: string };
    value?: unknown;
    by?: number;
    otherRef?: { type: string; name?: string; id?: string };
    // datetime arithmetic (addTime, subtractTime)
    amount?: number;
    unit?: string;
    // setFromCharacteristic
    deviceId?: string;
    characteristicId?: string;
    serviceId?: string;
  };
}

export interface TimedChangeDraft {
  _draftId: string;
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  value?: unknown;
  valueRef?: { type: string; name?: string; id?: string };
  valueSource?: 'local' | 'global';
}

export type AutomationLoggingMode = 'off' | 'executed' | 'all';

export interface AutomationDraft {
  name: string;
  description: string;
  isEnabled: boolean;
  continueOnError: boolean;
  loggingOverride?: AutomationLoggingMode;
  tags: string[];
  triggers: AutomationTriggerDraft[];
  conditions: AutomationConditionDraft[];
  blocks: AutomationBlockDraft[];
}

export function emptyDraft(): AutomationDraft {
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
