import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createApiClient } from './api';

describe('createApiClient', () => {
  const baseUrl = 'http://localhost:3000';
  const token = 'test-token-123';

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  describe('checkHealth', () => {
    it('returns true when server responds ok', async () => {
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
        text: () => Promise.resolve('ok'),
      }));

      const client = createApiClient(baseUrl, token);
      expect(await client.checkHealth()).toBe(true);

      expect(fetch).toHaveBeenCalledWith('http://localhost:3000/health');
    });

    it('returns false on network error', async () => {
      vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('Connection refused')));

      const client = createApiClient(baseUrl, token);
      expect(await client.checkHealth()).toBe(false);
    });

    it('returns false when response is not ok', async () => {
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
        text: () => Promise.resolve('error'),
      }));

      const client = createApiClient(baseUrl, token);
      expect(await client.checkHealth()).toBe(false);
    });
  });

  describe('authorization', () => {
    it('includes bearer token on non-health endpoints', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        text: () => Promise.resolve('[]'),
      });
      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.getDevices();

      const [, options] = mockFetch.mock.calls[0]!;
      expect(options.headers['Authorization']).toBe(`Bearer ${token}`);
    });

    it('does not include auth header on health endpoint', async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        text: () => Promise.resolve('ok'),
      });
      vi.stubGlobal('fetch', mockFetch);

      const client = createApiClient(baseUrl, token);
      await client.checkHealth();

      // checkHealth uses plain fetch without headers
      expect(mockFetch).toHaveBeenCalledWith('http://localhost:3000/health');
    });
  });

  describe('error handling', () => {
    it('throws on non-ok responses', async () => {
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
        ok: false,
        status: 401,
        statusText: 'Unauthorized',
        text: () => Promise.resolve('{"error":"Invalid token"}'),
      }));

      const client = createApiClient(baseUrl, token);
      await expect(client.getDevices()).rejects.toThrow('Invalid token');
    });
  });
});
