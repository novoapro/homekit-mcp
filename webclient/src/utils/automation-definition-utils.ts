import type { TriggerCondition, ComparisonOperator, ScheduleType } from '@/types/automation-definition';

function formatValue(val: unknown): string {
  if (val === undefined || val === null) return '?';
  if (typeof val === 'boolean') return val ? 'On' : 'Off';
  if (typeof val === 'object' && val !== null && 'value' in val) return formatValue((val as { value: unknown }).value);
  return String(val);
}

export function formatTriggerCondition(c: TriggerCondition): string {
  switch (c.type) {
    case 'changed': return 'changes';
    case 'equals': return `equals ${formatValue(c.value)}`;
    case 'notEquals': return `not equal to ${formatValue(c.value)}`;
    case 'transitioned': {
      const from = c.from !== undefined ? formatValue(c.from) : 'any';
      const to = c.to !== undefined ? formatValue(c.to) : 'any';
      return `transitions from ${from} to ${to}`;
    }
    case 'greaterThan': return `> ${c.value}`;
    case 'lessThan': return `< ${c.value}`;
    case 'greaterThanOrEqual': return `>= ${c.value}`;
    case 'lessThanOrEqual': return `<= ${c.value}`;
    default: return 'unknown';
  }
}

export function formatComparisonOperator(op: ComparisonOperator): string {
  switch (op.type) {
    case 'equals': return `equals ${formatValue(op.value)}`;
    case 'notEquals': return `not equal to ${formatValue(op.value)}`;
    case 'greaterThan': return `> ${op.value}`;
    case 'lessThan': return `< ${op.value}`;
    case 'greaterThanOrEqual': return `>= ${op.value}`;
    case 'lessThanOrEqual': return `<= ${op.value}`;
    case 'isEmpty': return 'is empty';
    case 'isNotEmpty': return 'is not empty';
    case 'contains': return `contains "${(op as { value: string }).value}"`;
    default: return 'unknown';
  }
}

function formatTime(hour: number, minute: number): string {
  const ampm = hour < 12 ? 'AM' : 'PM';
  const h = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  return `${h}:${String(minute).padStart(2, '0')} ${ampm}`;
}

