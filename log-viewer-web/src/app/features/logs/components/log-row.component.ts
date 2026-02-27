import { Component, input, signal, computed } from '@angular/core';
import { RouterLink } from '@angular/router';
import { trigger, transition, style, animate } from '@angular/animations';
import { StateChangeLog, LogCategory, CATEGORY_META } from '../../../core/models/state-change-log.model';
import { WorkflowExecutionLog, ExecutionStatus } from '../../../core/models/workflow-log.model';
import { characteristicDisplayName, formatCharacteristicValue } from '../../../core/utils/characteristic-types';
import { CategoryIconComponent } from '../../../shared/components/category-icon.component';
import { IconComponent } from '../../../shared/components/icon.component';
import { LogDetailPanelComponent } from './log-detail-panel.component';
import { ConditionTreeComponent } from '../../workflows/components/condition-tree.component';
import { BlockTreeComponent } from '../../workflows/components/block-tree.component';

@Component({
  selector: 'app-log-row',
  standalone: true,
  imports: [RouterLink, CategoryIconComponent, IconComponent, LogDetailPanelComponent, ConditionTreeComponent, BlockTreeComponent],
  templateUrl: './log-row.component.html',
  styleUrl: './log-row.component.css',
  animations: [
    trigger('expandCollapse', [
      transition(':enter', [
        style({ height: 0, opacity: 0, overflow: 'hidden' }),
        animate('250ms cubic-bezier(0.4, 0, 0.2, 1)', style({ height: '*', opacity: 1 }))
      ]),
      transition(':leave', [
        style({ overflow: 'hidden' }),
        animate('200ms cubic-bezier(0.4, 0, 0.2, 1)', style({ height: 0, opacity: 0 }))
      ])
    ])
  ]
})
export class LogRowComponent {
  log = input.required<StateChangeLog>();
  index = input(0);

  expanded = signal(false);

  readonly isExpandable = computed(() => {
    const l = this.log();
    // Workflow entries with execution data are always expandable
    if (l.workflowExecution) return true;
    return !!(l.detailedRequestBody || l.requestBody || l.responseBody);
  });

  readonly isError = computed(() => {
    const l = this.log();
    const cat = l.category;
    if (cat === LogCategory.WorkflowError) {
      // If execution succeeded or was cancelled (stop block), not a red error
      const status = l.workflowExecution?.status;
      if (status === 'success' || status === 'cancelled' || status === 'running') return false;
    }
    return cat === LogCategory.WebhookError ||
      cat === LogCategory.ServerError ||
      cat === LogCategory.WorkflowError ||
      cat === LogCategory.SceneError;
  });

  readonly categoryColor = computed(() => {
    const l = this.log();
    if (l.category === LogCategory.WorkflowError) {
      const status = l.workflowExecution?.status;
      if (status === 'success') return 'var(--status-active)';
      if (status === 'cancelled') return 'var(--status-warning)';
    }
    const meta = CATEGORY_META[l.category];
    return meta?.color || 'var(--tint-main)';
  });

  readonly displayCharacteristicType = computed(() => {
    return characteristicDisplayName(this.log().characteristicType);
  });

  readonly backupSubtype = computed(() => {
    const l = this.log();
    if (l.category !== LogCategory.BackupRestore) return '';
    return l.characteristicType
      .replace(/-/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase());
  });

  readonly isBooleanChange = computed(() => {
    const l = this.log();
    if (l.category !== LogCategory.StateChange) return false;
    return typeof l.newValue === 'boolean' || typeof l.oldValue === 'boolean';
  });

  readonly timeStr = computed(() => {
    return new Date(this.log().timestamp).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  });

  readonly formattedOldValue = computed(() => {
    const l = this.log();
    if (l.category === LogCategory.StateChange) {
      return formatCharacteristicValue(l.oldValue, l.characteristicType);
    }
    return this.formatValue(l.oldValue);
  });

  readonly formattedNewValue = computed(() => {
    const l = this.log();
    if (l.category === LogCategory.StateChange) {
      return formatCharacteristicValue(l.newValue, l.characteristicType);
    }
    return this.formatValue(l.newValue);
  });

  readonly showValueChange = computed(() => {
    const l = this.log();
    return l.category === LogCategory.StateChange && (l.oldValue !== undefined || l.newValue !== undefined);
  });

  // 12 visually distinct [background, foreground] pairs for room pills.
  private static readonly ROOM_COLORS: [string, string][] = [
    ['#dbeafe', '#1e3a8a'], // blue
    ['#dcfce7', '#14532d'], // green
    ['#fef9c3', '#713f12'], // yellow
    ['#ffe4e6', '#881337'], // rose
    ['#f3e8ff', '#4c1d95'], // violet
    ['#ffedd5', '#7c2d12'], // orange
    ['#cffafe', '#164e63'], // cyan
    ['#fce7f3', '#831843'], // pink
    ['#d1fae5', '#064e3b'], // emerald
    ['#e0e7ff', '#1e1b4b'], // indigo
    ['#fef3c7', '#78350f'], // amber
    ['#f1f5f9', '#1e293b'], // slate
  ];

