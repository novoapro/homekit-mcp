import { Component, input, computed } from '@angular/core';
import { ExecutionStatus } from '../../core/models/workflow-log.model';

@Component({
  selector: 'app-status-badge',
  standalone: true,
  template: `
    <span class="badge" [style.background-color]="bgColor()" [style.color]="fgColor()">
      @if (status() === 'running') {
        <span class="dot animate-pulse"></span>
      }
      {{ label() }}
    </span>
  `,
  styles: [`
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 2px 8px;
      border-radius: var(--radius-full);
      font-size: 10px;
      font-weight: var(--font-weight-bold);
      letter-spacing: 0.03em;
      text-transform: uppercase;
      white-space: nowrap;
      line-height: 1.4;
    }
    .dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background-color: currentColor;
    }
  `]
})
export class StatusBadgeComponent {
  status = input.required<ExecutionStatus>();

  readonly label = computed(() => {
    const map: Record<ExecutionStatus, string> = {
      running: 'Running',
      success: 'Success',
      failure: 'Failed',
      skipped: 'Skipped',
      conditionNotMet: 'Condition Not Met',
      cancelled: 'Cancelled',
    };
    return map[this.status()] || this.status();
  });

  readonly fgColor = computed(() => {
    const map: Record<ExecutionStatus, string> = {
      running: 'var(--status-running)',
      success: 'var(--status-active)',
      failure: 'var(--status-error)',
      skipped: 'var(--status-inactive)',
      conditionNotMet: 'var(--status-warning)',
      cancelled: 'var(--status-inactive)',
    };
    return map[this.status()] || 'var(--text-secondary)';
  });

  readonly bgColor = computed(() => {
    return `color-mix(in srgb, ${this.fgColor()} 15%, transparent)`;
  });
}
