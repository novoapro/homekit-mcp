import { Component, inject, signal, effect, OnInit, OnDestroy } from '@angular/core';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { WebSocketService } from '../../core/services/websocket.service';
import { MobileTopBarService } from '../../core/services/mobile-topbar.service';
import { Workflow, WorkflowExecutionLog } from '../../core/models/workflow-log.model';
import { WorkflowLogRowComponent } from './components/workflow-log-row.component';
import { EmptyStateComponent } from '../../shared/components/empty-state.component';
import { IconComponent } from '../../shared/components/icon.component';
import { PullToRefreshDirective } from '../../shared/directives/pull-to-refresh.directive';

@Component({
  selector: 'app-workflow-logs',
  standalone: true,
  imports: [FormsModule, WorkflowLogRowComponent, EmptyStateComponent, IconComponent, PullToRefreshDirective],
  templateUrl: './workflow-logs.component.html',
  styleUrl: './workflow-logs.component.css',
})
export class WorkflowLogsComponent implements OnInit, OnDestroy {
  private api = inject(ApiService);
  private router = inject(Router);
  private config = inject(ConfigService);
  private wsService = inject(WebSocketService);
  private topBar = inject(MobileTopBarService);
  private wsSub?: Subscription;

  workflows = signal<Workflow[]>([]);
  selectedWorkflowId = signal<string>('');
  executionLogs = signal<WorkflowExecutionLog[]>([]);
  isLoading = signal(false);
  error = signal<string | null>(null);

  private topBarEffect = effect(() => {
    this.topBar.set('Workflows', null, this.isLoading());
  });

  ngOnInit(): void {
    this.loadWorkflows();

    // Connect WebSocket for real-time workflow log updates
    if (this.config.websocketEnabled() && !this.wsService.isConnected()) {
      this.wsService.connect();
    }
    this.wsSub = this.wsService.workflowLogMessage$.subscribe(msg => {
      const selectedId = this.selectedWorkflowId();
      if (!selectedId || msg.data.workflowId !== selectedId) return;

      const current = this.executionLogs();
      if (msg.type === 'new') {
        if (!current.some(l => l.id === msg.data.id)) {
          this.executionLogs.set([msg.data, ...current]);
        }
      } else if (msg.type === 'updated') {
        const idx = current.findIndex(l => l.id === msg.data.id);
        if (idx >= 0) {
          const updated = [...current];
          updated[idx] = msg.data;
          this.executionLogs.set(updated);
        }
      }
    });
  }

  ngOnDestroy(): void {
    this.wsSub?.unsubscribe();
  }

  loadWorkflows(): void {
    this.api.getWorkflows().subscribe({
      next: (wfs) => {
        this.workflows.set(wfs);
        if (wfs.length > 0 && !this.selectedWorkflowId()) {
          this.selectedWorkflowId.set(wfs[0].id);
          this.loadLogs();
        }
      },
      error: (err) => {
        this.error.set(err?.message || 'Failed to load workflows');
      }
    });
  }

  onWorkflowChange(workflowId: string): void {
    this.selectedWorkflowId.set(workflowId);
    this.loadLogs();
  }

  loadLogs(): void {
    const wfId = this.selectedWorkflowId();
    if (!wfId) return;

    this.isLoading.set(true);
    this.error.set(null);

    this.api.getWorkflowLogs(wfId, 100).subscribe({
      next: (logs) => {
        this.executionLogs.set(logs);
        this.isLoading.set(false);
      },
      error: (err) => {
        this.error.set(err?.message || 'Failed to load execution logs');
        this.isLoading.set(false);
      }
    });
  }

  openDetail(log: WorkflowExecutionLog): void {
    this.router.navigate(['/workflows', log.workflowId, log.id]);
  }

  onPullRefresh = (): void => {
    this.loadLogs();
  };

  refresh(): void {
    this.loadLogs();
  }
}
