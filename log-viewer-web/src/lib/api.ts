import type { PaginatedLogsResponse, LogQueryParams } from '@/types/api-response';
import type { WorkflowExecutionLog, Workflow } from '@/types/workflow-log';
import type { WorkflowDefinition } from '@/types/workflow-definition';
import type { RESTDevice, RESTScene } from '@/types/homekit-device';

export interface ApiClient {
  checkHealth(): Promise<boolean>;
  getLogs(params?: LogQueryParams): Promise<PaginatedLogsResponse>;
  clearLogs(): Promise<void>;
  getWorkflows(): Promise<Workflow[]>;
  getWorkflow(workflowId: string): Promise<WorkflowDefinition>;
  getWorkflowLogs(workflowId: string, limit?: number): Promise<WorkflowExecutionLog[]>;
  updateWorkflow(workflowId: string, updates: Partial<Workflow>): Promise<Workflow>;
  createWorkflow(workflow: Partial<WorkflowDefinition>): Promise<WorkflowDefinition>;
  deleteWorkflow(workflowId: string): Promise<void>;
  getDevices(): Promise<RESTDevice[]>;
  getScenes(): Promise<RESTScene[]>;
}

export function createApiClient(baseUrl: string, bearerToken: string): ApiClient {
  async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...((options.headers as Record<string, string>) ?? {}),
    };

    // Add auth header for all endpoints except /health
    if (!path.endsWith('/health') && bearerToken) {
      headers['Authorization'] = `Bearer ${bearerToken}`;
    }

    const res = await fetch(`${baseUrl}${path}`, {
      ...options,
      headers,
    });

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${res.statusText}`);
    }

    const text = await res.text();
    if (!text) return undefined as T;

    try {
      return JSON.parse(text) as T;
    } catch {
      return text as T;
    }
  }

  return {
    async checkHealth() {
      try {
        const res = await fetch(`${baseUrl}/health`);
        const text = await res.text();
        return text === 'ok';
      } catch {
        return false;
      }
    },

    async getLogs(params: LogQueryParams = {}) {
      const searchParams = new URLSearchParams();
      if (params.categories?.length) searchParams.set('categories', params.categories.join(','));
      if (params.device_name) searchParams.set('device_name', params.device_name);
      if (params.date) searchParams.set('date', params.date);
      if (params.from) searchParams.set('from', params.from);
      if (params.to) searchParams.set('to', params.to);
      if (params.offset !== undefined) searchParams.set('offset', String(params.offset));
      if (params.limit !== undefined) searchParams.set('limit', String(params.limit));

      const qs = searchParams.toString();
      return request<PaginatedLogsResponse>(`/logs${qs ? `?${qs}` : ''}`);
    },

    async clearLogs() {
      await request('/logs', { method: 'DELETE' });
    },

    async getWorkflows() {
      return request<Workflow[]>('/workflows');
    },

    async getWorkflow(workflowId: string) {
      return request<WorkflowDefinition>(`/workflows/${workflowId}`);
    },

    async getWorkflowLogs(workflowId: string, limit?: number) {
      const qs = limit !== undefined ? `?limit=${limit}` : '';
      return request<WorkflowExecutionLog[]>(`/workflows/${workflowId}/logs${qs}`);
    },

    async updateWorkflow(workflowId: string, updates: Partial<Workflow>) {
      return request<Workflow>(`/workflows/${workflowId}`, {
        method: 'PUT',
        body: JSON.stringify(updates),
      });
    },

    async createWorkflow(workflow: Partial<WorkflowDefinition>) {
      return request<WorkflowDefinition>('/workflows', {
        method: 'POST',
        body: JSON.stringify(workflow),
      });
    },

    async deleteWorkflow(workflowId: string) {
      await request(`/workflows/${workflowId}`, { method: 'DELETE' });
    },

    async getDevices() {
      return request<RESTDevice[]>('/devices');
    },

    async getScenes() {
      return request<RESTScene[]>('/scenes');
    },
  };
}
