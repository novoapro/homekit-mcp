import { Component, input, computed } from '@angular/core';
import {
  WorkflowTriggerDef, CompoundTriggerDef, DeviceStateTriggerDef,
  ScheduleTriggerDef, SunEventTriggerDef, WebhookTriggerDef,
} from '../../../core/models/workflow-definition.model';
import { TRIGGER_TYPE_ICONS } from '../../../core/models/workflow-log.model';
import { formatTriggerCondition, formatScheduleType, formatRetriggerPolicy } from '../../../core/utils/workflow-definition-utils';
import { IconComponent } from '../../../shared/components/icon.component';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

@Component({
  selector: 'app-definition-trigger',
  standalone: true,
  imports: [IconComponent, DefinitionTriggerComponent],
  template: `
    <div class="trigger-node">
      <div class="trigger-row">
        @for (i of depthRange(); track i) {
          <div class="connector-line" [style.background-color]="depthColor(i)"></div>
        }

        <span class="trigger-icon" [style.color]="iconColor()">
          <app-icon [name]="triggerIcon()" [size]="16" />
        </span>

        @if (trigger().type === 'compound') {
          <span class="logic-badge">{{ operatorLabel() }}</span>
        }

        <div class="trigger-info">
          <span class="trigger-name">{{ displayName() }}</span>
          @if (detailText()) {
            <span class="trigger-detail">{{ detailText() }}</span>
          }
          @if (retriggerLabel()) {
            <span class="retrigger-badge">
              <span class="retrigger-badge-key">Retrigger</span>
              {{ retriggerLabel() }}
            </span>
          }
        </div>
      </div>

      @if (trigger().type === 'compound') {
        @for (sub of compoundTriggers(); track $index) {
          <app-definition-trigger [trigger]="sub" [depth]="depth() + 1" />
        }
      }
    </div>
  `,
  styles: [`
    .trigger-node {
      font-size: var(--font-size-sm);
    }
    .trigger-row {
      display: flex;
      align-items: flex-start;
      gap: 6px;
      padding: 6px 0;
    }
    .connector-line {
      width: 2px;
      min-height: 24px;
      align-self: stretch;
      opacity: 0.3;
      border-radius: 1px;
      flex-shrink: 0;
      margin-left: 6px;
    }
    .trigger-icon {
      display: flex;
      align-items: center;
      flex-shrink: 0;
      margin-top: 1px;
    }
    .logic-badge {
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-bold);
      padding: 1px 6px;
      border-radius: 4px;
      background: color-mix(in srgb, var(--tint-secondary) 15%, transparent);
      color: var(--tint-secondary);
      text-transform: uppercase;
      flex-shrink: 0;
    }
    .trigger-info {
      flex: 1;
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .trigger-name {
      font-weight: var(--font-weight-semibold);
      color: var(--text-primary);
    }
    .trigger-detail {
      color: var(--text-secondary);
      line-height: 1.4;
    }
    .retrigger-badge {
      display: inline-flex;
      align-items: center;
      align-self: flex-start;
      gap: 4px;
      font-size: 10px;
      font-weight: var(--font-weight-medium);
      padding: 2px 8px;
      border-radius: var(--radius-full);
      background: color-mix(in srgb, var(--text-tertiary) 10%, transparent);
      color: var(--text-secondary);
      margin-top: 2px;
    }
    .retrigger-badge-key {
      font-weight: var(--font-weight-bold);
      color: var(--text-tertiary);
      text-transform: uppercase;
      font-size: 9px;
      letter-spacing: 0.06em;
    }
  `]
})
export class DefinitionTriggerComponent {
  trigger = input.required<WorkflowTriggerDef>();
  depth = input(0);

  readonly depthRange = computed(() => Array.from({ length: this.depth() }, (_, i) => i));

  readonly triggerIcon = computed(() => {
    return TRIGGER_TYPE_ICONS[this.trigger().type] || 'bolt-circle-fill';
  });

  readonly iconColor = computed(() => {
    return 'var(--tint-main)';
  });

  readonly operatorLabel = computed(() => {
    const t = this.trigger();
    if (t.type === 'compound') return (t as CompoundTriggerDef).operator.toUpperCase();
    return '';
  });

  readonly displayName = computed(() => {
    const t = this.trigger();
    if (t.name) return t.name;
    switch (t.type) {
      case 'deviceStateChange': {
        const d = t as DeviceStateTriggerDef;
        return d.deviceName || d.deviceId;
      }
      case 'schedule': return 'Schedule';
      case 'webhook': return 'Webhook';
      case 'compound': return 'Compound Trigger';
      case 'workflow': return 'Callable Trigger';
      case 'sunEvent': {
        const s = t as SunEventTriggerDef;
        return s.event === 'sunrise' ? 'Sunrise' : 'Sunset';
      }
      default: return (t as any).type;
    }
  });

  readonly detailText = computed(() => {
    const t = this.trigger();
    switch (t.type) {
      case 'deviceStateChange': {
        const d = t as DeviceStateTriggerDef;
        const parts: string[] = [];
        if (d.roomName) parts.push(d.roomName);
        parts.push(`${d.characteristicType} ${formatTriggerCondition(d.condition)}`);
        return parts.join(' · ');
      }
      case 'schedule': {
        const s = t as ScheduleTriggerDef;
        return formatScheduleType(s.scheduleType);
      }
      case 'webhook': {
        const w = t as WebhookTriggerDef;
        return `Token: ${w.token}`;
      }
      case 'sunEvent': {
        const s = t as SunEventTriggerDef;
        if (s.offsetMinutes === 0) return undefined;
        const abs = Math.abs(s.offsetMinutes);
        const dir = s.offsetMinutes > 0 ? 'after' : 'before';
        return `${abs} min ${dir}`;
      }
      case 'compound': return undefined;
      case 'workflow': return 'Can be triggered by other workflows';
      default: return undefined;
    }
  });

  readonly retriggerLabel = computed(() => {
    const policy = (this.trigger() as any).retriggerPolicy;
    if (!policy) return null;
    return formatRetriggerPolicy(policy);
  });

  readonly compoundTriggers = computed(() => {
    const t = this.trigger();
    if (t.type === 'compound') return (t as CompoundTriggerDef).triggers;
    return [];
  });

  depthColor(i: number): string {
    return DEPTH_COLORS[i % DEPTH_COLORS.length];
  }
}
