import type { TriggerCondition, ComparisonOperator, ScheduleType } from '@/types/workflow-definition';

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
      return `transitions from ${from} to ${formatValue(c.to)}`;
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

export function formatTimeConditionMode(mode: string, startTime?: { hour: number; minute: number }, endTime?: { hour: number; minute: number }): string {
  switch (mode) {
    case 'beforeSunrise': return 'Before Sunrise';
    case 'afterSunrise': return 'After Sunrise';
    case 'beforeSunset': return 'Before Sunset';
    case 'afterSunset': return 'After Sunset';
    case 'daytime': return 'Daytime';
    case 'nighttime': return 'Nighttime';
    case 'timeRange': {
      const s = startTime ? formatTime(startTime.hour, startTime.minute) : '?';
      const e = endTime ? formatTime(endTime.hour, endTime.minute) : '?';
      return `${s} – ${e}`;
    }
    default: return mode;
  }
}

export function formatRetriggerPolicy(policy: string): string {
  switch (policy) {
    case 'ignoreNew': return 'Ignore trigger';
    case 'cancelAndRestart': return 'Restart workflow';
    case 'queueAndExecute': return 'Queue new execution';
    case 'cancelOnly': return 'Cancel workflow';
    default: return policy;
  }
}

export function formatBlockType(type: string): string {
  const map: Record<string, string> = {
    controlDevice: 'Control Device',
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
    stop: 'Return',
    executeWorkflow: 'Execute Workflow',
  };
  return map[type] || type;
}

export function blockTypeIcon(type: string, kind: string): string {
  if (kind === 'action') {
    const map: Record<string, string> = {
      controlDevice: 'house',
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
    'return': 'stop-circle',
    stop: 'stop-circle',
    executeWorkflow: 'play-circle-fill',
  };
  return map[type] || 'rectangles-group';
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
