import type { PaginatedLogsResponse, LogQueryParams } from '@/types/api-response';
import type { WorkflowExecutionLog, Workflow } from '@/types/workflow-log';
import type { WorkflowDefinition } from '@/types/workflow-definition';
import type { RESTDevice, RESTScene } from '@/types/homekit-device';

export interface SunEvents {
  sunrise: string | null;
  sunset: string | null;
  locationConfigured: boolean;
  cityName: string | null;
}

export interface WorkflowRuntime {
  sunEvents: SunEvents;
}

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
  generateWorkflow(prompt: string, deviceIds?: string[], sceneIds?: string[]): Promise<{ id: string; name: string; description: string | null }>;
  improveWorkflow(workflowId: string, prompt?: string): Promise<WorkflowDefinition>;
  getDevices(): Promise<RESTDevice[]>;
  getScenes(): Promise<RESTScene[]>;
  getWorkflowRuntime(): Promise<WorkflowRuntime>;
}

const DEFAULT_TIMEOUT = 15_000;

export function createApiClient(baseUrl: string, bearerToken: string): ApiClient {
  function buildHeaders(path: string, options: RequestInit = {}): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...((options.headers as Record<string, string>) ?? {}),
    };
    if (!path.endsWith('/health') && bearerToken) {
      headers['Authorization'] = `Bearer ${bearerToken}`;
    }
    return headers;
  }

  async function parseError(res: Response): Promise<string> {
    const errorText = await res.text();
    let errorMessage = `HTTP ${res.status}: ${res.statusText}`;
    try {
      const errorJson = JSON.parse(errorText);
      if (typeof errorJson.error === 'string') errorMessage = errorJson.error;
      else if (errorJson.reason) errorMessage = errorJson.reason;
    } catch { /* use default message */ }
    return errorMessage;
  }

  async function fetchWithTimeout(url: string, options: RequestInit = {}, timeoutMs = DEFAULT_TIMEOUT): Promise<Response> {
    const controller = new AbortController();
    const existingSignal = options.signal;

    // Link external signal if provided
    if (existingSignal) {
      if (existingSignal.aborted) {
        controller.abort(existingSignal.reason);
      } else {
        existingSignal.addEventListener('abort', () => controller.abort(existingSignal.reason), { once: true });
      }
    }

    const timeout = setTimeout(() => controller.abort('Request timeout'), timeoutMs);

    try {
      return await fetch(url, { ...options, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
  }

  async function requestJson<T>(path: string, options: RequestInit = {}, timeoutMs = DEFAULT_TIMEOUT): Promise<T> {
    const headers = buildHeaders(path, options);
    const res = await fetchWithTimeout(`${baseUrl}${path}`, { ...options, headers }, timeoutMs);

    if (!res.ok) {
      throw new Error(await parseError(res));
    }

    const text = await res.text();
    if (!text) {
      console.warn(`[API] Empty response from ${path}`);
      return undefined as unknown as T;
    }

    return JSON.parse(text) as T;
  }

  async function requestVoid(path: string, options: RequestInit = {}): Promise<void> {
    const headers = buildHeaders(path, options);
    const res = await fetchWithTimeout(`${baseUrl}${path}`, { ...options, headers });

    if (!res.ok) {
      throw new Error(await parseError(res));
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
      return requestJson<PaginatedLogsResponse>(`/logs${qs ? `?${qs}` : ''}`);
    },

    async clearLogs() {
      await requestVoid('/logs', { method: 'DELETE' });
    },

    async getWorkflows() {
      return requestJson<Workflow[]>('/workflows');
    },

    async getWorkflow(workflowId: string) {
      return requestJson<WorkflowDefinition>(`/workflows/${workflowId}`);
    },

    async getWorkflowLogs(workflowId: string, limit?: number) {
      const qs = limit !== undefined ? `?limit=${limit}` : '';
      return requestJson<WorkflowExecutionLog[]>(`/workflows/${workflowId}/logs${qs}`);
    },

    async updateWorkflow(workflowId: string, updates: Partial<Workflow>) {
      return requestJson<Workflow>(`/workflows/${workflowId}`, {
        method: 'PUT',
        body: JSON.stringify(updates),
      });
    },

    async createWorkflow(workflow: Partial<WorkflowDefinition>) {
      return requestJson<WorkflowDefinition>('/workflows', {
        method: 'POST',
        body: JSON.stringify(workflow),
      });
    },

    async deleteWorkflow(workflowId: string) {
      await requestVoid(`/workflows/${workflowId}`, { method: 'DELETE' });
    },

    async generateWorkflow(prompt: string, deviceIds?: string[], sceneIds?: string[]) {
      const body: Record<string, unknown> = { prompt };
      if (deviceIds && deviceIds.length > 0) body.deviceIds = deviceIds;
      if (sceneIds && sceneIds.length > 0) body.sceneIds = sceneIds;
      return requestJson<{ id: string; name: string; description: string | null }>('/workflows/generate', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 90_000);
    },

    async improveWorkflow(workflowId: string, prompt?: string) {
      const body: Record<string, unknown> = {};
      if (prompt) body.prompt = prompt;
      return requestJson<WorkflowDefinition>(`/workflows/${workflowId}/improve`, {
        method: 'POST',
        body: JSON.stringify(body),
      }, 90_000);
    },

    async getDevices() {
      return requestJson<RESTDevice[]>('/devices');
    },

    async getScenes() {
      return requestJson<RESTScene[]>('/scenes');
    },

    async getWorkflowRuntime() {
      return requestJson<WorkflowRuntime>('/workflow-runtime');
    },
  };
}
