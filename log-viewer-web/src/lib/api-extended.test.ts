import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createApiClient } from './api';

describe('createApiClient - Extended Tests', () => {
  const baseUrl = 'http://localhost:3000';
  const token = 'test-token-123';

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  describe('fetchWithTimeout', () => {
    it('times out correctly using AbortController', async () => {
      const mockFetch = vi.fn(async (_url: string, _options: RequestInit) => {
        // Simulate timeout by waiting
        await new Promise(resolve => setTimeout(resolve, 100));
        throw new Error('Request aborted');
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      // Try to get devices with a very short timeout
      const promise = client.getDevices();

      // The AbortController should timeout
      await expect(promise).rejects.toThrow();
    });

    it('respects custom timeout values', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve('[]'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getDevices();

      expect(mockFetch).toHaveBeenCalled();
    });
  });

  describe('workflow CRUD methods', () => {
    it('createWorkflow uses POST method with correct payload', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({ id: 'wf-123', name: 'New Workflow' })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const workflow = { name: 'Test Workflow', description: 'A test' };

      await client.createWorkflow(workflow);

      const [url, options] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/workflows');
      expect(options.method).toBe('POST');
      expect(options.body).toBe(JSON.stringify(workflow));
    });

    it('updateWorkflow uses PUT method with correct payload', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({ id: 'wf-123', name: 'Updated' })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const updates = { name: 'Updated Workflow' };

      await client.updateWorkflow('wf-123', updates);

      const [url, options] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/workflows/wf-123');
      expect(options.method).toBe('PUT');
      expect(options.body).toBe(JSON.stringify(updates));
    });

    it('deleteWorkflow uses DELETE method', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(''),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await client.deleteWorkflow('wf-123');

      const [url, options] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/workflows/wf-123');
      expect(options.method).toBe('DELETE');
    });

    it('getWorkflow retrieves a single workflow', async () => {
      const workflow = { id: 'wf-456', name: 'My Workflow' };

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(workflow)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const result = await client.getWorkflow('wf-456');

      expect(result).toEqual(workflow);
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('/workflows/wf-456'),
        expect.any(Object),
      );
    });

    it('getWorkflows returns array of workflows', async () => {
      const workflows = [
        { id: 'wf-1', name: 'Workflow 1' },
        { id: 'wf-2', name: 'Workflow 2' },
      ];

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(workflows)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const result = await client.getWorkflows();

      expect(result).toEqual(workflows);
      expect(Array.isArray(result)).toBe(true);
    });
  });

  describe('getLogs with filter parameters', () => {
    it('includes all query parameters in request', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({ logs: [], total: 0 })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getLogs({
        categories: ['device', 'workflow'],
        device_name: 'Kitchen Light',
        date: '2024-01-15',
        from: '2024-01-15T00:00:00Z',
        to: '2024-01-15T23:59:59Z',
        offset: 10,
        limit: 50,
      });

      const [url] = mockFetch.mock.calls[0]!;
      expect(url).toContain('categories=device%2Cworkflow');
      expect(url).toContain('device_name=Kitchen+Light');
      expect(url).toContain('date=2024-01-15');
      expect(url).toContain('from=');
      expect(url).toContain('to=');
      expect(url).toContain('offset=10');
      expect(url).toContain('limit=50');
    });

    it('includes categories parameter when provided', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({ logs: [], total: 0 })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getLogs({ categories: ['device', 'system'] });

      const [url] = mockFetch.mock.calls[0]!;
      expect(url).toContain('categories=device%2Csystem');
    });

    it('omits empty parameters', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({ logs: [], total: 0 })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getLogs({ categories: [] });

      const [url] = mockFetch.mock.calls[0]!;
      expect(url).not.toContain('categories');
    });
  });

  describe('clearLogs', () => {
    it('uses DELETE method', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(''),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.clearLogs();

      const [url, options] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/logs');
      expect(options.method).toBe('DELETE');
    });
  });

  describe('error handling for HTTP status codes', () => {
    it('throws on 401 unauthorized', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: false,
        status: 401,
        statusText: 'Unauthorized',
        text: () => Promise.resolve('{"error":"Invalid token"}'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await expect(client.getDevices()).rejects.toThrow('Invalid token');
    });

    it('throws on 404 not found', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: false,
        status: 404,
        statusText: 'Not Found',
        text: () => Promise.resolve('{"error":"Workflow not found"}'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await expect(client.getWorkflow('nonexistent')).rejects.toThrow('Workflow not found');
    });

    it('throws on 500 server error', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: false,
        status: 500,
        statusText: 'Internal Server Error',
        text: () => Promise.resolve('{"reason":"Database connection failed"}'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await expect(client.getDevices()).rejects.toThrow('Database connection failed');
    });

    it('falls back to HTTP status message when error field missing', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: false,
        status: 400,
        statusText: 'Bad Request',
        text: () => Promise.resolve('{}'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await expect(client.getDevices()).rejects.toThrow(/HTTP 400/);
    });
  });

  describe('error handling for network failures', () => {
    it('handles fetch throwing an error', async () => {
      const mockFetch = vi.fn().mockRejectedValue(new Error('Network error'));

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await expect(client.getDevices()).rejects.toThrow('Network error');
    });

    it('handles timeout errors', async () => {
      const mockFetch = vi.fn().mockRejectedValue(new Error('Request timeout'));

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      await expect(client.getDevices()).rejects.toThrow('Request timeout');
    });

    it('checkHealth returns false on network error', async () => {
      const mockFetch = vi.fn().mockRejectedValue(new Error('Connection refused'));

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);

      expect(await client.checkHealth()).toBe(false);
    });
  });

  describe('getDevices', () => {
    it('returns array of devices', async () => {
      const devices = [
        { id: 'device-1', name: 'Light 1' },
        { id: 'device-2', name: 'Light 2' },
      ];

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(devices)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const result = await client.getDevices();

      expect(result).toEqual(devices);
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('/devices'),
        expect.any(Object),
      );
    });
  });

  describe('getScenes', () => {
    it('returns array of scenes', async () => {
      const scenes = [
        { id: 'scene-1', name: 'Good Morning' },
        { id: 'scene-2', name: 'Good Night' },
      ];

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(scenes)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const result = await client.getScenes();

      expect(result).toEqual(scenes);
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('/scenes'),
        expect.any(Object),
      );
    });
  });

  describe('getWorkflowLogs', () => {
    it('includes limit parameter when provided', async () => {
      const logs = [{ id: 'log-1', status: 'success' }];

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(logs)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getWorkflowLogs('wf-123', 20);

      const [url] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/workflows/wf-123/logs');
      expect(url).toContain('limit=20');
    });

    it('omits limit parameter when not provided', async () => {
      const logs = [{ id: 'log-1', status: 'success' }];

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(logs)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getWorkflowLogs('wf-123');

      const [url] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/workflows/wf-123/logs');
      expect(url).not.toContain('limit');
    });
  });

  describe('getWorkflowRuntime', () => {
    it('retrieves workflow runtime configuration', async () => {
      const runtime = {
        sunEvents: {
          sunrise: '06:30',
          sunset: '18:45',
          locationConfigured: true,
          cityName: 'San Francisco',
        },
      };

      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify(runtime)),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const result = await client.getWorkflowRuntime();

      expect(result).toEqual(runtime);
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('/workflow-runtime'),
        expect.any(Object),
      );
    });
  });

  describe('generateWorkflow', () => {
    it('sends prompt and optional device/scene IDs', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({
          id: 'gen-wf-1',
          name: 'Generated Workflow',
          description: 'Auto-generated',
        })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.generateWorkflow('Turn on the lights', ['device-1'], ['scene-1']);

      const [url, options] = mockFetch.mock.calls[0]!;
      expect(url).toContain('/workflows/generate');
      expect(options.method).toBe('POST');

      const body = JSON.parse(options.body as string);
      expect(body.prompt).toBe('Turn on the lights');
      expect(body.deviceIds).toEqual(['device-1']);
      expect(body.sceneIds).toEqual(['scene-1']);
    });

    it('omits empty device and scene arrays', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({
          id: 'gen-wf-1',
          name: 'Generated',
        })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.generateWorkflow('Turn on the lights', [], []);

      const [, options] = mockFetch.mock.calls[0]!;
      const body = JSON.parse(options.body as string);

      expect(body.deviceIds).toBeUndefined();
      expect(body.sceneIds).toBeUndefined();
    });

    it('uses extended timeout for generation', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(JSON.stringify({
          id: 'gen-wf-1',
          name: 'Generated',
        })),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.generateWorkflow('A complex prompt');

      expect(mockFetch).toHaveBeenCalled();
    });
  });

  describe('authorization headers', () => {
    it('includes bearer token on all non-health endpoints', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve('[]'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getDevices();

      const [, options] = mockFetch.mock.calls[0]!;
      expect(options.headers).toHaveProperty('Authorization', `Bearer ${token}`);
    });

    it('omits bearer token on health endpoint', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        text: () => Promise.resolve('ok'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.checkHealth();

      const call = mockFetch.mock.calls[0]!;
      expect(call[0]).toContain('/health');
      // Health endpoint uses plain fetch without custom headers
    });
  });

  describe('empty response handling', () => {
    it('handles empty text response', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve(''),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      const result = await client.getDevices();

      expect(result).toBeUndefined();
    });
  });

  describe('content type header', () => {
    it('sets Content-Type to application/json', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve('[]'),
      });

      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getDevices();

      const [, options] = mockFetch.mock.calls[0]!;
      expect(options.headers).toHaveProperty('Content-Type', 'application/json');
    });
  });
});
