import type {
  AutomationDefinition,
  AutomationTriggerDef,
  AutomationConditionDef,
  AutomationBlockDef,
  ScheduleType,
} from '@/types/automation-definition';
import type {
  AutomationDraft,
  AutomationTriggerDraft,
  AutomationConditionDraft,
  AutomationBlockDraft,
} from './automation-editor-types';
import { newUUID } from './automation-editor-types';

// --- Device registry interface (matches useDeviceRegistry) ---

interface RegistryLike {
  lookupDevice: (deviceId: string) => { name: string; room?: string } | undefined;
  lookupCharacteristic: (deviceId: string, charId: string) => { name: string } | undefined;
  lookupScene: (sceneId: string) => { name: string } | undefined;
}

// --- Block info collection (depth-first ordinals) ---

export interface BlockInfo {
  _draftId: string;
  ordinal: number;  // 1-based, global depth-first
  name: string;
  type: string;
}

export function collectAllBlockInfos(
  blocks: AutomationBlockDraft[],
  registry: RegistryLike,
): BlockInfo[] {
  const result: BlockInfo[] = [];
  let ordinal = 1;

  function recurse(blockList: AutomationBlockDraft[]) {
    for (const block of blockList) {
      result.push({
        _draftId: block._draftId,
        ordinal: ordinal++,
        name: block.name || blockAutoName(block, registry),
        type: block.type,
      });
      if (block.thenBlocks) recurse(block.thenBlocks);
      if (block.elseBlocks) recurse(block.elseBlocks);
      if (block.blocks) recurse(block.blocks);
    }
  }

  recurse(blocks);
  return result;
}

// --- Condition leaf factory ---

export function newConditionLeaf(type: string): AutomationConditionDraft {
  const base: AutomationConditionDraft = { _draftId: newUUID(), type: type as AutomationConditionDraft['type'] };
  switch (type) {
    case 'deviceState':
      base.comparison = { type: 'equals', value: true };
      break;
    case 'timeCondition':
      base.mode = 'timeRange';
      base.startTime = { type: 'fixed', hour: 8, minute: 0 };
      base.endTime = { type: 'fixed', hour: 20, minute: 0 };
      break;
    case 'blockResult':
      base.blockResultScope = { scope: 'any' };
      base.expectedStatus = 'success';
      break;
    case 'engineState':
      base.variableRef = { type: 'byName', name: '' };
      base.comparison = { type: 'equals', value: '' };
      base.stateCompareMode = 'literal';
      break;
    case 'and':
    case 'or':
      base.conditions = [];
      break;
    case 'not':
      base.condition = { _draftId: newUUID(), type: 'deviceState', comparison: { type: 'equals', value: true } };
      break;
  }
  return base;
}

// --- Shared value parsing ---

export function parseSmartValue(raw: string): string | number | boolean {
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  if (raw.trim() !== '' && !isNaN(+raw)) return +raw;
  return raw;
}

// --- Draft → Payload ---

export function draftToPayload(draft: AutomationDraft): Partial<AutomationDefinition> {
  // Pass 1: convert blocks, building _draftId → blockId map
  const draftIdToBlockId = new Map<string, string>();
  const blocks = draft.blocks.map((b) => blockDraftToPayload(b, draftIdToBlockId));

  // Pass 2: convert conditions, rewriting blockResultScope.blockId from _draftId to new blockId
  const conditions = draft.conditions.length > 0
    ? draft.conditions.map(conditionDraftToPayload)
    : [];

  // Rewrite block result references in both root conditions and block-level conditions
  if (conditions) rewritePayloadConditionBlockRefs(conditions, draftIdToBlockId);
  rewritePayloadBlockConditionRefs(blocks, draftIdToBlockId);

  return {
    name: draft.name.trim(),
    description: draft.description.trim(),
    isEnabled: draft.isEnabled,
    continueOnError: draft.continueOnError,
    metadata: { tags: draft.tags } as AutomationDefinition['metadata'],
    triggers: draft.triggers.map(triggerDraftToPayload),
    conditions,
    blocks,
  };
}

