import { Component, inject, signal, effect, OnInit, OnDestroy } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { Location } from '@angular/common';
import { Subscription } from 'rxjs';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { WebSocketService } from '../../core/services/websocket.service';
import { MobileTopBarService } from '../../core/services/mobile-topbar.service';
import { WorkflowExecutionLog } from '../../core/models/workflow-log.model';
import { WorkflowLogRowComponent } from './components/workflow-log-row.component';
import { EmptyStateComponent } from '../../shared/components/empty-state.component';
import { IconComponent } from '../../shared/components/icon.component';
import { PullToRefreshDirective } from '../../shared/directives/pull-to-refresh.directive';

@Component({
  selector: 'app-workflow-execution-list',
  standalone: true,
  imports: [WorkflowLogRowComponent, EmptyStateComponent, IconComponent, PullToRefreshDirective],
  template: `
    <div class="execution-list-page">
      <!-- Back button -->
      <button class="back-btn" (click)="goBack()">
        <app-icon name="chevron-down" [size]="14" />
        <span>Back to Workflows</span>
      </button>

      <!-- Page header -->
      <div class="page-header">
        <h1 class="page-title">Execution Logs</h1>
        @if (isLoading()) {
          <span class="loading-dot"></span>
        }
      </div>

      <!-- Error -->
      @if (error()) {
        <div class="error-banner animate-fade-in">
          <app-icon name="exclamation-triangle" [size]="16" />
          <span>{{ error() }}</span>
        </div>
      }

      <!-- Skeleton Loading -->
      @if (isLoading() && executionLogs().length === 0) {
        <div class="skeleton-list">
          @for (i of [1,2,3,4,5,6,7,8,9,10]; track i) {
            <div class="skeleton-card skeleton" [style.animation-delay.ms]="i * 100"></div>
          }
        </div>
      }

      <!-- Empty -->
      @if (!isLoading() && executionLogs().length === 0 && !error()) {
        <app-empty-state
          icon="bolt-circle-fill"
          title="No executions"
          message="This workflow hasn't been executed yet. Trigger it and execution logs will appear here."
        />
      }

      <!-- Execution list -->
      @if (executionLogs().length > 0) {
        <div class="log-list" [appPullToRefresh]="onPullRefresh">
          @for (log of executionLogs(); track log.id; let i = $index) {
            <app-workflow-log-row [log]="log" [index]="i" (click)="openDetail(log)" />
          }
        </div>
      }
    </div>
  `,
  styles: [`
    :host {
      display: block;
      height: 100%;
    }
    .execution-list-page {
      display: flex;
      flex-direction: column;
      height: 100%;
      background: var(--bg-main);
      max-width: 800px;
      margin: 0 auto;
      padding: 0 var(--spacing-md);
    }
    .back-btn {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 8px 14px;
      border-radius: var(--radius-md);
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-semibold);
      color: var(--tint-main);
      cursor: pointer;
      transition: background var(--transition-fast);
      margin-top: var(--spacing-md);
      align-self: flex-start;
      background: none;
      border: none;
      font-family: inherit;
    }
    .back-btn app-icon {
      transform: rotate(90deg);
    }
    .back-btn:hover {
      background: color-mix(in srgb, var(--tint-main) 10%, transparent);
    }
    .page-header {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: var(--spacing-sm) 0;
    }
    .page-title {
      font-size: var(--font-size-2xl);
      font-weight: var(--font-weight-black);
      color: var(--text-primary);
      margin: 0;
      letter-spacing: -0.03em;
    }
    .loading-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: var(--tint-main);
      animation: pulse 1.5s ease-in-out infinite;
      flex-shrink: 0;
    }
    .error-banner {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: var(--spacing-sm) 0;
      color: var(--status-error);
      font-size: var(--font-size-sm);
    }
    .skeleton-list {
      padding: var(--spacing-sm) 0;
    }
    .skeleton-card {
      height: 80px;
      margin-bottom: var(--card-gap);
      border-radius: var(--radius-md);
    }
    .log-list {
      flex: 1;
      overflow-y: auto;
      padding: var(--spacing-sm) 0 calc(var(--spacing-3xl) + env(safe-area-inset-bottom, 0px));
    }
    @media (max-width: 768px) {
      .execution-list-page {
        padding: 0 var(--spacing-sm);
      }
      .page-header {
        display: none;
      }
      .skeleton-card {
        border-radius: var(--radius-sm);
      }
    }
  `]
})
export class WorkflowExecutionListComponent implements OnInit, OnDestroy {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private api = inject(ApiService);
  private config = inject(ConfigService);
  private wsService = inject(WebSocketService);
  private topBar = inject(MobileTopBarService);
  private wsSub?: Subscription;
  private wsClearedSub?: Subscription;

  executionLogs = signal<WorkflowExecutionLog[]>([]);
  isLoading = signal(false);
  error = signal<string | null>(null);

  private workflowId = '';

  private topBarEffect = effect(() => {
    this.topBar.set('Execution Logs', null, this.isLoading());
  });

  ngOnInit(): void {
    this.workflowId = this.route.snapshot.paramMap.get('workflowId') || '';
    this.loadLogs();

    // Connect WebSocket for real-time workflow log updates
    if (this.config.websocketEnabled() && !this.wsService.isConnected()) {
      this.wsService.connect();
    }
    this.wsClearedSub = this.wsService.logsCleared$.subscribe(() => {
      this.executionLogs.set([]);
    });
    this.wsSub = this.wsService.workflowLogMessage$.subscribe(msg => {
      if (msg.data.workflowId !== this.workflowId) return;

      const current = this.executionLogs();
      if (msg.type === 'new') {
        if (!current.some(l => l.id === msg.data.id)) {
          this.executionLogs.set([msg.data, ...current]);
        }
      } else if (msg.type === 'updated') {
        const idx = current.findIndex(l => l.id === msg.data.id);
        if (idx >= 0) {
          const existing = current[idx].status;
          if (existing !== 'running' && msg.data.status === 'running') return;
          const updated = [...current];
          updated[idx] = msg.data;
          this.executionLogs.set(updated);
        }
      }
    });
  }

  ngOnDestroy(): void {
    this.wsSub?.unsubscribe();
    this.wsClearedSub?.unsubscribe();
  }

  loadLogs(): void {
    if (!this.workflowId) return;

    this.isLoading.set(true);
    this.error.set(null);

    this.api.getWorkflowLogs(this.workflowId, 100).subscribe({
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
    this.router.navigate(['/workflows', this.workflowId, log.id]);
  }

  goBack(): void {
    if (window.history.length > 1) {
      this.location.back();
    } else {
      this.router.navigate(['/workflows', this.workflowId, 'definition']);
    }
  }

  onPullRefresh = (): void => {
    this.loadLogs();
  };
}
