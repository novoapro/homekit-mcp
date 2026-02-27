import { Component, inject, signal, effect, OnInit, OnDestroy } from '@angular/core';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { WebSocketService } from '../../core/services/websocket.service';
import { MobileTopBarService } from '../../core/services/mobile-topbar.service';
import { Workflow } from '../../core/models/workflow-log.model';
import { WorkflowCardComponent } from './components/workflow-card.component';
import { EmptyStateComponent } from '../../shared/components/empty-state.component';
import { IconComponent } from '../../shared/components/icon.component';
import { PullToRefreshDirective } from '../../shared/directives/pull-to-refresh.directive';

@Component({
  selector: 'app-workflow-logs',
  standalone: true,
  imports: [WorkflowCardComponent, EmptyStateComponent, IconComponent, PullToRefreshDirective],
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
  isLoading = signal(false);
  error = signal<string | null>(null);

  private topBarEffect = effect(() => {
    this.topBar.set('Workflows', null, this.isLoading());
  });

  ngOnInit(): void {
    this.loadWorkflows();

    // Connect WebSocket for real-time workflow updates
    if (this.config.websocketEnabled() && !this.wsService.isConnected()) {
      this.wsService.connect();
    }
    this.wsSub = this.wsService.workflowsUpdated$.subscribe(workflows => {
      this.workflows.set(workflows);
    });
  }

  ngOnDestroy(): void {
    this.wsSub?.unsubscribe();
  }

  loadWorkflows(): void {
    this.isLoading.set(true);
    this.error.set(null);

    this.api.getWorkflows().subscribe({
      next: (wfs) => {
        this.workflows.set(wfs);
        this.isLoading.set(false);
      },
      error: (err) => {
        this.error.set(err?.message || 'Failed to load workflows');
        this.isLoading.set(false);
      }
    });
  }

  openWorkflow(workflow: Workflow): void {
    this.router.navigate(['/workflows', workflow.id, 'definition']);
  }

  toggleWorkflow(workflow: Workflow, enabled: boolean): void {
    // Optimistic update
    const current = this.workflows();
    this.workflows.set(
      current.map(w => w.id === workflow.id ? { ...w, isEnabled: enabled } : w)
    );

    this.api.updateWorkflow(workflow.id, { isEnabled: enabled }).subscribe({
      next: (updated) => {
        this.workflows.set(
          this.workflows().map(w => w.id === updated.id ? updated : w)
        );
      },
      error: () => {
        // Revert
        this.workflows.set(
          this.workflows().map(w => w.id === workflow.id ? { ...w, isEnabled: !enabled } : w)
        );
        this.error.set('Failed to update workflow');
      }
    });
  }

  onPullRefresh = (): void => {
    this.loadWorkflows();
  };
}