function rewritePayloadConditionBlockRefs(conditions: AutomationConditionDef[], map: Map<string, string>): void {
  for (const c of conditions) {
    if (c.type === 'blockResult' && c.blockResultScope?.scope === 'specific' && c.blockResultScope.blockId) {
      const mapped = map.get(c.blockResultScope.blockId);
      if (mapped) c.blockResultScope = { scope: 'specific', blockId: mapped };
    }
    if ('conditions' in c && c.conditions) rewritePayloadConditionBlockRefs(c.conditions, map);
    if ('condition' in c && c.condition) rewritePayloadConditionBlockRefs([c.condition as AutomationConditionDef], map);
  }
}

function rewritePayloadBlockConditionRefs(blocks: AutomationBlockDef[], map: Map<string, string>): void {
  for (const b of blocks) {
    if (b.condition) rewritePayloadConditionBlockRefs([b.condition as AutomationConditionDef], map);
    if (b.thenBlocks) rewritePayloadBlockConditionRefs(b.thenBlocks, map);
    if (b.elseBlocks) rewritePayloadBlockConditionRefs(b.elseBlocks, map);
    if (b.blocks) rewritePayloadBlockConditionRefs(b.blocks, map);
  }
}

function triggerDraftToPayload(t: AutomationTriggerDraft): AutomationTriggerDef {
  const shared: { name?: string; retriggerPolicy?: string; conditions?: AutomationConditionDef[] } = {};
  if (t.name) shared.name = t.name;
  if (t.retriggerPolicy) shared.retriggerPolicy = t.retriggerPolicy;
  if (t.conditions?.length) {
    shared.conditions = t.conditions.map(conditionDraftToPayload);
  }

  switch (t.type) {
    case 'deviceStateChange':
      return {
        ...shared,
        type: 'deviceStateChange',
        deviceId: t.deviceId!,
        serviceId: t.serviceId,
        characteristicId: t.characteristicId!,
        matchOperator: t.matchOperator ?? { type: 'changed' },
      };
    case 'schedule':
      return { ...shared, type: 'schedule', scheduleType: buildScheduleType(t) };
    case 'webhook':
      return { ...shared, type: 'webhook', token: t.token! };
    case 'sunEvent':
      return { ...shared, type: 'sunEvent', event: t.event!, offsetMinutes: t.offsetMinutes ?? 0 };
    case 'automation':
      return { ...shared, type: 'automation' };
    default:
      return { ...shared, type: t.type } as AutomationTriggerDef;
  }
}

function buildScheduleType(t: AutomationTriggerDraft): ScheduleType {
  switch (t.scheduleType) {
    case 'once': {
      const date = t.scheduleDate || new Date().toISOString().slice(0, 10);
      const time = t.scheduleTime ?? { hour: 8, minute: 0 };
      return { type: 'once', date: `${date}T${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}:00` };
    }
    case 'daily':
      return { type: 'daily', time: t.scheduleTime ?? { hour: 8, minute: 0 } };
    case 'weekly':
      return { type: 'weekly', time: t.scheduleTime ?? { hour: 8, minute: 0 }, days: t.scheduleDays ?? [] };
    case 'interval':
      return { type: 'interval', seconds: t.scheduleIntervalSeconds ?? 60 };
    default:
      return { type: 'daily', time: { hour: 8, minute: 0 } };
  }
}

