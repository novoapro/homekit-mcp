import type {
  WorkflowDefinition,
  WorkflowTriggerDef,
  WorkflowConditionDef,
  WorkflowBlockDef,
} from '@/types/workflow-definition';
import type {
  WorkflowDraft,
  WorkflowTriggerDraft,
  WorkflowConditionDraft,
  WorkflowBlockDraft,
} from './workflow-editor-types';
import { newUUID } from './workflow-editor-types';

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
  blocks: WorkflowBlockDraft[],
  registry: RegistryLike,
): BlockInfo[] {
  const result: BlockInfo[] = [];
  let ordinal = 1;

  function recurse(blockList: WorkflowBlockDraft[]) {
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

export function newConditionLeaf(type: string): WorkflowConditionDraft {
  const base: WorkflowConditionDraft = { _draftId: newUUID(), type: type as WorkflowConditionDraft['type'] };
  switch (type) {
    case 'deviceState':
      base.comparison = { type: 'equals', value: true };
      break;
    case 'timeCondition':
      base.mode = 'between';
      base.startTime = { hour: 8, minute: 0 };
      base.endTime = { hour: 20, minute: 0 };
      break;
    case 'sceneActive':
      base.isActive = true;
      break;
    case 'blockResult':
      base.blockResultScope = { scope: 'any' };
      base.expectedStatus = 'success';
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

export function draftToPayload(draft: WorkflowDraft): Partial<WorkflowDefinition> {
  // Pass 1: convert blocks, building _draftId → blockId map
  const draftIdToBlockId = new Map<string, string>();
  const blocks = draft.blocks.map((b) => blockDraftToPayload(b, draftIdToBlockId));

  // Pass 2: convert conditions, rewriting blockResultScope.blockId from _draftId to new blockId
  const conditions = draft.conditions.length > 0
    ? draft.conditions.map(conditionDraftToPayload)
    : undefined;

  // Rewrite block result references in both root conditions and block-level conditions
  if (conditions) rewritePayloadConditionBlockRefs(conditions, draftIdToBlockId);
  rewritePayloadBlockConditionRefs(blocks, draftIdToBlockId);

  return {
    name: draft.name.trim(),
    description: draft.description.trim(),
    isEnabled: draft.isEnabled,
    continueOnError: draft.continueOnError,
    metadata: { tags: draft.tags } as WorkflowDefinition['metadata'],
    triggers: draft.triggers.map(triggerDraftToPayload),
    conditions,
    blocks,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rewritePayloadConditionBlockRefs(conditions: any[], map: Map<string, string>): void {
  for (const c of conditions) {
    if (c.type === 'blockResult' && c.blockResultScope?.scope === 'specific' && c.blockResultScope.blockId) {
      const mapped = map.get(c.blockResultScope.blockId);
      if (mapped) c.blockResultScope = { scope: 'specific', blockId: mapped };
    }
    if (c.conditions) rewritePayloadConditionBlockRefs(c.conditions, map);
    if (c.condition) rewritePayloadConditionBlockRefs([c.condition], map);
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rewritePayloadBlockConditionRefs(blocks: any[], map: Map<string, string>): void {
  for (const b of blocks) {
    if (b.condition) rewritePayloadConditionBlockRefs([b.condition], map);
    if (b.thenBlocks) rewritePayloadBlockConditionRefs(b.thenBlocks, map);
    if (b.elseBlocks) rewritePayloadBlockConditionRefs(b.elseBlocks, map);
    if (b.blocks) rewritePayloadBlockConditionRefs(b.blocks, map);
  }
}

function triggerDraftToPayload(t: WorkflowTriggerDraft): WorkflowTriggerDef {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const base: any = { type: t.type };
  if (t.name) base.name = t.name;
  if (t.retriggerPolicy) base.retriggerPolicy = t.retriggerPolicy;

  switch (t.type) {
    case 'deviceStateChange':
      base.deviceId = t.deviceId;
      base.serviceId = t.serviceId;
      base.characteristicId = t.characteristicId;
      base.condition = t.condition ?? { type: 'changed' };
      break;
    case 'schedule':
      base.scheduleType = buildScheduleType(t);
      break;
    case 'webhook':
      base.token = t.token;
      break;
    case 'sunEvent':
      base.event = t.event;
      base.offsetMinutes = t.offsetMinutes ?? 0;
      break;
    case 'workflow':
      break;
    case 'compound':
      base.operator = 'and';
      base.triggers = [];
      break;
  }
  return base as WorkflowTriggerDef;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function buildScheduleType(t: WorkflowTriggerDraft): any {
  switch (t.scheduleType) {
    case 'once':
      return { type: 'once', date: t.scheduleDate };
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

function conditionDraftToPayload(c: WorkflowConditionDraft): WorkflowConditionDef {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const base: any = { type: c.type };
  switch (c.type) {
    case 'deviceState':
      base.deviceId = c.deviceId;
      base.serviceId = c.serviceId;
      base.characteristicId = c.characteristicId;
      base.comparison = c.comparison ?? { type: 'equals', value: true };
      break;
    case 'timeCondition':
      base.mode = c.mode;
      if (c.startTime) base.startTime = c.startTime;
      if (c.endTime) base.endTime = c.endTime;
      break;
    case 'sceneActive':
      base.sceneId = c.sceneId;
      base.isActive = c.isActive ?? true;
      break;
    case 'blockResult':
      base.blockResultScope = c.blockResultScope ?? { scope: 'any' };
      base.expectedStatus = c.expectedStatus ?? 'success';
      break;
    case 'and':
    case 'or':
      base.conditions = (c.conditions ?? []).map(conditionDraftToPayload);
      break;
    case 'not':
      base.condition = c.condition ? conditionDraftToPayload(c.condition) : undefined;
      break;
  }
  return base as WorkflowConditionDef;
}

function blockDraftToPayload(b: WorkflowBlockDraft, idMap?: Map<string, string>): WorkflowBlockDef {
  const blockId = newUUID();
  if (idMap) idMap.set(b._draftId, blockId);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const base: any = { block: b.block, blockId, type: b.type };
  if (b.name) base.name = b.name;

  switch (b.type) {
    case 'controlDevice':
      base.deviceId = b.deviceId;
      base.serviceId = b.serviceId;
      base.characteristicId = b.characteristicId;
      base.value = b.value;
      break;
    case 'runScene':
      base.sceneId = b.sceneId;
      break;
    case 'webhook':
      base.url = b.url;
      base.method = b.method ?? 'POST';
      if (b.headers) base.headers = b.headers;
      if (b.body !== undefined) base.body = b.body;
      break;
    case 'log':
      base.message = b.message;
      break;
    case 'delay':
      base.seconds = b.seconds ?? 1;
      break;
    case 'waitForState':
      base.condition = b.condition ? conditionDraftToPayload(b.condition) : undefined;
      base.timeoutSeconds = b.timeoutSeconds ?? 30;
      break;
    case 'conditional':
      base.condition = b.condition ? conditionDraftToPayload(b.condition) : undefined;
      base.thenBlocks = (b.thenBlocks ?? []).map((child) => blockDraftToPayload(child, idMap));
      if (b.elseBlocks?.length) base.elseBlocks = b.elseBlocks.map((child) => blockDraftToPayload(child, idMap));
      break;
    case 'repeat':
      base.count = b.count ?? 1;
      base.blocks = (b.blocks ?? []).map((child) => blockDraftToPayload(child, idMap));
      if (b.delayBetweenSeconds != null) base.delayBetweenSeconds = b.delayBetweenSeconds;
      break;
    case 'repeatWhile':
      base.condition = b.condition ? conditionDraftToPayload(b.condition) : undefined;
      base.blocks = (b.blocks ?? []).map((child) => blockDraftToPayload(child, idMap));
      if (b.maxIterations != null) base.maxIterations = b.maxIterations;
      break;
    case 'group':
      base.label = b.label;
      base.blocks = (b.blocks ?? []).map((child) => blockDraftToPayload(child, idMap));
      break;
    case 'stop':
    case 'return':
      base.outcome = b.outcome ?? 'success';
      break;
    case 'executeWorkflow':
      base.targetWorkflowId = b.targetWorkflowId;
      base.executionMode = b.executionMode ?? 'async';
      break;
  }
  return base as WorkflowBlockDef;
}

// --- WorkflowDefinition → Draft ---

function migrateBlockCondition(condition: WorkflowConditionDraft): WorkflowConditionDraft {
  if (condition.type === 'and' || condition.type === 'or' || condition.type === 'not') {
    return condition;
  }
  return { _draftId: newUUID(), type: 'and', conditions: [condition] };
}

function migrateConditions(conditions: WorkflowConditionDraft[]): WorkflowConditionDraft[] {
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

export function definitionToDraft(wf: WorkflowDefinition): WorkflowDraft {
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

function rewriteDraftConditionBlockRefs(conditions: WorkflowConditionDraft[], map: Map<string, string>): void {
  for (const c of conditions) {
    if (c.type === 'blockResult' && c.blockResultScope?.scope === 'specific' && c.blockResultScope.blockId) {
      const mapped = map.get(c.blockResultScope.blockId);
      if (mapped) c.blockResultScope = { scope: 'specific', blockId: mapped };
    }
    if (c.conditions) rewriteDraftConditionBlockRefs(c.conditions, map);
    if (c.condition) rewriteDraftConditionBlockRefs([c.condition], map);
  }
}

function rewriteDraftBlockConditionRefs(blocks: WorkflowBlockDraft[], map: Map<string, string>): void {
  for (const b of blocks) {
    if (b.condition) rewriteDraftConditionBlockRefs([b.condition], map);
    if (b.thenBlocks) rewriteDraftBlockConditionRefs(b.thenBlocks, map);
    if (b.elseBlocks) rewriteDraftBlockConditionRefs(b.elseBlocks, map);
    if (b.blocks) rewriteDraftBlockConditionRefs(b.blocks, map);
  }
}

function triggerDefToDraft(t: WorkflowTriggerDef): WorkflowTriggerDraft {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const base: WorkflowTriggerDraft = { _draftId: newUUID(), type: t.type as any };
  if (t.name) base.name = t.name;
  if ('retriggerPolicy' in t && t.retriggerPolicy) base.retriggerPolicy = t.retriggerPolicy;

  switch (t.type) {
    case 'deviceStateChange':
      base.deviceId = t.deviceId;
      base.serviceId = t.serviceId;
      base.characteristicId = t.characteristicId;
      base.condition = t.condition;
      break;
    case 'schedule': {
      const st = t.scheduleType;
      if (st) {
        base.scheduleType = st.type;
        if (st.type === 'once') base.scheduleDate = st.date;
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

function conditionDefToDraft(c: WorkflowConditionDef): WorkflowConditionDraft {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const base: WorkflowConditionDraft = { _draftId: newUUID(), type: c.type as any };
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
    case 'sceneActive':
      base.sceneId = c.sceneId;
      base.isActive = c.isActive;
      break;
    case 'blockResult':
      base.blockResultScope = c.blockResultScope;
      base.expectedStatus = c.expectedStatus;
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

function blockDefToDraft(b: WorkflowBlockDef, blockIdMap?: Map<string, string>): WorkflowBlockDraft {
  const base: WorkflowBlockDraft = { _draftId: newUUID(), block: b.block, type: b.type };
  if (blockIdMap) blockIdMap.set(b.blockId, base._draftId);
  if (b.name) base.name = b.name;

  switch (b.type) {
    case 'controlDevice':
      base.deviceId = b.deviceId;
      base.serviceId = b.serviceId;
      base.characteristicId = b.characteristicId;
      base.value = b.value;
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
    case 'delay':
      base.seconds = b.seconds;
      break;
    case 'waitForState':
      base.condition = b.condition ? migrateBlockCondition(conditionDefToDraft(b.condition as WorkflowConditionDef)) : undefined;
      base.timeoutSeconds = b.timeoutSeconds;
      break;
    case 'conditional':
      base.condition = b.condition ? migrateBlockCondition(conditionDefToDraft(b.condition as WorkflowConditionDef)) : undefined;
      base.thenBlocks = (b.thenBlocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      base.elseBlocks = b.elseBlocks?.map((child) => blockDefToDraft(child, blockIdMap));
      break;
    case 'repeat':
      base.count = b.count;
      base.blocks = (b.blocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      base.delayBetweenSeconds = b.delayBetweenSeconds;
      break;
    case 'repeatWhile':
      base.condition = b.condition ? migrateBlockCondition(conditionDefToDraft(b.condition as WorkflowConditionDef)) : undefined;
      base.blocks = (b.blocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      base.maxIterations = b.maxIterations;
      break;
    case 'group':
      base.label = b.label;
      base.blocks = (b.blocks ?? []).map((child) => blockDefToDraft(child, blockIdMap));
      break;
    case 'stop':
    case 'return':
      base.outcome = b.outcome;
      break;
    case 'executeWorkflow':
      base.targetWorkflowId = b.targetWorkflowId;
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
};

const DAYS_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function formatAutoVal(val: any): string {
  if (val === undefined || val === null) return '?';
  if (val === true) return 'On';
  if (val === false) return 'Off';
  return String(val);
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

function fmtTime(t: { hour: number; minute: number } | undefined): string {
  if (!t) return '?';
  return `${pad2(t.hour)}:${pad2(t.minute)}`;
}

export function triggerAutoName(t: WorkflowTriggerDraft, registry: RegistryLike): string {
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
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const cond = t.condition as any;
      if (cond) {
        if (cond.type === 'changed') {
          parts.push('Changed');
        } else if (cond.type === 'transitioned') {
          const from = cond.from !== undefined ? formatAutoVal(cond.from) : 'any';
          parts.push(`${from} \u2192 ${formatAutoVal(cond.to)}`);
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
          return `Once on ${t.scheduleDate || '?'}`;
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
    case 'workflow':
      return 'Callable';
    default:
      return 'Trigger';
  }
}

export function conditionAutoName(c: WorkflowConditionDraft, registry: RegistryLike, allBlocks?: BlockInfo[]): string {
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
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const sym = COMPARISON_SYMBOLS[(c.comparison as any).type] || '=';
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        parts.push(`${sym} ${formatAutoVal((c.comparison as any).value)}`);
      }
      return parts.join(' ');
    }
    case 'timeCondition': {
      switch (c.mode) {
        case 'between':
          return `${fmtTime(c.startTime)}\u2013${fmtTime(c.endTime)}`;
        case 'before':
          return `Before ${fmtTime(c.endTime)}`;
        case 'after':
          return `After ${fmtTime(c.startTime)}`;
        case 'daytime':
          return 'Daytime';
        case 'nighttime':
          return 'Nighttime';
        default:
          return 'Time Window';
      }
    }
    case 'sceneActive': {
      if (!c.sceneId) return 'Scene Active';
      const scene = registry.lookupScene(c.sceneId);
      const name = scene?.name || c.sceneId;
      return c.isActive ? `Scene "${name}" active` : `Scene "${name}" not active`;
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
    case 'and': {
      const inner = (c.conditions || []).map((ch) => conditionAutoName(ch, registry, allBlocks));
      return inner.length ? inner.join(' AND ') : 'All match';
    }
    case 'or': {
      const inner = (c.conditions || []).map((ch) => conditionAutoName(ch, registry, allBlocks));
      return inner.length ? inner.join(' OR ') : 'Any match';
    }
    case 'not': {
      if (c.condition) return `NOT ${conditionAutoName(c.condition, registry, allBlocks)}`;
      return 'NOT ...';
    }
    default:
      return 'Condition';
  }
}

export function blockAutoName(b: WorkflowBlockDraft, registry: RegistryLike): string {
  switch (b.type) {
    case 'controlDevice': {
      if (!b.deviceId) return 'Control Device';
      const device = registry.lookupDevice(b.deviceId);
      const devName = device?.name || b.deviceId;
      if (!b.characteristicId) return `Set ${devName}`;
      const char = registry.lookupCharacteristic(b.deviceId, b.characteristicId);
      const charName = char?.name || b.characteristicId;
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
    case 'stop':
      return `Stop (${b.outcome || 'success'})`;
    case 'executeWorkflow': {
      const mode = b.executionMode === 'sync' ? 'sync' : 'async';
      return `Execute Workflow (${mode})`;
    }
    default:
      return b.type;
  }
}
