// Trigger Conditions
export interface TriggerConditionChanged { type: 'changed'; }
export interface TriggerConditionEquals { type: 'equals'; value: unknown; }
export interface TriggerConditionNotEquals { type: 'notEquals'; value: unknown; }
export interface TriggerConditionTransitioned { type: 'transitioned'; from?: unknown; to?: unknown; }
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
export interface ComparisonIsEmpty { type: 'isEmpty'; }
export interface ComparisonIsNotEmpty { type: 'isNotEmpty'; }
export interface ComparisonContains { type: 'contains'; value: string; }

export type ComparisonOperator =
  | ComparisonEquals | ComparisonNotEquals
  | ComparisonGT | ComparisonLT | ComparisonGTE | ComparisonLTE
  | ComparisonIsEmpty | ComparisonIsNotEmpty | ComparisonContains;

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
  matchOperator: TriggerCondition;
  retriggerPolicy?: string;
  conditions?: AutomationConditionDef[];
}

export interface ScheduleTriggerDef {
  type: 'schedule';
  name?: string;
  scheduleType: ScheduleType;
  retriggerPolicy?: string;
  conditions?: AutomationConditionDef[];
}

export interface WebhookTriggerDef {
  type: 'webhook';
  name?: string;
  token: string;
  retriggerPolicy?: string;
  conditions?: AutomationConditionDef[];
}

export interface AutomationCallTriggerDef {
  type: 'automation';
  name?: string;
  retriggerPolicy?: string;
  conditions?: AutomationConditionDef[];
}

export interface SunEventTriggerDef {
  type: 'sunEvent';
  name?: string;
  event: 'sunrise' | 'sunset';
  offsetMinutes: number;
  retriggerPolicy?: string;
  conditions?: AutomationConditionDef[];
}

export type AutomationTriggerDef =
  | DeviceStateTriggerDef | ScheduleTriggerDef
  | WebhookTriggerDef | AutomationCallTriggerDef | SunEventTriggerDef;

// Automation Conditions
export interface DeviceStateConditionDef {
  type: 'deviceState';
  deviceId: string;
  serviceId?: string;
  characteristicId: string;
  comparison: ComparisonOperator;
}

// Time Point: either a fixed time or a named marker (midnight, noon, sunrise, sunset)
export type TimePointMarker = 'midnight' | 'noon' | 'sunrise' | 'sunset';
export type TimePointFixed = { type: 'fixed'; hour: number; minute: number };
export type TimePointMarkerDef = { type: 'marker'; marker: TimePointMarker };
export type TimePoint = TimePointFixed | TimePointMarkerDef;

export interface TimeConditionDef {
  type: 'timeCondition';
  mode: string;
  startTime?: TimePoint;
  endTime?: TimePoint;
}

export interface BlockResultConditionDef {
  type: 'blockResult';
  blockResultScope: { scope: string; blockId?: string };
  expectedStatus: string;
}

export interface LogicAndConditionDef {
  type: 'and';
  conditions: AutomationConditionDef[];
}

export interface LogicOrConditionDef {
  type: 'or';
  conditions: AutomationConditionDef[];
}

export interface LogicNotConditionDef {
  type: 'not';
  condition: AutomationConditionDef;
}

export interface EngineStateConditionDef {
  type: 'engineState';
  variableRef: { type: string; name?: string; id?: string };
  comparison: ComparisonOperator;
  compareToStateRef?: { type: string; name?: string; id?: string };
  dynamicDateValue?: string;
}

export type AutomationConditionDef =
  | DeviceStateConditionDef | TimeConditionDef
  | BlockResultConditionDef | EngineStateConditionDef
  | LogicAndConditionDef | LogicOrConditionDef | LogicNotConditionDef;

// Automation Blocks
export interface AutomationBlockDef {
  block: 'action' | 'flowControl';
  blockId: string;
  type: string;
  name?: string;
  deviceId?: string;
  serviceId?: string;
  characteristicId?: string;
  value?: unknown;
  valueRef?: { type: string; name?: string; id?: string };
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  body?: unknown;
  message?: string;
  sceneId?: string;
  seconds?: number;
  condition?: unknown;
  timeoutSeconds?: number;
  thenBlocks?: AutomationBlockDef[];
  elseBlocks?: AutomationBlockDef[];
  count?: number;
  blocks?: AutomationBlockDef[];
  delayBetweenSeconds?: number;
  maxIterations?: number;
  label?: string;
  outcome?: string;
  targetAutomationId?: string;
  executionMode?: string;
  operation?: unknown;
}

// Full Automation Definition
export interface AutomationDefinition {
  id: string;
  name: string;
  description?: string;
  isEnabled: boolean;
  triggers: AutomationTriggerDef[];
  conditions?: AutomationConditionDef[];
  blocks: AutomationBlockDef[];
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