function conditionDraftToPayload(c: AutomationConditionDraft): AutomationConditionDef {
  switch (c.type) {
    case 'deviceState':
      return {
        type: 'deviceState',
        deviceId: c.deviceId!,
        serviceId: c.serviceId,
        characteristicId: c.characteristicId!,
        comparison: c.comparison ?? { type: 'equals', value: true },
      };
    case 'timeCondition':
      return {
        type: 'timeCondition',
        mode: c.mode!,
        ...(c.startTime && { startTime: c.startTime }),
        ...(c.endTime && { endTime: c.endTime }),
      };
    case 'blockResult':
      return {
        type: 'blockResult',
        blockResultScope: c.blockResultScope ?? { scope: 'any' },
        expectedStatus: c.expectedStatus ?? 'success',
      };
    case 'and':
      return { type: 'and', conditions: (c.conditions ?? []).map(conditionDraftToPayload) };
    case 'or':
      return { type: 'or', conditions: (c.conditions ?? []).map(conditionDraftToPayload) };
    case 'not':
      return { type: 'not', condition: c.condition ? conditionDraftToPayload(c.condition) : undefined! };
    case 'engineState':
      return {
        type: 'engineState',
        variableRef: c.variableRef ?? { type: 'byName', name: '' },
        comparison: c.comparison ?? { type: 'equals', value: '' },
        ...(c.stateCompareMode === 'stateRef' && c.compareToStateRef && { compareToStateRef: c.compareToStateRef }),
        ...(c.dynamicDateValue && { dynamicDateValue: c.dynamicDateValue }),
      } as AutomationConditionDef;
  }
}

function blockDraftToPayload(b: AutomationBlockDraft, idMap?: Map<string, string>): AutomationBlockDef {
  const blockId = newUUID();
  if (idMap) idMap.set(b._draftId, blockId);
  const shared: Pick<AutomationBlockDef, 'block' | 'blockId' | 'type' | 'name'> = {
    block: b.block,
    blockId,
    type: b.type,
    ...(b.name && { name: b.name }),
  };

  switch (b.type) {
    case 'controlDevice':
      return {
        ...shared,
        deviceId: b.deviceId, serviceId: b.serviceId, characteristicId: b.characteristicId, value: b.value,
        ...(b.valueSource === 'global' && b.valueRef && { valueRef: b.valueRef }),
      };
    case 'runScene':
      return { ...shared, sceneId: b.sceneId };
    case 'webhook':
      return {
        ...shared,
        url: b.url,
        method: b.method ?? 'POST',
        ...(b.headers && { headers: b.headers }),
        ...(b.body !== undefined && { body: b.body }),
      };
    case 'log':
      return { ...shared, message: b.message };
    case 'stateVariable':
      return { ...shared, operation: b.operation };
    case 'delay':
      return { ...shared, seconds: b.seconds ?? 1 };
    case 'waitForState':
      return {
        ...shared,
        condition: b.condition ? conditionDraftToPayload(b.condition) : undefined,
        timeoutSeconds: b.timeoutSeconds ?? 30,
      };
    case 'conditional':
      return {
        ...shared,
        condition: b.condition ? conditionDraftToPayload(b.condition) : undefined,
        thenBlocks: (b.thenBlocks ?? []).map((child) => blockDraftToPayload(child, idMap)),
        ...(b.elseBlocks?.length && { elseBlocks: b.elseBlocks.map((child) => blockDraftToPayload(child, idMap)) }),
      };
    case 'repeat':
      return {
        ...shared,
        count: b.count ?? 1,
        blocks: (b.blocks ?? []).map((child) => blockDraftToPayload(child, idMap)),
        ...(b.delayBetweenSeconds != null && { delayBetweenSeconds: b.delayBetweenSeconds }),
      };
    case 'repeatWhile':
      return {
        ...shared,
        condition: b.condition ? conditionDraftToPayload(b.condition) : undefined,
        blocks: (b.blocks ?? []).map((child) => blockDraftToPayload(child, idMap)),
        ...(b.maxIterations != null && { maxIterations: b.maxIterations }),
      };
    case 'group':
      return { ...shared, label: b.label, blocks: (b.blocks ?? []).map((child) => blockDraftToPayload(child, idMap)) };
    case 'return':
      return { ...shared, outcome: b.outcome ?? 'success' };
    case 'executeAutomation':
      return { ...shared, targetAutomationId: b.targetAutomationId, executionMode: b.executionMode ?? 'async' };
    default:
      return shared;
  }
}

// --- AutomationDefinition → Draft ---