  private static hashName(name: string): number {
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
    }
    return hash % LogRowComponent.ROOM_COLORS.length;
  }

  /** Stable [bg, fg] color pair derived from the room name. */
  readonly roomBadgeColors = computed((): [string, string] => {
    const name = this.log().roomName;
    if (!name) return ['transparent', 'inherit'];
    return LogRowComponent.ROOM_COLORS[LogRowComponent.hashName(name)];
  });

  /** Stable [bg, fg] color pair derived from the service name. */
  readonly serviceBadgeColors = computed((): [string, string] => {
    const name = this.log().serviceName;
    if (!name) return ['transparent', 'inherit'];
    return LogRowComponent.ROOM_COLORS[LogRowComponent.hashName(name)];
  });

  readonly showServiceBadge = computed(() => {
    const l = this.log();
    return l.serviceName &&
      l.category !== LogCategory.McpCall &&
      l.category !== LogCategory.RestCall;
  });

  readonly serviceIconMatch = computed<string | null>(() => {
    const name = this.log().serviceName?.toLowerCase();
    if (!name) return null;

    // Core HomeKit Types
    if (name.includes('lightbulb') || name.includes('light')) return 'hk-lightbulb';
    if (name.includes('switch') || name.includes('button')) return 'hk-switch';
    if (name.includes('outlet') || name.includes('plug')) return 'hk-outlet';
    if (name.includes('fan')) return 'hk-fan';
    if (name.includes('thermostat') || name.includes('heater') || name.includes('cooler') || name.includes('ac')) return 'hk-thermostat';
    if (name.includes('garage')) return 'hk-garage';
    if (name.includes('lock')) return 'hk-lock';
    if (name.includes('window') || name.includes('blind') || name.includes('shade')) return 'hk-window-covering';
    if (name.includes('motion')) return 'hk-motion';
    if (name.includes('occupancy') || name.includes('presence')) return 'hk-occupancy';
    if (name.includes('temperature') || name.includes('temp')) return 'hk-temperature';
    if (name.includes('humidity')) return 'hk-humidity';
    if (name.includes('contact') || name.includes('door')) return 'hk-contact';
    if (name.includes('leak') || name.includes('water')) return 'hk-leak';
    if (name.includes('smoke') || name.includes('monoxide') || name.includes('dioxide')) return 'hk-smoke';
    if (name.includes('security') || name.includes('alarm')) return 'hk-security';
    if (name.includes('camera') || name.includes('video')) return 'hk-camera';
    if (name.includes('tv') || name.includes('television')) return 'hk-tv';
    if (name.includes('speaker') || name.includes('audio')) return 'hk-speaker';
    if (name.includes('valve') || name.includes('faucet') || name.includes('irrigation')) return 'hk-valve';
    if (name.includes('doorbell') || name.includes('bell')) return 'hk-doorbell';
    if (name.includes('purifier') || name.includes('air purifier')) return 'hk-air-purifier';
    if (name.includes('air quality') || name.includes('airquality') || name.includes('air_quality')) return 'hk-air-quality';
    if (name.includes('battery')) return 'hk-battery';
    if (name.includes('microphone') || name.includes('mic')) return 'hk-microphone';
    if (name.includes('filter')) return 'hk-filter';
    if (name.includes('robot') || name.includes('vacuum') || name.includes('roomba')) return 'hk-robot-vacuum';
    if (name.includes('curtain') || name.includes('drape')) return 'hk-curtain';

    return null;
  });

  readonly isWorkflowLog = computed(() => {
    const cat = this.log().category;
    return cat === LogCategory.WorkflowExecution || cat === LogCategory.WorkflowError;
  });

  /** Status from the embedded WorkflowExecutionLog. */
  readonly workflowStatus = computed<ExecutionStatus | null>(() => {
    return this.log().workflowExecution?.status ?? null;
  });

  /** Status badge color based on execution status. */
  readonly workflowStatusColor = computed(() => {
    const s = this.workflowStatus();
    if (!s) return 'var(--status-active)';
    const map: Record<ExecutionStatus, string> = {
      running: 'var(--status-running, var(--status-active))',
      success: 'var(--status-active)',
      failure: 'var(--status-error)',
      skipped: 'var(--text-secondary)',
      conditionNotMet: 'var(--status-warning)',
      cancelled: 'var(--status-warning)',
    };
    return map[s] || 'var(--text-secondary)';
  });

  /** Human-readable status label. */
  readonly workflowStatusLabel = computed(() => {
    const s = this.workflowStatus();
    if (!s) return '';
    const map: Record<ExecutionStatus, string> = {
      running: 'Running',
      success: 'Success',
      failure: 'Failed',
      skipped: 'Skipped',
      conditionNotMet: 'Condition Not Met',
      cancelled: 'Cancelled',
    };
    return map[s] || s;
  });

  /** Trigger description from the embedded execution log. */
  readonly workflowTriggerDescription = computed(() => {
    const e = this.log().workflowExecution;
    if (!e) return this.log().requestBody ?? null;
    if (e.triggerEvent?.triggerDescription) return e.triggerEvent.triggerDescription;
    const te = e.triggerEvent;
    if (te?.deviceName) {
      const oldStr = te.oldValue !== undefined ? String(te.oldValue) : '?';
      const newStr = te.newValue !== undefined ? String(te.newValue) : '?';
      return `${te.deviceName}: ${oldStr} → ${newStr}`;
    }
    return null;
  });

  /** Splits responseBody into an HTTP status code (if present) + remainder. */
  readonly parsedResponseBody = computed(() => {
    const body = this.log().responseBody;
    if (!body) return null;
    const match = body.match(/^(\d{3})(\s.*|$)/s);
    if (!match) return { code: null, color: '', rest: body };
    const code = parseInt(match[1], 10);
    const color = code < 300
      ? 'var(--status-active)'
      : code < 400
        ? 'var(--status-warning)'
        : 'var(--status-error)';
    return { code: match[1], color, rest: match[2].trim() };
  });

  toggle(): void {
    if (this.isExpandable()) {
      this.expanded.set(!this.expanded());
    }
  }

  private formatValue(val: any): string {
    if (val === undefined || val === null) return '—';
    if (typeof val === 'boolean') return val ? 'on' : 'off';
    if (typeof val === 'number') return String(val);
    if (typeof val === 'string') return val;
    return JSON.stringify(val);
  }
}
