import { Component, input, computed } from '@angular/core';
import { WorkflowExecutionLog } from '../../../core/models/workflow-log.model';
import { IconComponent } from '../../../shared/components/icon.component';
import { StatusBadgeComponent } from '../../../shared/components/status-badge.component';
import { DurationPipe } from '../../../shared/pipes/duration.pipe';

@Component({
  selector: 'app-workflow-log-row',
  standalone: true,
  imports: [IconComponent, StatusBadgeComponent, DurationPipe],
  template: `
    <div class="workflow-card" [style.animation-delay.ms]="index() * 30">
      <!-- Status icon -->
      <div class="status-icon" [style.color]="statusColor()">
        @if (log().status === 'running') {
          <span class="animate-pulse">
            <app-icon name="bolt-circle-fill" [size]="32" />
          </span>
        } @else {
          <app-icon name="bolt-circle-fill" [size]="32" />
        }
      </div>

      <!-- Content -->
      <div class="content">
        <div class="header-row">
          <span class="workflow-name">{{ log().workflowName }}</span>
          <app-status-badge [status]="log().status" />
        </div>
        @if (log().triggerEvent?.triggerDescription) {
          <div class="trigger-text">{{ log().triggerEvent!.triggerDescription }}</div>
        }
        <div class="meta-row">
          <span class="step-count">{{ log().blockResults.length }} steps</span>
          @if (log().errorMessage) {
            <span class="message-text" [class.error]="log().status === 'failure'" [class.success]="log().status === 'success'" [class.cancelled]="log().status === 'cancelled'">{{ log().errorMessage }}</span>
          }
        </div>
      </div>

      <!-- Time -->
      <div class="time-col">
        <span class="time">{{ timeStr() }}</span>
        <span class="duration">
          @if (log().completedAt) {
            {{ log().triggeredAt | duration: log().completedAt }}
          } @else if (log().status === 'running') {
            {{ log().triggeredAt | duration }}
          }
        </span>
      </div>

      <!-- Chevron -->
      <app-icon name="chevron-right" [size]="14" />
    </div>
  `,
  styles: [`
    :host {
      display: block;
      padding: 0 var(--spacing-sm);
      animation: cardEnter 350ms cubic-bezier(0, 0, 0.2, 1) backwards;
    }
    .workflow-card {
      display: flex;
      align-items: flex-start;
      gap: var(--spacing-sm);
      padding: var(--card-padding);
      background: var(--bg-card);
      border-radius: var(--radius-md);
      border: none;
      box-shadow: var(--shadow-card);
      margin-bottom: var(--card-gap);
      cursor: pointer;
      transition: background 150ms ease, box-shadow 150ms ease, transform 150ms cubic-bezier(0.34, 1.56, 0.64, 1);
    }
    .workflow-card:hover {
      box-shadow: var(--shadow-card-hover);
    }
    .workflow-card:active {
      transform: scale(0.985);
    }
    .status-icon {
      flex-shrink: 0;
    }
    .content {
      flex: 1;
      min-width: 0;
      padding-top: 4px; /* center header text with 32px status icon */
    }
    .header-row {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      flex-wrap: wrap;
    }
    .workflow-name {
      font-size: var(--font-size-base);
      font-weight: var(--font-weight-bold);
      color: var(--text-primary);
    }
    .trigger-text {
      font-size: var(--font-size-sm);
      color: var(--text-secondary);
      margin-top: 4px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .meta-row {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      margin-top: 4px;
    }
    .step-count {
      font-size: var(--font-size-xs);
      color: var(--text-tertiary);
    }
    .message-text {
      font-size: var(--font-size-xs);
      color: var(--text-secondary);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .message-text.error {
      color: var(--status-error);
    }
    .message-text.success {
      color: var(--status-active);
    }
    .message-text.cancelled {
      color: var(--status-warning);
    }
    .time-col {
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      flex-shrink: 0;
      padding-top: 4px; /* align with content padding-top */
    }
    .time {
      font-size: var(--font-size-xs);
      color: var(--text-tertiary);
    }
    .duration {
      font-size: var(--font-size-xs);
      color: var(--text-tertiary);
      font-family: var(--font-mono);
    }
    app-icon {
      color: var(--text-tertiary);
      flex-shrink: 0;
      padding-top: 8px; /* align with header text (4px content offset + 4px centering) */
    }
    @media (max-width: 768px) {
      .workflow-card {
        --card-padding: 12px;
        border-radius: var(--radius-sm);
        gap: var(--spacing-xs);
      }
      .content {
        padding-top: 2px;
      }
      .time-col {
        padding-top: 2px;
      }
      app-icon {
        padding-top: 6px;
      }
      .workflow-name {
        font-size: var(--font-size-sm);
      }
      .trigger-text {
        font-size: var(--font-size-xs);
      }
    }
    @media (max-width: 480px) {
      .time-col {
        display: none;
      }
      .meta-row {
        flex-wrap: wrap;
      }
    }
  `]
})
export class WorkflowLogRowComponent {
  log = input.required<WorkflowExecutionLog>();
  index = input(0);

  readonly statusColor = computed(() => {
    const map: Record<string, string> = {
      running: 'var(--status-running)',
      success: 'var(--status-active)',
      failure: 'var(--status-error)',
      skipped: 'var(--status-inactive)',
      conditionNotMet: 'var(--status-warning)',
      cancelled: 'var(--status-inactive)',
    };
    return map[this.log().status] || 'var(--tint-main)';
  });

  readonly timeStr = computed(() => {
    return new Date(this.log().triggeredAt).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  });
}
