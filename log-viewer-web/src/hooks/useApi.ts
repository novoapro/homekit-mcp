import { useMemo } from 'react';
import { useConfig } from '@/contexts/ConfigContext';
import { createApiClient, type ApiClient } from '@/lib/api';

export function useApi(): ApiClient {
  const { baseUrl, config } = useConfig();
  return useMemo(() => createApiClient(baseUrl, config.bearerToken), [baseUrl, config.bearerToken]);
}