export function formatScheduleType(s: ScheduleType): string {
  switch (s.type) {
    case 'once': {
      const d = new Date(s.date);
      return `Once on ${d.toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })}`;
    }
    case 'daily':
      return `Daily at ${formatTime(s.time.hour, s.time.minute)}`;
    case 'weekly': {
      const dayNames = ['', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      const days = (s.days || []).sort().map(d => dayNames[d] || `Day ${d}`).join(', ');
      return `Weekly on ${days} at ${formatTime(s.time.hour, s.time.minute)}`;
    }
    case 'interval': {
      if (s.seconds >= 3600) return `Every ${(s.seconds / 3600).toFixed(1).replace(/\.0$/, '')} hour(s)`;
      if (s.seconds >= 60) return `Every ${Math.round(s.seconds / 60)} minute(s)`;
      return `Every ${s.seconds} second(s)`;
    }
    default: return 'Unknown schedule';
  }
}

function formatTimePoint(tp: { type?: string; hour?: number; minute?: number; marker?: string } | undefined): string {
  if (!tp) return '?';
  if (tp.type === 'marker' && tp.marker) {
    const labels: Record<string, string> = { midnight: 'Midnight', noon: 'Noon', sunrise: 'Sunrise', sunset: 'Sunset' };
    return labels[tp.marker] || tp.marker;
  }
  return formatTime(tp.hour ?? 0, tp.minute ?? 0);
}

export function formatTimeConditionMode(mode: string, startTime?: { type?: string; hour?: number; minute?: number; marker?: string }, endTime?: { type?: string; hour?: number; minute?: number; marker?: string }): string {
  switch (mode) {
    case 'beforeSunrise': return 'Before Sunrise';
    case 'afterSunrise': return 'After Sunrise';
    case 'beforeSunset': return 'Before Sunset';
    case 'afterSunset': return 'After Sunset';
    case 'daytime': return 'Daytime';
    case 'nighttime': return 'Nighttime';
    case 'timeRange': {
      return `${formatTimePoint(startTime)} – ${formatTimePoint(endTime)}`;
    }
    default: return mode;
  }
}

export function formatRetriggerPolicy(policy: string): string {
  switch (policy) {
    case 'ignoreNew': return 'Ignore new';
    case 'cancelAndRestart': return 'Cancel and restart';
    case 'queueAndExecute': return 'Queue and continue';
    case 'cancelOnly': return 'Cancel';
    default: return policy;
  }
}

export function formatBlockType(type: string): string {
  const map: Record<string, string> = {
    controlDevice: 'Control Device',
    timedControl: 'Timed Control',
    stateVariable: 'Global Value',
    webhook: 'Webhook',
    log: 'Log Message',
    runScene: 'Run Scene',
    delay: 'Delay',
    waitForState: 'Wait For State',
    conditional: 'Conditional',
    repeat: 'Repeat',
    repeatWhile: 'Repeat While',
    group: 'Group',
    'return': 'Return',
    executeAutomation: 'Execute Automation',
  };
  return map[type] || type;
}

export function blockTypeIcon(type: string, kind: string): string {
  if (kind === 'action') {
    const map: Record<string, string> = {
      controlDevice: 'house',
      timedControl: 'clock',
      webhook: 'link-circle-fill',
      log: 'cpu',
      runScene: 'play-circle-fill',
    };
    return map[type] || 'bolt-circle-fill';
  }
  const map: Record<string, string> = {
    delay: 'clock',
    waitForState: 'hourglass',
    conditional: 'branch',
    repeat: 'repeat',
    repeatWhile: 'repeat',
    group: 'rectangles-group',
    'return': 'arrow-uturn-left',
    executeAutomation: 'play-circle-fill',
  };
  return map[type] || 'rectangles-group';
}

export function formatConditionSummary(
  condition: unknown,
  lookupDevice?: (id: string) => { name: string; room?: string } | undefined,
  lookupChar?: (deviceId: string, charId: string) => { name: string } | undefined,
): string | undefined {
  if (!condition || typeof condition !== 'object') return undefined;
  const c = condition as Record<string, unknown>;
  const type = c.type as string | undefined;
  if (!type) return undefined;

  switch (type) {
    case 'deviceState': {
      const deviceId = c.deviceId as string | undefined;
      const charId = c.characteristicId as string | undefined;
      const device = deviceId && lookupDevice ? lookupDevice(deviceId) : undefined;
      const char = deviceId && charId && lookupChar ? lookupChar(deviceId, charId) : undefined;
      const deviceLabel = device?.name || deviceId || '?';
      const charLabel = char?.name || charId || '?';
      const comp = c.comparison as { type: string; value?: unknown } | undefined;
      const compStr = comp ? formatComparisonOperator(comp as ComparisonOperator) : '?';
      return `${deviceLabel} · ${charLabel} ${compStr}`;
    }
    case 'timeCondition': {
      const mode = c.mode as string;
      return formatTimeConditionMode(mode, c.startTime as Parameters<typeof formatTimeConditionMode>[1], c.endTime as Parameters<typeof formatTimeConditionMode>[2]);
    }
    case 'and': {
      const subs = c.conditions as unknown[] | undefined;
      if (!subs || subs.length === 0) return undefined;
      if (subs.length === 1) return formatConditionSummary(subs[0], lookupDevice, lookupChar);
      if (subs.length <= 3) {
        const parts = subs.map(s => formatConditionSummary(s, lookupDevice, lookupChar)).filter(Boolean);
        if (parts.length === subs.length) return parts.join(' & ');
      }
      return `All of ${subs.length} conditions`;
    }
    case 'or': {
      const subs = c.conditions as unknown[] | undefined;
      if (!subs || subs.length === 0) return undefined;
      if (subs.length === 1) return formatConditionSummary(subs[0], lookupDevice, lookupChar);
      if (subs.length <= 3) {
        const parts = subs.map(s => formatConditionSummary(s, lookupDevice, lookupChar)).filter(Boolean);
        if (parts.length === subs.length) return parts.join(' | ');
      }
      return `Any of ${subs.length} conditions`;
    }
    case 'not': {
      const inner = formatConditionSummary(c.condition, lookupDevice, lookupChar);
      return inner ? `NOT ${inner}` : 'NOT condition';
    }
    case 'engineState': {
      const ref = c.variableRef as { name?: string } | undefined;
      const varName = ref?.name || 'state';
      const comp = c.comparison as { type: string; value?: unknown } | undefined;
      const compStr = comp ? formatComparisonOperator(comp as ComparisonOperator) : '?';
      return `${varName} ${compStr}`;
    }
    default:
      return type;
  }
}

export function isBlockingType(type: string): boolean {
  return type === 'delay' || type === 'waitForState';
}

export function formatDurationShort(seconds: number): string {
  if (seconds >= 3600) {
    const h = seconds / 3600;
    return `${h.toFixed(1).replace(/\.0$/, '')} hour(s)`;
  }
  if (seconds >= 60) {
    const m = Math.round(seconds / 60);
    return `${m} minute(s)`;
  }
  return `${seconds} second(s)`;
}
