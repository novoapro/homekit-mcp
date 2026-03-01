// Trigger Conditions
export interface TriggerConditionChanged { type: 'changed'; }
export interface TriggerConditionEquals { type: 'equals'; value: unknown; }
export interface TriggerConditionNotEquals { type: 'notEquals'; value: unknown; }
export interface TriggerConditionTransitioned { type: 'transitioned'; from?: unknown; to: unknown; }
export interface TriggerConditionGT { type: 'greaterThan'; value: number; }
export interface TriggerConditionLT { type: 'lessThan'; value: number; }
export interface TriggerConditionGTE { type: 'greaterThanOrEqual'; value: number; }
export interface TriggerConditionLTE { type: 'lessThanOrEqual'; value: number; }

export type TriggerCondition =
  | TriggerConditionChanged | TriggerConditionEquals | TriggerConditionNotEquals
  | TriggerConditionTransitioned
  | TriggerConditionGT | TriggerConditionLT | TriggerConditionGTE | TriggerConditionLTE;

// Comparison Operators
export interface ComparisonEquals { type: 'equals'; value: unknown; }
export interface ComparisonNotEquals { type: 'notEquals'; value: unknown; }
export interface ComparisonGT { type: 'greaterThan'; value: number; }
export interface ComparisonLT { type: 'lessThan'; value: number; }
export interface ComparisonGTE { type: 'greaterThanOrEqual'; value: number; }
export interface ComparisonLTE { type: 'lessThanOrEqual'; value: number; }

export type ComparisonOperator =
  | ComparisonEquals | ComparisonNotEquals
  | ComparisonGT | ComparisonLT | ComparisonGTE | ComparisonLTE;

// Schedules
export interface ScheduleTime { hour: number; minute: number; }
export interface ScheduleOnce { type: 'once'; date: string; }
export interface ScheduleDaily { type: 'daily'; time: ScheduleTime; }
export interface ScheduleWeekly { type: 'weekly'; time: ScheduleTime; days: number[]; }
export interface ScheduleInterval { type: 'interval'; seconds: number; }
export type ScheduleType = ScheduleOnce | ScheduleDaily | ScheduleWeekly | ScheduleInterval;

// Trigger Definitions
export interface DeviceStateTriggerDef {
  type: 'deviceStateChange';
  name?: string;
  deviceId: string;
  serviceId?: string;
  characteristicId: string;
  condition: TriggerCondition;
  retriggerPolicy?: string;
}

export interface CompoundTriggerDef {
  type: 'compound';
  name?: string;
  operator: string;
  triggers: WorkflowTriggerDef[];
  retriggerPolicy?: string;
}

export interface ScheduleTriggerDef {
  type: 'schedule';
  name?: string;
  scheduleType: ScheduleType;
  retriggerPolicy?: string;
}

export interface WebhookTriggerDef {
  type: 'webhook';
  name?: string;
  token: string;
  retriggerPolicy?: string;
}

export interface WorkflowCallTriggerDef {
  type: 'workflow';
  name?: string;
  retriggerPolicy?: string;
}

export interface SunEventTriggerDef {
  type: 'sunEvent';
  name?: string;
  event: 'sunrise' | 'sunset';
  offsetMinutes: number;
  retriggerPolicy?: string;
}

export type WorkflowTriggerDef =
  | DeviceStateTriggerDef | CompoundTriggerDef | ScheduleTriggerDef
  | WebhookTriggerDef | WorkflowCallTriggerDef | SunEventTriggerDef;

// Workflow Conditions
export interface DeviceStateConditionDef {
  type: 'deviceState';
  deviceId: string;
  serviceId?: string;
  characteristicId: string;
  comparison: ComparisonOperator;
}

export interface TimeConditionDef {
  type: 'timeCondition';
  mode: string;
  startTime?: { hour: number; minute: number };
  endTime?: { hour: number; minute: number };
}

export interface SceneActiveConditionDef {
  type: 'sceneActive';
  sceneId: string;
  isActive: boolean;
}

export interface BlockResultConditionDef {
  type: 'blockResult';
  blockResultScope: { scope: string; blockId?: string };
  expectedStatus: string;
}

export interface LogicAndConditionDef {
  type: 'and';
  conditions: WorkflowConditionDef[];
}

export interface LogicOrConditionDef {
  type: 'or';
  conditions: WorkflowConditionDef[];
}

export interface LogicNotConditionDef {
  type: 'not';
  condition: WorkflowConditionDef;
}

export type WorkflowConditionDef =
  | DeviceStateConditionDef | TimeConditionDef | SceneActiveConditionDef
  | BlockResultConditionDef | LogicAndConditionDef | LogicOrConditionDef | LogicNotConditionDef;

// Workflow Blocks
export interface WorkflowBlockDef {
  block: 'action' | 'flowControl';
  blockId: string;
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
  condition?: unknown;
  timeoutSeconds?: number;
  thenBlocks?: WorkflowBlockDef[];
  elseBlocks?: WorkflowBlockDef[];
  count?: number;
  blocks?: WorkflowBlockDef[];
  delayBetweenSeconds?: number;
  maxIterations?: number;
  label?: string;
  outcome?: string;
  targetWorkflowId?: string;
  executionMode?: string;
}

// Full Workflow Definition
export interface WorkflowDefinition {
  id: string;
  name: string;
  description?: string;
  isEnabled: boolean;
  triggers: WorkflowTriggerDef[];
  conditions?: WorkflowConditionDef[];
  blocks: WorkflowBlockDef[];
  continueOnError: boolean;
  retriggerPolicy: string;
  metadata: {
    createdBy?: string;
    tags?: string[];
    lastTriggeredAt?: string;
    totalExecutions: number;
    consecutiveFailures: number;
  };
  createdAt: string;
  updatedAt: string;
}