function migrateBlockCondition(condition: AutomationConditionDraft): AutomationConditionDraft {
  if (condition.type === 'and' || condition.type === 'or' || condition.type === 'not') {
    return condition;
  }
  return { _draftId: newUUID(), type: 'and', conditions: [condition] };
}

function migrateConditions(conditions: AutomationConditionDraft[]): AutomationConditionDraft[] {
  if (conditions.length === 0) return [];
  const first = conditions[0]!;
  if (
    conditions.length === 1 &&
    (first.type === 'and' ||
      first.type === 'or' ||
      (first.type === 'not' &&
        first.condition &&
        (first.condition.type === 'and' || first.condition.type === 'or')))
  ) {
    return conditions;
  }
  return [{ _draftId: newUUID(), type: 'and', conditions }];
}

export function definitionToDraft(wf: AutomationDefinition): AutomationDraft {
  // Pass 1: convert blocks, building blockId → _draftId map
  const blockIdMap = new Map<string, string>();
  const blocks = wf.blocks.map((b) => blockDefToDraft(b, blockIdMap));

  // Pass 2: convert conditions, then rewrite blockResultScope.blockId references
  const conditions = migrateConditions((wf.conditions ?? []).map(conditionDefToDraft));
  rewriteDraftConditionBlockRefs(conditions, blockIdMap);
  rewriteDraftBlockConditionRefs(blocks, blockIdMap);

  return {
    name: wf.name,
    description: wf.description ?? '',
    isEnabled: wf.isEnabled,
    continueOnError: wf.continueOnError,
    tags: wf.metadata?.tags ?? [],
    triggers: wf.triggers.map(triggerDefToDraft),
    conditions,
    blocks,
  };
}

function rewriteDraftConditionBlockRefs(conditions: AutomationConditionDraft[], map: Map<string, string>): void {
  for (const c of conditions) {
    if (c.type === 'blockResult' && c.blockResultScope?.scope === 'specific' && c.blockResultScope.blockId) {
      const mapped = map.get(c.blockResultScope.blockId);
      if (mapped) c.blockResultScope = { scope: 'specific', blockId: mapped };
    }
    if (c.conditions) rewriteDraftConditionBlockRefs(c.conditions, map);
    if (c.condition) rewriteDraftConditionBlockRefs([c.condition], map);
  }
}

function rewriteDraftBlockConditionRefs(blocks: AutomationBlockDraft[], map: Map<string, string>): void {
  for (const b of blocks) {
    if (b.condition) rewriteDraftConditionBlockRefs([b.condition], map);
    if (b.thenBlocks) rewriteDraftBlockConditionRefs(b.thenBlocks, map);
    if (b.elseBlocks) rewriteDraftBlockConditionRefs(b.elseBlocks, map);
    if (b.blocks) rewriteDraftBlockConditionRefs(b.blocks, map);
  }
}

function triggerDefToDraft(t: AutomationTriggerDef): AutomationTriggerDraft {
  const base: AutomationTriggerDraft = { _draftId: newUUID(), type: t.type };
  if (t.name) base.name = t.name;
  if ('retriggerPolicy' in t && t.retriggerPolicy) base.retriggerPolicy = t.retriggerPolicy;
  if (t.conditions?.length) {
    base.conditions = t.conditions.map(conditionDefToDraft);
  }

  switch (t.type) {
    case 'deviceStateChange':
      base.deviceId = t.deviceId;
      base.serviceId = t.serviceId;
      base.characteristicId = t.characteristicId;
      base.matchOperator = t.matchOperator;
      break;
    case 'schedule': {
      const st = t.scheduleType;
      if (st) {
        base.scheduleType = st.type;
        if (st.type === 'once') {
          base.scheduleDate = st.date.slice(0, 10);
          if (st.date.length > 10) {
            const timePart = st.date.slice(11);
            const [h, m] = timePart.split(':').map(Number);
            base.scheduleTime = { hour: h || 0, minute: m || 0 };
          }
        }
        if (st.type === 'daily') base.scheduleTime = st.time;
        if (st.type === 'weekly') {
          base.scheduleTime = st.time;
          base.scheduleDays = st.days;
        }
        if (st.type === 'interval') base.scheduleIntervalSeconds = st.seconds;
      }
      break;
    }
    case 'webhook':
      base.token = t.token;
      break;
    case 'sunEvent':
      base.event = t.event;
      base.offsetMinutes = t.offsetMinutes;
      break;
  }
  return base;
}

