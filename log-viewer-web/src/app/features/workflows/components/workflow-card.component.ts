import { Component, input, output, computed } from '@angular/core';
import { Workflow, TriggerTypeKey, TRIGGER_TYPE_LABELS, TRIGGER_TYPE_ICONS } from '../../../core/models/workflow-log.model';
import { IconComponent } from '../../../shared/components/icon.component';
import { RelativeTimePipe } from '../../../shared/pipes/relative-time.pipe';

@Component({
  selector: 'app-workflow-card',
  standalone: true,
  imports: [IconComponent, RelativeTimePipe],
  template: `
    <div class="workflow-card" [style.animation-delay.ms]="index() * 40">
      <!-- Trigger icon circle -->
      <div class="trigger-icon" [style.color]="statusColor()">
        <div class="trigger-icon-bg" [style.background]="statusBg()">
          <app-icon [name]="triggerIcon()" [size]="18" />
        </div>
      </div>

      <!-- Content -->
      <div class="content">
        <!-- Row 1: Name + disabled badge -->
        <div class="name-row">
          <span class="workflow-name">{{ workflow().name }}</span>
          @if (!workflow().isEnabled) {
            <span class="disabled-badge">Disabled</span>
          }
        </div>

        <!-- Row 2: Trigger type pill + stats -->
        <div class="stats-row">
          <span class="trigger-pill" [style.color]="statusColor()" [style.background]="pillBg()">
            {{ triggerLabel() }}
          </span>
          <span class="stat">
            <app-icon name="bolt-circle-fill" [size]="12" />
            {{ workflow().triggers.length }}
          </span>
          <span class="stat">
            <app-icon name="rectangles-group" [size]="12" />
            {{ workflow().blocks.length }}
          </span>
          @if (workflow().metadata.totalExecutions > 0) {
            <span class="stat">
              <app-icon name="play-circle-fill" [size]="12" />
              {{ workflow().metadata.totalExecutions }}
            </span>
          }
        </div>

        <!-- Row 3: Description -->
        @if (workflow().description) {
          <div class="description">{{ workflow().description }}</div>
        }

        <!-- Row 4: Last triggered -->
        @if (workflow().metadata.lastTriggeredAt) {
          <div class="last-triggered">
            Last triggered {{ workflow().metadata.lastTriggeredAt! | relativeTime }}
          </div>
        }
      </div>

      <!-- Toggle -->
      <label class="toggle-wrapper" (click)="$event.stopPropagation()">
        <input
          type="checkbox"
          [checked]="workflow().isEnabled"
          (change)="onToggleChange($event)"
        />
        <span class="toggle-track"></span>
      </label>
    </div>
  `,
  styles: [`
    :host {
      display: block;
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

    /* Trigger icon */
    .trigger-icon {
      flex-shrink: 0;
      padding-top: 2px;
    }
    .trigger-icon-bg {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    /* Content */
    .content {
      flex: 1;
      min-width: 0;
      padding-top: 2px;
    }
    .name-row {
      display: flex;
      align-items: center;
      gap: var(--spacing-xs);
      flex-wrap: wrap;
    }
    .workflow-name {
      font-size: var(--font-size-base);
      font-weight: var(--font-weight-bold);
      color: var(--text-primary);
    }
    .disabled-badge {
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-medium);
      padding: 1px 6px;
      border-radius: 4px;
      background: var(--bg-pill);
      color: var(--text-secondary);
    }

    /* Stats row */
    .stats-row {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      margin-top: 4px;
      flex-wrap: wrap;
    }
    .trigger-pill {
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-medium);
      padding: 1px 6px;
      border-radius: 4px;
    }
    .stat {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: var(--font-size-xs);
      color: var(--text-secondary);
    }

    /* Description */
    .description {
      font-size: var(--font-size-sm);
      color: var(--text-secondary);
      margin-top: 4px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    /* Last triggered */
    .last-triggered {
      font-size: var(--font-size-xs);
      color: var(--text-tertiary);
      margin-top: 4px;
    }

    /* Toggle switch */
    .toggle-wrapper {
      flex-shrink: 0;
      position: relative;
      display: inline-flex;
      align-items: center;
      cursor: pointer;
      padding-top: 6px;
    }
    .toggle-wrapper input {
      position: absolute;
      opacity: 0;
      width: 0;
      height: 0;
    }
    .toggle-track {
      width: 42px;
      height: 24px;
      border-radius: 12px;
      background: var(--bg-pill);
      position: relative;
      transition: background 200ms ease;
    }
    .toggle-track::before {
      content: '';
      position: absolute;
      top: 2px;
      left: 2px;
      width: 20px;
      height: 20px;
      border-radius: 50%;
      background: white;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
      transition: transform 200ms ease;
    }
    .toggle-wrapper input:checked + .toggle-track {
      background: var(--tint-main);
    }
    .toggle-wrapper input:checked + .toggle-track::before {
      transform: translateX(18px);
    }

    /* Responsive */
    @media (max-width: 768px) {
      .workflow-card {
        --card-padding: 12px;
        border-radius: var(--radius-sm);
        gap: var(--spacing-xs);
      }
      .workflow-name {
        font-size: var(--font-size-sm);
      }
    }
    @media (max-width: 480px) {
      .stats-row {
        gap: var(--spacing-xs);
      }
    }
  `]
})
export class WorkflowCardComponent {
  workflow = input.required<Workflow>();
  index = input(0);
  toggleEnabled = output<boolean>();

  readonly triggerType = computed((): TriggerTypeKey => {
    const triggers = this.workflow().triggers;
    return triggers.length > 0 ? triggers[0].type : 'deviceStateChange';
  });

  readonly triggerIcon = computed(() => TRIGGER_TYPE_ICONS[this.triggerType()]);
  readonly triggerLabel = computed(() => TRIGGER_TYPE_LABELS[this.triggerType()]);

  readonly statusColor = computed(() => {
    const wf = this.workflow();
    if (!wf.isEnabled) return 'var(--status-inactive)';
    if (wf.metadata.consecutiveFailures > 0) return 'var(--status-error)';
    if (wf.metadata.totalExecutions > 0) return 'var(--status-active)';
    return 'var(--tint-main)';
  });

  readonly statusBg = computed(() => {
    return `color-mix(in srgb, ${this.statusColor()} 15%, transparent)`;
  });

  readonly pillBg = computed(() => {
    return `color-mix(in srgb, ${this.statusColor()} 12%, transparent)`;
  });

  onToggleChange(event: Event): void {
    const checked = (event.target as HTMLInputElement).checked;
    this.toggleEnabled.emit(checked);
  }
}
