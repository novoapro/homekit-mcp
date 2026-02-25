import { Component, input, output, signal, computed } from '@angular/core';
import { trigger, transition, style, animate } from '@angular/animations';
import { StateChangeLog, LogCategory, CATEGORY_META } from '../../../core/models/state-change-log.model';
import { characteristicDisplayName, formatCharacteristicValue } from '../../../core/utils/characteristic-types';
import { CategoryIconComponent } from '../../../shared/components/category-icon.component';
import { IconComponent } from '../../../shared/components/icon.component';
import { LogDetailPanelComponent } from './log-detail-panel.component';

@Component({
  selector: 'app-log-row',
  standalone: true,
  imports: [CategoryIconComponent, IconComponent, LogDetailPanelComponent],
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
  navigateToWorkflow = output<{ workflowId: string; logId: string }>();

  expanded = signal(false);

  readonly isExpandable = computed(() => {
    const l = this.log();
    return !!(l.detailedRequestBody || l.requestBody || l.responseBody);
  });

  readonly isError = computed(() => {
    const l = this.log();
    const cat = l.category;
    if (cat === LogCategory.WorkflowError && l.returnOutcome && l.returnOutcome !== 'error') {
      return false;
    }
    return cat === LogCategory.WebhookError ||
      cat === LogCategory.ServerError ||
      cat === LogCategory.WorkflowError ||
      cat === LogCategory.SceneError;
  });

  readonly categoryColor = computed(() => {
    const l = this.log();
    if (l.category === LogCategory.WorkflowError && l.returnOutcome) {
      if (l.returnOutcome === 'success') return 'var(--status-active)';
      if (l.returnOutcome === 'cancelled') return 'var(--status-warning)';
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

  readonly showServiceBadge = computed(() => {
    const l = this.log();
    return l.serviceName &&
      l.category !== LogCategory.McpCall &&
      l.category !== LogCategory.RestCall;
  });

  readonly isWorkflowLog = computed(() => {
    const cat = this.log().category;
    return cat === LogCategory.WorkflowExecution || cat === LogCategory.WorkflowError;
  });

  readonly workflowStatus = computed(() => {
    const l = this.log();
    if (!this.isWorkflowLog()) return null;
    return l.newValue as string | null;
  });

  toggle(): void {
    if (this.isWorkflowLog()) {
      const l = this.log();
      this.navigateToWorkflow.emit({ workflowId: l.deviceId, logId: l.id });
      return;
    }
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
