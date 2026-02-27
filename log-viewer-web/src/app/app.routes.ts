import { Routes } from '@angular/router';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { ConfigService } from './core/services/config.service';

export const configGuard = () => {
  const config = inject(ConfigService);
  const router = inject(Router);
  if (!config.isConfigured()) {
    return router.parseUrl('/settings');
  }
  return true;
};

export const routes: Routes = [
  { path: '', redirectTo: 'workflows', pathMatch: 'full' },
  {
    path: 'logs',
    canActivate: [configGuard],
    data: { title: 'Activity Log' },
    loadComponent: () => import('./features/logs/logs.component').then(m => m.LogsComponent),
  },
  {
    path: 'workflows',
    canActivate: [configGuard],
    data: { title: 'Workflows' },
    loadComponent: () => import('./features/workflows/workflow-logs.component').then(m => m.WorkflowLogsComponent),
  },
  {
    path: 'workflows/:workflowId/definition',
    canActivate: [configGuard],
    data: { title: 'Workflow Definition' },
    loadComponent: () => import('./features/workflows/workflow-definition.component').then(m => m.WorkflowDefinitionComponent),
  },
  {
    path: 'workflows/:workflowId',
    canActivate: [configGuard],
    data: { title: 'Workflow Logs' },
    loadComponent: () => import('./features/workflows/workflow-execution-list.component').then(m => m.WorkflowExecutionListComponent),
  },
  {
    path: 'workflows/:workflowId/:logId',
    canActivate: [configGuard],
    data: { title: 'Workflow Detail' },
    loadComponent: () => import('./features/workflows/workflow-detail.component').then(m => m.WorkflowDetailComponent),
  },
  {
    path: 'settings',
    data: { title: 'Settings' },
    loadComponent: () => import('./features/settings/settings.component').then(m => m.SettingsComponent),
  },
];
