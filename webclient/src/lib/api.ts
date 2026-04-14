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
  getStateVariables(): Promise<StateVariable[]>;
  getStateVariable(id: string): Promise<StateVariable>;
  createStateVariable(data: { name: string; displayName?: string; type: string; value: unknown }): Promise<StateVariable>;
  updateStateVariable(id: string, value: unknown): Promise<StateVariable>;
  deleteStateVariable(id: string): Promise<void>;
}

export interface StateVariable {
  id: string;
  name: string;
  displayName?: string;
  type: 'number' | 'string' | 'boolean';
  value: unknown;
  createdAt: string;
  updatedAt: string;
}

/** Human-readable label — prefers displayName, falls back to name. */
export function stateLabel(s: { name: string; displayName?: string }): string {
  return s.displayName || s.name;
}

export class AuthenticationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AuthenticationError';
  }
}

const DEFAULT_TIMEOUT = 15_000;

/** Token resolver: a static string or an async function that returns a fresh token. */
export type TokenResolver = string | (() => Promise<string>);

/** Callback invoked when a token is rejected (401). OAuth clients use this to clear cached tokens. */
export type OnAuthFailure = () => void;

export function createApiClient(
  baseUrl: string,
  tokenResolver: TokenResolver,
  onAuthFailure?: OnAuthFailure,
): ApiClient {

  async function resolveToken(): Promise<string> {
    return typeof tokenResolver === 'function' ? tokenResolver() : tokenResolver;
  }

  async function buildHeaders(path: string, options: RequestInit = {}): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...((options.headers as Record<string, string>) ?? {}),
    };
    if (!path.endsWith('/health')) {
      const token = await resolveToken();
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
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

  async function handleResponse<T>(res: Response, path: string, parse: boolean): Promise<T | void> {
    if (res.status === 401) {
      onAuthFailure?.();
      throw new AuthenticationError(await parseError(res));
    }
    if (res.status === 402) {
      throw new SubscriptionRequiredError(await parseError(res));
    }
    if (!res.ok) {
      throw new Error(await parseError(res));
    }
    if (!parse) return;
    const text = await res.text();
    if (!text) {
      console.warn(`[API] Empty response from ${path}`);
      return undefined as unknown as T;
    }
    return JSON.parse(text) as T;
  }

  async function requestJson<T>(path: string, options: RequestInit = {}, timeoutMs = DEFAULT_TIMEOUT): Promise<T> {
    const headers = await buildHeaders(path, options);
    const res = await fetchWithTimeout(`${baseUrl}${path}`, { ...options, headers }, timeoutMs);
    return handleResponse<T>(res, path, true) as Promise<T>;
  }

  async function requestVoid(path: string, options: RequestInit = {}): Promise<void> {
    const headers = await buildHeaders(path, options);
    const res = await fetchWithTimeout(`${baseUrl}${path}`, { ...options, headers });
    await handleResponse(res, path, false);
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

    async getStateVariables() {
      return requestJson<StateVariable[]>('/state-variables');
    },

    async getStateVariable(id: string) {
      return requestJson<StateVariable>(`/state-variables/${id}`);
    },

    async createStateVariable(data: { name: string; displayName?: string; type: string; value: unknown }) {
      return requestJson<StateVariable>('/state-variables', {
        method: 'POST',
        body: JSON.stringify(data),
      });
    },

    async updateStateVariable(id: string, value: unknown) {
      return requestJson<StateVariable>(`/state-variables/${id}`, {
        method: 'PUT',
        body: JSON.stringify({ value }),
      });
    },

    async deleteStateVariable(id: string) {
      await requestVoid(`/state-variables/${id}`, { method: 'DELETE' });
    },

};
}
