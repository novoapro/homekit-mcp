import type { PaginatedLogsResponse, LogQueryParams } from '@/types/api-response';
import type { AutomationExecutionLog, Automation } from '@/types/automation-log';
import type { AutomationDefinition } from '@/types/automation-definition';
import type { RESTDevice, RESTScene } from '@/types/homekit-device';

export interface SunEvents {
  sunrise: string | null;
  sunset: string | null;
  locationConfigured: boolean;
  cityName: string | null;
}

export interface AutomationRuntime {
  sunEvents: SunEvents;
}

export interface SubscriptionStatus {
  tier: 'free' | 'pro';
  isPro: boolean;
}

export class SubscriptionRequiredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SubscriptionRequiredError';
  }
}

export interface ApiClient {
  checkHealth(): Promise<boolean>;
  getLogs(params?: LogQueryParams): Promise<PaginatedLogsResponse>;
  clearLogs(): Promise<void>;
  getAutomations(): Promise<Automation[]>;
  getAutomation(automationId: string): Promise<AutomationDefinition>;
  getAutomationLogs(automationId: string, limit?: number): Promise<AutomationExecutionLog[]>;
  updateAutomation(automationId: string, updates: Partial<Automation>): Promise<Automation>;
  createAutomation(automation: Partial<AutomationDefinition>): Promise<AutomationDefinition>;
  deleteAutomation(automationId: string): Promise<void>;
  generateAutomation(prompt: string, deviceIds?: string[], sceneIds?: string[]): Promise<{ id: string; name: string; description: string | null }>;
  improveAutomation(automationId: string, prompt?: string): Promise<AutomationDefinition>;
  getDevices(): Promise<RESTDevice[]>;
  getScenes(): Promise<RESTScene[]>;
  getAutomationRuntime(): Promise<AutomationRuntime>;
  getSubscriptionStatus(): Promise<SubscriptionStatus>;
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
      if (res.status === 402) {
        const reason = await parseError(res);
        throw new SubscriptionRequiredError(reason);
      }
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
      if (res.status === 402) {
        const reason = await parseError(res);
        throw new SubscriptionRequiredError(reason);
      }
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

    async getAutomations() {
      return requestJson<Automation[]>('/automations');
    },

    async getAutomation(automationId: string) {
      return requestJson<AutomationDefinition>(`/automations/${automationId}`);
    },

    async getAutomationLogs(automationId: string, limit?: number) {
      const qs = limit !== undefined ? `?limit=${limit}` : '';
      return requestJson<AutomationExecutionLog[]>(`/automations/${automationId}/logs${qs}`);
    },

    async updateAutomation(automationId: string, updates: Partial<Automation>) {
      return requestJson<Automation>(`/automations/${automationId}`, {
        method: 'PUT',
        body: JSON.stringify(updates),
      });
    },

    async createAutomation(automation: Partial<AutomationDefinition>) {
      return requestJson<AutomationDefinition>('/automations', {
        method: 'POST',
        body: JSON.stringify(automation),
      });
    },

    async deleteAutomation(automationId: string) {
      await requestVoid(`/automations/${automationId}`, { method: 'DELETE' });
    },

    async generateAutomation(prompt: string, deviceIds?: string[], sceneIds?: string[]) {
      const body: Record<string, unknown> = { prompt };
      if (deviceIds && deviceIds.length > 0) body.deviceIds = deviceIds;
      if (sceneIds && sceneIds.length > 0) body.sceneIds = sceneIds;
      return requestJson<{ id: string; name: string; description: string | null }>('/automations/generate', {
        method: 'POST',
        body: JSON.stringify(body),
      }, 90_000);
    },

    async improveAutomation(automationId: string, prompt?: string) {
      const body: Record<string, unknown> = {};
      if (prompt) body.prompt = prompt;
      return requestJson<AutomationDefinition>(`/automations/${automationId}/improve`, {
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

    async getAutomationRuntime() {
      return requestJson<AutomationRuntime>('/automation-runtime');
    },

    async getSubscriptionStatus() {
      return requestJson<SubscriptionStatus>('/subscription/status');
    },
  };
}