function conditionDefToDraft(c: AutomationConditionDef): AutomationConditionDraft {
  const base: AutomationConditionDraft = { _draftId: newUUID(), type: c.type };
  switch (c.type) {
    case 'deviceState':
      base.deviceId = c.deviceId;
      base.serviceId = c.serviceId;
      base.characteristicId = c.characteristicId;
      base.comparison = c.comparison;
      break;
    case 'timeCondition':
      base.mode = c.mode;
      base.startTime = c.startTime;
      base.endTime = c.endTime;
      break;
    case 'blockResult':
      base.blockResultScope = c.blockResultScope;
      base.expectedStatus = c.expectedStatus;
      break;
    case 'engineState':
      base.variableRef = c.variableRef;
      base.comparison = c.comparison;
      if (c.compareToStateRef) {
        base.compareToStateRef = c.compareToStateRef;
        base.stateCompareMode = 'stateRef';
      } else {
        base.stateCompareMode = 'literal';
      }
      if (c.dynamicDateValue) {
        base.dynamicDateValue = c.dynamicDateValue;
      }
      break;
    case 'and':
    case 'or':
      base.conditions = (c.conditions ?? []).map(conditionDefToDraft);
      break;
    case 'not':
      base.condition = c.condition ? conditionDefToDraft(c.condition) : undefined;
      break;
  }
  return base;
}

