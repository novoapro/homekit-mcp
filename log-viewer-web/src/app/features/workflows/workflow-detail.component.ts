import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { WorkflowExecutionLog, ExecutionStatus } from '../../core/models/workflow-log.model';
import { IconComponent } from '../../shared/components/icon.component';
import { StatusBadgeComponent } from '../../shared/components/status-badge.component';
import { ConditionTreeComponent } from './components/condition-tree.component';
import { BlockTreeComponent } from './components/block-tree.component';
import { DurationPipe } from '../../shared/pipes/duration.pipe';
import { PullToRefreshDirective } from '../../shared/directives/pull-to-refresh.directive';

@Component({
  selector: 'app-workflow-detail',
  standalone: true,
  imports: [IconComponent, StatusBadgeComponent, ConditionTreeComponent, BlockTreeComponent, DurationPipe, PullToRefreshDirective],
  templateUrl: './workflow-detail.component.html',
  styleUrl: './workflow-detail.component.css',
})
export class WorkflowDetailComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private api = inject(ApiService);

  log = signal<WorkflowExecutionLog | null>(null);
  isLoading = signal(true);
  error = signal<string | null>(null);

  readonly statusColor = computed(() => {
    const s = this.log()?.status;
    if (!s) return 'var(--text-secondary)';
    const map: Record<ExecutionStatus, string> = {
      running: 'var(--status-running)',
      success: 'var(--status-active)',
      failure: 'var(--status-error)',
      skipped: 'var(--status-inactive)',
      conditionNotMet: 'var(--status-warning)',
      cancelled: 'var(--status-inactive)',
    };
    return map[s] || 'var(--text-secondary)';
  });

  readonly statusIcon = computed(() => {
    const s = this.log()?.status;
    if (!s) return 'bolt-circle-fill';
    const map: Record<ExecutionStatus, string> = {
      running: 'spinner',
      success: 'checkmark-circle-fill',
      failure: 'xmark-circle-fill',
      skipped: 'forward-circle-fill',
      conditionNotMet: 'exclamation-circle-fill',
      cancelled: 'slash-circle-fill',
    };
    return map[s] || 'bolt-circle-fill';
  });

  readonly triggerValueChange = computed(() => {
    const te = this.log()?.triggerEvent;
    if (!te) return null;
    if (te.oldValue === undefined && te.newValue === undefined) return null;
    return {
      old: this.formatValue(te.oldValue),
      new: this.formatValue(te.newValue),
    };
  });

  onPullRefresh = (): void => {
    this.loadDetail();
  };

  ngOnInit(): void {
    this.loadDetail();
  }

  private loadDetail(): void {
    const workflowId = this.route.snapshot.paramMap.get('workflowId')!;
    const logId = this.route.snapshot.paramMap.get('logId')!;

    this.api.getWorkflowLogs(workflowId, 100).subscribe({
      next: (logs) => {
        const found = logs.find(l => l.id === logId);
        this.log.set(found || null);
        this.isLoading.set(false);
        if (!found) {
          this.error.set('Execution log not found');
        }
      },
      error: (err) => {
        this.error.set(err?.message || 'Failed to load execution log');
        this.isLoading.set(false);
      }
    });
  }

  goBack(): void {
    this.router.navigate(['/workflows']);
  }

  formatDate(iso: string): string {
    const d = new Date(iso);
    return d.toLocaleString(undefined, {
      month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
  }

  private formatValue(val: any): string {
    if (val === undefined || val === null) return '—';
    if (typeof val === 'boolean') return val ? 'on' : 'off';
    return String(val);
  }
}
