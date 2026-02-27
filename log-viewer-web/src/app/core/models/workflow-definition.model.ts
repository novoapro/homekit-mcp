// Workflow Definition models — matches the full JSON structure from GET /workflows/:id

// --- Trigger Condition (discriminated via `type`) ---
export interface TriggerConditionChanged { type: 'changed'; }
export interface TriggerConditionEquals { type: 'equals'; value: any; }
export interface TriggerConditionNotEquals { type: 'notEquals'; value: any; }
export interface TriggerConditionTransitioned { type: 'transitioned'; from?: any; to: any; }
export interface TriggerConditionGT { type: 'greaterThan'; value: number; }
export interface TriggerConditionLT { type: 'lessThan'; value: number; }
export interface TriggerConditionGTE { type: 'greaterThanOrEqual'; value: number; }
export interface TriggerConditionLTE { type: 'lessThanOrEqual'; value: number; }

export type TriggerCondition =
  | TriggerConditionChanged | TriggerConditionEquals | TriggerConditionNotEquals
  | TriggerConditionTransitioned
  | TriggerConditionGT | TriggerConditionLT | TriggerConditionGTE | TriggerConditionLTE;

// --- Comparison Operator (used in conditions & waitForState) ---
export interface ComparisonEquals { type: 'equals'; value: any; }
export interface ComparisonNotEquals { type: 'notEquals'; value: any; }
export interface ComparisonGT { type: 'greaterThan'; value: number; }
export interface ComparisonLT { type: 'lessThan'; value: number; }
export interface ComparisonGTE { type: 'greaterThanOrEqual'; value: number; }
export interface ComparisonLTE { type: 'lessThanOrEqual'; value: number; }

export type ComparisonOperator =
  | ComparisonEquals | ComparisonNotEquals
  | ComparisonGT | ComparisonLT | ComparisonGTE | ComparisonLTE;

// --- Schedule ---
export interface ScheduleTime { hour: number; minute: number; }

export interface ScheduleOnce { type: 'once'; date: string; }
export interface ScheduleDaily { type: 'daily'; time: ScheduleTime; }
export interface ScheduleWeekly { type: 'weekly'; time: ScheduleTime; days: number[]; }
export interface ScheduleInterval { type: 'interval'; seconds: number; }

export type ScheduleType = ScheduleOnce | ScheduleDaily | ScheduleWeekly | ScheduleInterval;

// --- Triggers (discriminated via `type`) ---
export interface DeviceStateTriggerDef {
  type: 'deviceStateChange';
  name?: string;
  deviceId: string;
  serviceId?: string;
  characteristicType: string;
  condition: TriggerCondition;
  deviceName?: string;
  roomName?: string;
  serviceType?: string;
  retriggerPolicy?: string;
}

export interface CompoundTriggerDef {
  type: 'compound';
  name?: string;
  operator: string; // 'and' | 'or'
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

// --- Workflow Conditions (discriminated via `type`) ---
export interface DeviceStateConditionDef {
  type: 'deviceState';
  deviceId: string;
  serviceId?: string;
  characteristicType: string;
  comparison: ComparisonOperator;
  deviceName?: string;
  roomName?: string;
  serviceType?: string;
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
  sceneName?: string;
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

// --- Workflow Blocks (discriminated via `block` + `type`) ---
export interface WorkflowBlockDef {
  block: 'action' | 'flowControl';
  blockId: string;
  type: string;
  name?: string;
  // controlDevice
  deviceId?: string;
  serviceId?: string;
  characteristicType?: string;
  value?: any;
  deviceName?: string;
  roomName?: string;
  serviceType?: string;
  // webhook
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  body?: any;
  // log
  message?: string;
  // runScene
  sceneId?: string;
  sceneName?: string;
  // delay
  seconds?: number;
  // waitForState
  condition?: any;
  timeoutSeconds?: number;
  // conditional
  thenBlocks?: WorkflowBlockDef[];
  elseBlocks?: WorkflowBlockDef[];
  // repeat
  count?: number;
  blocks?: WorkflowBlockDef[];
  delayBetweenSeconds?: number;
  // repeatWhile
  maxIterations?: number;
  // group
  label?: string;
  // stop (serialized as "return")
  outcome?: string;
  // executeWorkflow
  targetWorkflowId?: string;
  executionMode?: string;
}

// --- Full Workflow Definition ---
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
