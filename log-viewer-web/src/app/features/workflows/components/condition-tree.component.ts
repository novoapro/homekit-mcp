import { Component, input, computed } from '@angular/core';
import { ConditionResult } from '../../../core/models/workflow-log.model';
import { IconComponent } from '../../../shared/components/icon.component';

@Component({
  selector: 'app-condition-tree',
  standalone: true,
  imports: [IconComponent, ConditionTreeComponent],
  template: `
    <div class="condition-node">
      <div class="condition-row">
        <!-- Depth connector lines -->
        @for (i of depthRange(); track i) {
          <div class="connector-line" [style.background-color]="'var(--tint-secondary)'"></div>
        }

      <!-- Pass/fail icon -->
        @if (result().passed) {
          <app-icon name="checkmark-circle-fill" class="status-icon passed" [size]="16" />
        } @else {
          <app-icon name="xmark-circle-fill" class="status-icon failed" [size]="16" />
        }
        <!-- Logic operator badge -->
        @if (result().logicOperator) {
          <span class="logic-badge">{{ result().logicOperator }}</span>
        }

        <!-- Description -->
        <span class="description">
          @if (result().subResults && result().subResults!.length > 0) {
            {{ result().passed ? 'Passed' : 'Failed' }}
          } @else {
            {{ result().conditionDescription }}
          }
        </span>
      </div>

      <!-- Recursive children -->
      @if (result().subResults) {
        @for (sub of result().subResults!; track $index) {
          <app-condition-tree [result]="sub" [depth]="depth() + 1" />
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
      padding: 4px 0;
    }
    .connector-line {
      width: 2px;
      height: 20px;
      opacity: 0.3;
      border-radius: 1px;
      flex-shrink: 0;
      margin-left: 6px;
    }
    .status-icon.passed {
      color: var(--status-active);
    }
    .status-icon.failed {
      color: var(--status-error);
    }
    .logic-badge {
      display: inline-flex;
      padding: 1px 6px;
      border-radius: var(--radius-xs);
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-bold);
      background: var(--bg-pill);
      color: var(--text-secondary);
    }
    .description {
      color: var(--text-primary);
      flex: 1;
    }
  `]
})
export class ConditionTreeComponent {
  result = input.required<ConditionResult>();
  depth = input(0);

  readonly depthRange = computed(() => Array.from({ length: this.depth() }, (_, i) => i));
}
