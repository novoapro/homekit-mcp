import { Component, input, computed } from '@angular/core';
import {
  WorkflowConditionDef, DeviceStateConditionDef, TimeConditionDef,
  SceneActiveConditionDef, BlockResultConditionDef,
  LogicAndConditionDef, LogicOrConditionDef, LogicNotConditionDef,
} from '../../../core/models/workflow-definition.model';
import { formatComparisonOperator, formatTimeConditionMode } from '../../../core/utils/workflow-definition-utils';
import { IconComponent } from '../../../shared/components/icon.component';

@Component({
  selector: 'app-definition-condition',
  standalone: true,
  imports: [IconComponent, DefinitionConditionComponent],
  template: `
    <div class="condition-node">
      <div class="condition-row">
        @for (i of depthRange(); track i) {
          <div class="connector-line"></div>
        }

        @if (isLogic()) {
          <span class="logic-badge">{{ logicLabel() }}</span>
        } @else {
          <span class="condition-icon">
            <app-icon [name]="conditionIcon()" [size]="14" />
          </span>
        }

        <div class="condition-info">
          <span class="condition-name">{{ displayName() }}</span>
          @if (detailText()) {
            <span class="condition-detail">{{ detailText() }}</span>
          }
        </div>
      </div>

      @if (childConditions().length > 0) {
        @for (child of childConditions(); track $index) {
          <app-definition-condition [condition]="child" [depth]="depth() + 1" />
        }
      }
    </div>
  `,
  styles: [`
    .condition-node {
      font-size: var(--font-size-sm);
    }
    .condition-row {
      display: flex;
      align-items: center;
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
      background-color: var(--tint-secondary);
    }
    .condition-icon {
      display: flex;
      align-items: center;
      flex-shrink: 0;
      color: var(--text-tertiary);
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
    .condition-info {
      flex: 1;
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .condition-name {
      font-weight: var(--font-weight-semibold);
      color: var(--text-primary);
    }
    .condition-detail {
      color: var(--text-secondary);
      line-height: 1.4;
    }
  `]
})
export class DefinitionConditionComponent {
  condition = input.required<WorkflowConditionDef>();
  depth = input(0);

  readonly depthRange = computed(() => Array.from({ length: this.depth() }, (_, i) => i));

  readonly isLogic = computed(() => {
    const t = this.condition().type;
    return t === 'and' || t === 'or' || t === 'not';
  });

  readonly logicLabel = computed(() => {
    const t = this.condition().type;
    if (t === 'and') return 'AND';
    if (t === 'or') return 'OR';
    if (t === 'not') return 'NOT';
    return '';
  });

  readonly conditionIcon = computed(() => {
    switch (this.condition().type) {
      case 'deviceState': return 'house';
      case 'timeCondition': return 'clock';
      case 'sceneActive': return 'play-circle-fill';
      case 'blockResult': return 'checkmark-circle-fill';
      default: return 'bolt-circle-fill';
    }
  });

  readonly displayName = computed(() => {
    const c = this.condition();
    switch (c.type) {
      case 'deviceState': {
        const d = c as DeviceStateConditionDef;
        return d.deviceName || d.deviceId;
      }
      case 'timeCondition': {
        const t = c as TimeConditionDef;
        return formatTimeConditionMode(t.mode, t.startTime, t.endTime);
      }
      case 'sceneActive': {
        const s = c as SceneActiveConditionDef;
        const name = s.sceneName || s.sceneId;
        return `${name} is ${s.isActive ? 'active' : 'inactive'}`;
      }
      case 'blockResult': {
        const b = c as BlockResultConditionDef;
        const scope = b.blockResultScope.scope === 'specific'
          ? `Block ${b.blockResultScope.blockId?.substring(0, 8) || '?'}`
          : b.blockResultScope.scope === 'all' ? 'All blocks' : 'Any block';
        return `${scope} is ${b.expectedStatus}`;
      }
      case 'and': return 'All of the following';
      case 'or': return 'Any of the following';
      case 'not': return 'None of the following';
      default: return (c as any).type;
    }
  });

  readonly detailText = computed(() => {
    const c = this.condition();
    switch (c.type) {
      case 'deviceState': {
        const d = c as DeviceStateConditionDef;
        const parts: string[] = [];
        if (d.roomName) parts.push(d.roomName);
        parts.push(`${d.characteristicType} ${formatComparisonOperator(d.comparison)}`);
        return parts.join(' · ');
      }
      default: return undefined;
    }
  });

  readonly childConditions = computed((): WorkflowConditionDef[] => {
    const c = this.condition();
    if (c.type === 'and') return (c as LogicAndConditionDef).conditions;
    if (c.type === 'or') return (c as LogicOrConditionDef).conditions;
    if (c.type === 'not') return [(c as LogicNotConditionDef).condition];
    return [];
  });
}
