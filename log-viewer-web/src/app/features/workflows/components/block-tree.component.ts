import { Component, input, computed } from '@angular/core';
import { BlockResult, ExecutionStatus } from '../../../core/models/workflow-log.model';
import { IconComponent } from '../../../shared/components/icon.component';
import { DurationPipe } from '../../../shared/pipes/duration.pipe';

const DEPTH_COLORS = [
  'var(--depth-0)',  // orange
  'var(--depth-1)',  // purple
  'var(--depth-2)',  // orange
  'var(--depth-3)',  // teal
  'var(--depth-4)',  // pink
];

@Component({
  selector: 'app-block-tree',
  standalone: true,
  imports: [IconComponent, DurationPipe, BlockTreeComponent],
  template: `
    <div class="block-node">
      <div class="block-row">
        <!-- Depth connector lines -->
        @for (i of depthRange(); track i) {
          <div
            class="connector-line"
            [style.background-color]="depthColor(i)"
          ></div>
        }

        <!-- Status icon -->
        <span class="status-icon" [style.color]="statusColor()">
          @switch (result().status) {
            @case ('success') {
              <app-icon name="checkmark-circle-fill" [size]="18" />
            }
            @case ('failure') {
              <app-icon name="xmark-circle-fill" [size]="18" />
            }
            @case ('running') {
              <span class="animate-pulse">
                <app-icon name="spinner" [size]="18" />
              </span>
            }
            @case ('skipped') {
              <app-icon name="forward-circle-fill" [size]="18" />
            }
            @case ('conditionNotMet') {
              <app-icon name="exclamation-circle-fill" [size]="18" />
            }
            @case ('cancelled') {
              <app-icon name="slash-circle-fill" [size]="18" />
            }
          }
        </span>

        <!-- Container icon (for flow control) -->
        @if (result().blockKind === 'flowControl') {
          <span class="container-icon" [style.color]="depthColor(depth())">
            <app-icon [name]="containerIcon()" [size]="14" />
          </span>
        }

        <!-- Block info -->
        <div class="block-info">
          <div class="block-header">
            <span class="block-name">{{ result().blockName || result().blockType }}</span>
            @if (result().completedAt) {
              <span class="duration">{{ result().startedAt | duration: result().completedAt }}</span>
            } @else if (result().status === 'running') {
              <span class="duration running">{{ result().startedAt | duration }}</span>
            }
          </div>
          @if (result().detail) {
            <div class="block-detail">{{ result().detail }}</div>
          }
          @if (result().errorMessage) {
            <div class="block-message" [class.error]="result().status === 'failure'" [class.success]="result().status === 'success'" [class.cancelled]="result().status === 'cancelled'">{{ result().errorMessage }}</div>
          }
        </div>
      </div>

      <!-- Nested results -->
      @if (result().nestedResults && result().nestedResults!.length > 0) {
        @for (nested of result().nestedResults!; track nested.id) {
          <app-block-tree [result]="nested" [depth]="depth() + 1" />
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
    .status-icon {
      display: flex;
      align-items: center;
      flex-shrink: 0;
      margin-top: 1px;
    }
    .container-icon {
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
    .duration {
      font-size: var(--font-size-xs);
      color: var(--text-tertiary);
      font-family: var(--font-mono);
    }
    .duration.running {
      color: var(--status-running);
    }
    .block-detail {
      color: var(--text-secondary);
      margin-top: 2px;
      line-height: 1.4;
    }
    .block-message {
      margin-top: 2px;
      font-size: var(--font-size-xs);
      color: var(--text-secondary);
    }
    .block-message.error {
      color: var(--status-error);
    }
    .block-message.success {
      color: var(--status-active);
    }
    .block-message.cancelled {
      color: var(--status-warning);
    }
  `]
})
export class BlockTreeComponent {
  result = input.required<BlockResult>();
  depth = input(0);

  readonly depthRange = computed(() => Array.from({ length: this.depth() }, (_, i) => i));

  readonly containerIcon = computed(() => {
    const map: Record<string, string> = {
      conditional: 'branch',
      repeat: 'repeat',
      repeatWhile: 'repeat',
      group: 'rectangles-group',
      delay: 'clock',
      waitForState: 'hourglass',
    };
    return map[this.result().blockType] || 'rectangles-group';
  });

  readonly statusColor = computed(() => {
    const map: Record<ExecutionStatus, string> = {
      running: 'var(--status-running)',
      success: 'var(--status-active)',
      failure: 'var(--status-error)',
      skipped: 'var(--status-inactive)',
      conditionNotMet: 'var(--status-warning)',
      cancelled: 'var(--status-inactive)',
    };
    return map[this.result().status] || 'var(--text-secondary)';
  });

  depthColor(i: number): string {
    return DEPTH_COLORS[i % DEPTH_COLORS.length];
  }
}