function blockDefToDraft(b: AutomationBlockDef, blockIdMap?: Map<string, string>): AutomationBlockDraft {
  const base: AutomationBlockDraft = { _draftId: newUUID(), block: b.block, type: b.type };
  if (blockIdMap) blockIdMap.set(b.blockId, base._draftId);
  if (b.name) base.name = b.name;

  switch (b.type) {
    case 'controlDevice':
      base.deviceId = b.deviceId;
      base.serviceId = b.serviceId;
      base.characteristicId = b.characteristicId;
      base.value = b.value;
      if (b.valueRef) {
        base.valueRef = b.valueRef;
        base.valueSource = 'global';
      } else {
        base.valueSource = 'local';
      }
      break;
    case 'runScene':
      base.sceneId = b.sceneId;
      break;
    case 'webhook':
      base.url = b.url;
      base.method = b.method;
      base.headers = b.headers;
      base.body = b.body;
      break;
    case 'log':
      base.message = b.message;
      break;
    case 'stateVariable':
      base.operation = b.operation as AutomationBlockDraft['operation'];
      break;
    case 'delay':
      base.seconds = b.seconds;
      break;
    case 'waitForState':
      base.condition = b.condition ? migrateBlockCondition(conditionDefToDraft(b.condition as AutomationConditionDef)) : undefined;
      base.timeoutSeconds = b.timeoutSeconds;
      break;
    case 'conditional':
      base.condition = b.condition ? migrateBlockCondition(conditionDefToDraft(b.condition as AutomationConditionDef)) : undefined;
      base.thenBlocks = (b.thenBlocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      base.elseBlocks = b.elseBlocks?.map((child) => blockDefToDraft(child, blockIdMap));
      break;
    case 'repeat':
      base.count = b.count;
      base.blocks = (b.blocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      base.delayBetweenSeconds = b.delayBetweenSeconds;
      break;
    case 'repeatWhile':
      base.condition = b.condition ? migrateBlockCondition(conditionDefToDraft(b.condition as AutomationConditionDef)) : undefined;
      base.blocks = (b.blocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      base.maxIterations = b.maxIterations;
      break;
    case 'group':
      base.label = b.label;
      base.blocks = (b.blocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      break;
    case 'return':
      base.outcome = b.outcome;
      break;
    case 'executeAutomation':
      base.targetAutomationId = b.targetAutomationId;
      base.executionMode = b.executionMode;
      break;
  }
  return base;
}

// --- Auto-Name Generation ---

const COMPARISON_SYMBOLS: Record<string, string> = {
  equals: '=',
  notEquals: '\u2260',
  greaterThan: '>',
  lessThan: '<',
  greaterThanOrEqual: '\u2265',
  lessThanOrEqual: '\u2264',
  isEmpty: 'is empty',
  isNotEmpty: 'is not empty',
  contains: 'contains',
};

const DAYS_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function formatAutoVal(val: unknown): string {
  if (val === undefined || val === null) return '?';
  if (val === true) return 'On';
  if (val === false) return 'Off';
  if (typeof val === 'string') {
    if (val === '__now__') return 'Now';
    // Relative datetime sentinels: __now-24h__, __now+7d__, etc.
    if (val.startsWith('__now') && val.endsWith('__')) {
      const desc = describeDateSentinel(val);
      if (desc) return desc;
    }
    // Try to detect and format ISO 8601 datetime strings
    if (/^\d{4}-\d{2}-\d{2}T/.test(val)) {
      try {
        const d = new Date(val);
        if (!isNaN(d.getTime())) return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
      } catch { /* fall through */ }
    }
  }
  return String(val);
}

function describeDateSentinel(val: string): string | undefined {
  if (val === '__now__') return 'Now';
  const inner = val.slice(5, -2); // e.g. "-24h" or "+7d"
  const m = inner.match(/^([+-]?)(\d+(?:\.\d+)?)([smhd])$/);
  if (!m) return undefined;
  const units: Record<string, string> = { s: 'second', m: 'minute', h: 'hour', d: 'day' };
  const amount = parseFloat(m[2]!);
  const unit = units[m[3]!] || m[3];
  const plural = amount === 1 ? '' : 's';
  return m[1] === '+' ? `${amount} ${unit}${plural} from now` : `${amount} ${unit}${plural} ago`;
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

const MARKER_LABELS: Record<string, string> = { midnight: 'Midnight', noon: 'Noon', sunrise: 'Sunrise', sunset: 'Sunset' };

function fmtTime(t: { type?: string; hour?: number; minute?: number; marker?: string } | undefined): string {
  if (!t) return '?';
  if (t.type === 'marker' && t.marker) return MARKER_LABELS[t.marker] || t.marker;
  const hour = t.hour ?? 0;
  const minute = t.minute ?? 0;
  const period = hour >= 12 ? 'PM' : 'AM';
  const h = hour % 12 || 12;
  return `${h}:${pad2(minute)} ${period}`;
}

export function triggerAutoName(t: AutomationTriggerDraft, registry: RegistryLike): string {
  switch (t.type) {
    case 'deviceStateChange': {
      if (!t.deviceId) return 'New Trigger';
      const device = registry.lookupDevice(t.deviceId);
      const parts: string[] = [];
      if (device?.room) parts.push(device.room);
      parts.push(device?.name || t.deviceId);
      if (t.characteristicId) {
        const char = registry.lookupCharacteristic(t.deviceId, t.characteristicId);
        parts.push(char?.name || t.characteristicId);
      }
      const cond = t.matchOperator;
      if (cond) {
        if (cond.type === 'changed') {
          parts.push('Changed');
        } else if (cond.type === 'transitioned') {
          const from = cond.from !== undefined ? formatAutoVal(cond.from) : 'any';
          const to = cond.to !== undefined ? formatAutoVal(cond.to) : 'any';
          parts.push(`${from} \u2192 ${to}`);
        } else {
          const sym = COMPARISON_SYMBOLS[cond.type] || cond.type;
          parts.push(`${sym} ${formatAutoVal(cond.value)}`);
        }
      }
      return parts.join(' ');
    }
    case 'schedule': {
      switch (t.scheduleType) {
        case 'once':
          return `Once on ${t.scheduleDate || '?'} at ${fmtTime(t.scheduleTime)}`;
        case 'daily':
          return `Daily at ${fmtTime(t.scheduleTime)}`;
        case 'weekly': {
          const days = (t.scheduleDays || []).map((d) => DAYS_SHORT[d] || '?').join(', ');
          return `Weekly at ${fmtTime(t.scheduleTime)} ${days}`;
        }
        case 'interval':
          return `Every ${t.scheduleIntervalSeconds || 60}s`;
        default:
          return 'Schedule';
      }
    }
    case 'sunEvent': {
      const event = t.event === 'sunset' ? 'Sunset' : 'Sunrise';
      const offset = t.offsetMinutes ?? 0;
      if (offset === 0) return `At ${event}`;
      if (offset > 0) return `${offset}min after ${event}`;
      return `${Math.abs(offset)}min before ${event}`;
    }
    case 'webhook':
      return 'Webhook Trigger';
    case 'automation':
      return 'Callable';
    default:
      return 'Trigger';
  }
}

export function conditionAutoName(c: AutomationConditionDraft, registry: RegistryLike, allBlocks?: BlockInfo[], stateNames?: StateDisplayNames): string {
  switch (c.type) {
    case 'deviceState': {
      if (!c.deviceId) return 'Device State';
      const device = registry.lookupDevice(c.deviceId);
      const parts: string[] = [];
      parts.push(device?.name || c.deviceId);
      if (c.characteristicId) {
        const char = registry.lookupCharacteristic(c.deviceId, c.characteristicId);
        parts.push(char?.name || c.characteristicId);
      }
      if (c.comparison) {
        const sym = COMPARISON_SYMBOLS[c.comparison.type] || '=';
        parts.push(`${sym} ${formatAutoVal('value' in c.comparison ? c.comparison.value : undefined)}`);
      }
      return parts.join(' ');
    }
    case 'timeCondition': {
      switch (c.mode) {
        case 'timeRange':
          return `${fmtTime(c.startTime)}\u2013${fmtTime(c.endTime)}`;
        case 'beforeSunrise':
          return 'Before Sunrise';
        case 'afterSunrise':
          return 'After Sunrise';
        case 'beforeSunset':
          return 'Before Sunset';
        case 'afterSunset':
          return 'After Sunset';
        case 'daytime':
          return 'Daytime';
        case 'nighttime':
          return 'Nighttime';
        default:
          return 'Time Window';
      }
    }
    case 'blockResult': {
      const scope = c.blockResultScope?.scope || 'any';
      const status = c.expectedStatus || 'success';
      if (scope === 'specific' && c.blockResultScope?.blockId) {
        const block = allBlocks?.find((b) => b._draftId === c.blockResultScope!.blockId);
        if (block) return `#${block.ordinal} ${block.name} = ${status}`;
        return `Block "${c.blockResultScope.blockId}" = ${status}`;
      }
      return `Any block = ${status}`;
    }
    case 'engineState': {
      const varKey = c.variableRef?.name || 'state';
      const varName = (stateNames && varKey in stateNames) ? stateNames[varKey] : varKey;
      if (c.comparison) {
        const sym = COMPARISON_SYMBOLS[c.comparison.type] || '=';
        return `${varName} ${sym} ${formatAutoVal('value' in c.comparison ? c.comparison.value : undefined)}`;
      }
      return `State: ${varName}`;
    }
    case 'and': {
      const inner = (c.conditions || []).map((ch) => conditionAutoName(ch, registry, allBlocks, stateNames));
      return inner.length ? inner.join(' AND ') : 'All match';
    }
    case 'or': {
      const inner = (c.conditions || []).map((ch) => conditionAutoName(ch, registry, allBlocks, stateNames));
      return inner.length ? inner.join(' OR ') : 'Any match';
    }
    case 'not': {
      if (c.condition) return `NOT ${conditionAutoName(c.condition, registry, allBlocks, stateNames)}`;
      return 'NOT ...';
    }
    default:
      return 'Condition';
  }
}

const ALL_OP_LABELS: Record<string, string> = {
  remove: 'Remove', toggle: 'Toggle', addState: 'Add State', subtractState: 'Subtract State',
  andState: 'AND State', orState: 'OR State', notState: 'NOT State', setFromCharacteristic: 'Set from Device',
};

/** Map from global value name (key) to display label. */
export type StateDisplayNames = Record<string, string>;

export function blockAutoName(b: AutomationBlockDraft, registry: RegistryLike, stateNames?: StateDisplayNames): string {
  switch (b.type) {
    case 'controlDevice': {
      if (!b.deviceId) return 'Control Device';
      const device = registry.lookupDevice(b.deviceId);
      const devName = device?.name || b.deviceId;
      if (!b.characteristicId) return `Set ${devName}`;
      const char = registry.lookupCharacteristic(b.deviceId, b.characteristicId);
      const charName = char?.name || b.characteristicId;
      if (b.valueSource === 'global' && b.valueRef?.name) {
        const refLabel = stateNames?.[b.valueRef.name] || b.valueRef.name;
        return `Set ${devName} ${charName} = ${refLabel} (Global)`;
      }
      const valStr = b.value !== undefined ? ` = ${formatAutoVal(b.value)}` : '';
      return `Set ${devName} ${charName}${valStr}`;
    }
    case 'runScene': {
      if (!b.sceneId) return 'Run Scene';
      const scene = registry.lookupScene(b.sceneId);
      return `Run "${scene?.name || b.sceneId}"`;
    }
    case 'webhook': {
      if (!b.url) return 'Webhook';
      try {
        const host = new URL(b.url).host;
        return `${(b.method || 'POST').toUpperCase()} ${host}`;
      } catch {
        return `${(b.method || 'POST').toUpperCase()} ${b.url.substring(0, 30)}`;
      }
    }
    case 'log':
      return b.message ? `Log: ${b.message.substring(0, 30)}` : 'Log Message';
    case 'stateVariable': {
      const op = b.operation;
      if (!op) return 'Global Value';
      const varName = op.variableRef?.name;
      const varDisplayName = varName ? (stateNames?.[varName] || varName) : undefined;
      const varLabel = varDisplayName ? ` '${varDisplayName}'` : '';
      switch (op.operation) {
        case 'set':
          return `Set${varLabel} = ${formatAutoVal(op.value)}`;
        case 'setToNow':
          return `Set${varLabel} to Now`;
        case 'addTime':
          return `Add ${op.amount ?? 1} ${op.unit || 'minutes'} to${varLabel}`;
        case 'subtractTime':
          return `Subtract ${op.amount ?? 1} ${op.unit || 'minutes'} from${varLabel}`;
        case 'increment':
          return `Increment${varLabel} by ${op.by ?? 1}`;
        case 'decrement':
          return `Decrement${varLabel} by ${op.by ?? 1}`;
        case 'multiply':
          return `Multiply${varLabel} by ${op.by ?? 1}`;
        case 'create':
          return `Create '${op.name || '?'}' (${op.variableType || 'number'})`;
        default: {
          const label = ALL_OP_LABELS[op.operation] || op.operation;
          return `${label}${varLabel}`;
        }
      }
    }
    case 'delay':
      return `Delay ${b.seconds ?? 1}s`;
    case 'waitForState': {
      if (!b.condition) return 'Wait for State';
      const desc = conditionAutoName(b.condition, registry);
      return `Wait ${desc}`;
    }
    case 'conditional': {
      if (!b.condition) return 'If / Else';
      return `If ${conditionAutoName(b.condition, registry)}`;
    }
    case 'repeat':
      return `Repeat ${b.count ?? 1}\u00D7`;
    case 'repeatWhile': {
      if (!b.condition) return 'Repeat While';
      return `While ${conditionAutoName(b.condition, registry)}`;
    }
    case 'group':
      return b.label || 'Group';
    case 'return':
      return `Return (${b.outcome || 'success'})`;
    case 'executeAutomation': {
      const mode = b.executionMode === 'sync' ? 'sync' : 'async';
      return `Execute Automation (${mode})`;
    }
    default:
      return b.type;
  }
}
