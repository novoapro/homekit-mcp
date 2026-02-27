import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { Location } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { MobileTopBarService } from '../../core/services/mobile-topbar.service';
import { WorkflowDefinition } from '../../core/models/workflow-definition.model';
import { formatRetriggerPolicy } from '../../core/utils/workflow-definition-utils';
import { IconComponent } from '../../shared/components/icon.component';
import { RelativeTimePipe } from '../../shared/pipes/relative-time.pipe';
import { DefinitionTriggerComponent } from './components/definition-trigger.component';
import { DefinitionConditionComponent } from './components/definition-condition.component';
import { DefinitionBlockTreeComponent } from './components/definition-block-tree.component';
import { PullToRefreshDirective } from '../../shared/directives/pull-to-refresh.directive';

@Component({
  selector: 'app-workflow-definition',
  standalone: true,
  imports: [
    IconComponent, RelativeTimePipe, PullToRefreshDirective,
    DefinitionTriggerComponent, DefinitionConditionComponent, DefinitionBlockTreeComponent,
  ],
  templateUrl: './workflow-definition.component.html',
  styleUrl: './workflow-definition.component.css',
})
export class WorkflowDefinitionComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private api = inject(ApiService);
  private topBar = inject(MobileTopBarService);

  workflow = signal<WorkflowDefinition | null>(null);
  isLoading = signal(true);
  error = signal<string | null>(null);

  private workflowId = '';

  readonly retriggerPolicyLabel = computed(() => {
    const wf = this.workflow();
    return wf ? formatRetriggerPolicy(wf.retriggerPolicy) : '';
  });

  onPullRefresh = (): void => {
    this.loadWorkflow();
  };

  ngOnInit(): void {
    this.workflowId = this.route.snapshot.paramMap.get('workflowId') || '';
    this.loadWorkflow();
  }

  private loadWorkflow(): void {
    if (!this.workflowId) return;

    this.isLoading.set(true);
    this.error.set(null);

    this.api.getWorkflow(this.workflowId).subscribe({
      next: (wf) => {
        this.workflow.set(wf);
        this.isLoading.set(false);
        this.topBar.set(wf.name, null, false);
      },
      error: (err) => {
        this.error.set(err?.message || 'Failed to load workflow');
        this.isLoading.set(false);
      }
    });
  }

  goBack(): void {
    if (window.history.length > 1) {
      this.location.back();
    } else {
      this.router.navigate(['/workflows']);
    }
  }

  viewExecutionLogs(): void {
    this.router.navigate(['/workflows', this.workflowId]);
  }

  formatDate(iso: string): string {
    const d = new Date(iso);
    return d.toLocaleString(undefined, {
      month: 'short', day: 'numeric', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  }
}
