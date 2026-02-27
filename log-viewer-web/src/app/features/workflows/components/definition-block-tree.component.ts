import { Component, input, computed } from '@angular/core';
import { WorkflowBlockDef } from '../../../core/models/workflow-definition.model';
import {
  blockTypeIcon, formatBlockType, isBlockingType,
  formatDuration, formatComparisonOperator,
} from '../../../core/utils/workflow-definition-utils';
import { IconComponent } from '../../../shared/components/icon.component';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

@Component({
  selector: 'app-definition-block-tree',
  standalone: true,
  imports: [IconComponent, DefinitionBlockTreeComponent],
  template: `
    <div class="block-node">
      <div class="block-row">
        @for (i of depthRange(); track i) {
          <div class="connector-line" [style.background-color]="depthColor(i)"></div>
        }

        <span class="type-icon" [style.color]="typeColor()">
          <app-icon [name]="icon()" [size]="16" />
        </span>

        <div class="block-info">
          <div class="block-header">
            <span class="block-name">{{ displayName() }}</span>
            @if (isBlocking()) {
              <span class="blocking-badge">
                <app-icon name="hourglass" [size]="10" />
                Blocking
              </span>
            }
          </div>
          @if (detailText()) {
            <div class="block-detail">{{ detailText() }}</div>
          }
        </div>
      </div>

      <!-- Then / Else for conditional -->
      @if (block().type === 'conditional') {
        @if (thenBlocks().length > 0) {
          <div class="sub-label" [style.padding-left.px]="(depth() + 1) * 14 + 6">Then</div>
          @for (b of thenBlocks(); track b.blockId) {
            <app-definition-block-tree [block]="b" [depth]="depth() + 1" />
          }
        }
        @if (elseBlocks().length > 0) {
          <div class="sub-label" [style.padding-left.px]="(depth() + 1) * 14 + 6">Else</div>
          @for (b of elseBlocks(); track b.blockId) {
            <app-definition-block-tree [block]="b" [depth]="depth() + 1" />
          }
        }
      }

      <!-- Nested blocks for repeat, repeatWhile, group -->
      @if (nestedBlocks().length > 0 && block().type !== 'conditional') {
        @for (b of nestedBlocks(); track b.blockId) {
          <app-definition-block-tree [block]="b" [depth]="depth() + 1" />
        }
      }
    </div>
  `,
  styles: [`
    .block-node {
      font-size: var(--font-size-sm);
    }
    .block-row {
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
    .type-icon {
      display: flex;
      align-items: center;
      flex-shrink: 0;
      margin-top: 1px;
    }
    .block-info {
      flex: 1;
      min-width: 0;
    }
    .block-header {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
    }
    .block-name {
      font-weight: var(--font-weight-semibold);
      color: var(--text-primary);
    }
    .blocking-badge {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: 10px;
      font-weight: var(--font-weight-bold);
      padding: 1px 6px;
      border-radius: 4px;
      background: color-mix(in srgb, var(--status-warning) 15%, transparent);
      color: var(--status-warning);
      flex-shrink: 0;
    }
    .block-detail {
      color: var(--text-secondary);
      margin-top: 2px;
      line-height: 1.4;
    }
    .sub-label {
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-bold);
      color: var(--text-tertiary);
      text-transform: uppercase;
      letter-spacing: 0.08em;
      padding: 4px 0 0;
    }
  `]
})
export class DefinitionBlockTreeComponent {
  block = input.required<WorkflowBlockDef>();
  depth = input(0);

  readonly depthRange = computed(() => Array.from({ length: this.depth() }, (_, i) => i));

  readonly icon = computed(() => blockTypeIcon(this.block().type, this.block().block));

  readonly typeColor = computed(() => {
    const b = this.block();
    if (isBlockingType(b.type)) return 'var(--status-warning)';
    if (b.block === 'flowControl') return this.depthColor(this.depth());
    return 'var(--tint-main)';
  });

  readonly isBlocking = computed(() => isBlockingType(this.block().type));

  readonly displayName = computed(() => {
    const b = this.block();
    if (b.name) return b.name;
    if (b.type === 'controlDevice' && b.deviceName) return b.deviceName;
    if (b.type === 'runScene' && b.sceneName) return b.sceneName;
    if (b.type === 'group' && b.label) return b.label;
    return formatBlockType(b.type);
  });

  readonly detailText = computed(() => {
    const b = this.block();
    switch (b.type) {
      case 'controlDevice': {
        const parts: string[] = [];
        if (b.roomName) parts.push(b.roomName);
        if (b.characteristicType) {
          const val = b.value !== undefined ? ` → ${formatVal(b.value)}` : '';
          parts.push(`${b.characteristicType}${val}`);
        }
        return parts.join(' · ') || undefined;
      }
      case 'webhook': {
        return `${(b.method || 'POST').toUpperCase()} ${b.url || ''}`;
      }
      case 'log': return b.message || undefined;
      case 'runScene': return b.sceneName ? undefined : b.sceneId;
      case 'delay': return b.seconds !== undefined ? formatDuration(b.seconds) : undefined;
      case 'waitForState': {
        const parts: string[] = [];
        const device = b.deviceName || b.deviceId || '';
        if (device) parts.push(device);
        if (b.characteristicType && b.condition) {
          parts.push(`${b.characteristicType} ${formatComparisonOperator(b.condition)}`);
        }
        if (b.timeoutSeconds) parts.push(`Timeout: ${formatDuration(b.timeoutSeconds)}`);
        return parts.join(' · ') || undefined;
      }
      case 'conditional': return undefined;
      case 'repeat': {
        const parts: string[] = [`${b.count || 0} times`];
        if (b.delayBetweenSeconds) parts.push(`${formatDuration(b.delayBetweenSeconds)} between`);
        return parts.join(', ');
      }
      case 'repeatWhile': {
        const parts: string[] = [];
        if (b.maxIterations) parts.push(`Max ${b.maxIterations} iterations`);
        if (b.delayBetweenSeconds) parts.push(`${formatDuration(b.delayBetweenSeconds)} between`);
        return parts.join(', ') || undefined;
      }
      case 'group': return undefined;
      case 'return':
      case 'stop': {
        const parts: string[] = [];
        if (b.outcome) parts.push(b.outcome);
        if (b.message) parts.push(b.message);
        return parts.join(': ') || undefined;
      }
      case 'executeWorkflow': {
        const mode = b.executionMode || 'inline';
        const modeLabel = mode === 'inline' ? 'Inline (Wait)' : mode === 'parallel' ? 'Parallel' : 'Delegate';
        return `Mode: ${modeLabel}`;
      }
      default: return undefined;
    }
  });

  readonly thenBlocks = computed(() => this.block().thenBlocks || []);
  readonly elseBlocks = computed(() => this.block().elseBlocks || []);

  readonly nestedBlocks = computed(() => {
    return this.block().blocks || [];
  });

  depthColor(i: number): string {
    return DEPTH_COLORS[i % DEPTH_COLORS.length];
  }
}

function formatVal(val: any): string {
  if (val === undefined || val === null) return '?';
  if (typeof val === 'boolean') return val ? 'On' : 'Off';
  if (typeof val === 'object' && val.value !== undefined) return formatVal(val.value);
  return String(val);
}
