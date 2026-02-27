import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map, catchError, of } from 'rxjs';
import { ConfigService } from './config.service';
import { PaginatedLogsResponse, LogQueryParams } from '../models/api-response.model';
import { WorkflowExecutionLog, Workflow } from '../models/workflow-log.model';
import { WorkflowDefinition } from '../models/workflow-definition.model';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);
  private config = inject(ConfigService);

  private get base(): string {
    return this.config.baseUrl();
  }

  checkHealth(): Observable<boolean> {
    return this.http.get(`${this.base}/health`, { responseType: 'text' }).pipe(
      map(res => res === 'ok'),
      catchError(() => of(false))
    );
  }

  getLogs(params: LogQueryParams = {}): Observable<PaginatedLogsResponse> {
    let httpParams = new HttpParams();

    if (params.categories?.length) {
      httpParams = httpParams.set('categories', params.categories.join(','));
    }
    if (params.device_name) {
      httpParams = httpParams.set('device_name', params.device_name);
    }
    if (params.date) {
      httpParams = httpParams.set('date', params.date);
    }
    if (params.from) {
      httpParams = httpParams.set('from', params.from);
    }
    if (params.to) {
      httpParams = httpParams.set('to', params.to);
    }
    if (params.offset !== undefined) {
      httpParams = httpParams.set('offset', String(params.offset));
    }
    if (params.limit !== undefined) {
      httpParams = httpParams.set('limit', String(params.limit));
    }

    return this.http.get<PaginatedLogsResponse>(`${this.base}/logs`, { params: httpParams });
  }

  clearLogs(): Observable<{ cleared: boolean }> {
    return this.http.delete<{ cleared: boolean }>(`${this.base}/logs`);
  }

  getWorkflows(): Observable<Workflow[]> {
    return this.http.get<Workflow[]>(`${this.base}/workflows`);
  }

  getWorkflow(workflowId: string): Observable<WorkflowDefinition> {
    return this.http.get<WorkflowDefinition>(`${this.base}/workflows/${workflowId}`);
  }

  getWorkflowLogs(workflowId: string, limit?: number): Observable<WorkflowExecutionLog[]> {
    let httpParams = new HttpParams();
    if (limit !== undefined) {
      httpParams = httpParams.set('limit', String(limit));
    }
    return this.http.get<WorkflowExecutionLog[]>(
      `${this.base}/workflows/${workflowId}/logs`,
      { params: httpParams }
    );
  }

  updateWorkflow(workflowId: string, updates: Partial<Workflow>): Observable<Workflow> {
    return this.http.put<Workflow>(`${this.base}/workflows/${workflowId}`, updates);
  }
}
