import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useMemo,
  useRef,
  type ReactNode,
} from 'react';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from './WebSocketContext';
import type { RESTDevice, RESTScene, RESTService, RESTCharacteristic } from '@/types/homekit-device';

interface DeviceRegistryContextValue {
  devices: RESTDevice[];
  scenes: RESTScene[];
  isLoading: boolean;
  lookupDevice: (deviceId: string) => RESTDevice | undefined;
  lookupService: (deviceId: string, serviceId: string) => RESTService | undefined;
  lookupCharacteristic: (deviceId: string, charId: string) => RESTCharacteristic | undefined;
  lookupScene: (sceneId: string) => RESTScene | undefined;
  describeDeviceCharacteristic: (deviceId: string, serviceId?: string, charType?: string) => string;
  refresh: () => void;
}

const DeviceRegistryContext = createContext<DeviceRegistryContextValue | null>(null);

export function DeviceRegistryProvider({ children }: { children: ReactNode }) {
  const api = useApi();
  const ws = useWebSocket();

  const [devices, setDevices] = useState<RESTDevice[]>([]);
  const [scenes, setScenes] = useState<RESTScene[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  const deviceMapRef = useRef(new Map<string, RESTDevice>());
  const sceneMapRef = useRef(new Map<string, RESTScene>());

  const loadRegistry = useCallback(async () => {
    setIsLoading(true);
    try {
      const [devs, scns] = await Promise.all([api.getDevices(), api.getScenes()]);
      setDevices(devs);
      setScenes(scns);
      deviceMapRef.current = new Map(devs.map(d => [d.id, d]));
      sceneMapRef.current = new Map(scns.map(s => [s.id, s]));
    } catch {
      // Silently fail — devices/scenes are optional
    } finally {
      setIsLoading(false);
    }
  }, [api]);

  // Load on mount
  useEffect(() => {
    loadRegistry();
  }, [loadRegistry]);

  // Reload on WebSocket events
  useEffect(() => {
    const unsub1 = ws.onDevicesUpdated(() => loadRegistry());
    const unsub2 = ws.onReconnected(() => loadRegistry());
    return () => { unsub1(); unsub2(); };
  }, [ws, loadRegistry]);

  const lookupDevice = useCallback((deviceId: string) => {
    return deviceMapRef.current.get(deviceId);
  }, []);

  const lookupService = useCallback((deviceId: string, serviceId: string) => {
    return deviceMapRef.current.get(deviceId)?.services.find(s => s.id === serviceId);
  }, []);

  const lookupCharacteristic = useCallback((deviceId: string, charId: string) => {
    const device = deviceMapRef.current.get(deviceId);
    if (!device) return undefined;
    for (const svc of device.services) {
      const char = svc.characteristics.find(c => c.id === charId);
      if (char) return char;
    }
    return undefined;
  }, []);

  const lookupScene = useCallback((sceneId: string) => {
    return sceneMapRef.current.get(sceneId);
  }, []);

  const describeDeviceCharacteristic = useCallback((deviceId: string, _serviceId?: string, charType?: string) => {
    const device = deviceMapRef.current.get(deviceId);
    if (!device) return deviceId;
    const parts: string[] = [device.name];
    if (device.room) parts.push(`(${device.room})`);
    if (charType) parts.push(`→ ${charType}`);
    return parts.join(' ');
  }, []);

  const value = useMemo<DeviceRegistryContextValue>(
    () => ({
      devices,
      scenes,
      isLoading,
      lookupDevice,
      lookupService,
      lookupCharacteristic,
      lookupScene,
      describeDeviceCharacteristic,
      refresh: loadRegistry,
    }),
    [devices, scenes, isLoading, lookupDevice, lookupService, lookupCharacteristic, lookupScene, describeDeviceCharacteristic, loadRegistry],
  );

  return (
    <DeviceRegistryContext.Provider value={value}>
      {children}
    </DeviceRegistryContext.Provider>
  );
}

export function useDeviceRegistry(): DeviceRegistryContextValue {
  const ctx = useContext(DeviceRegistryContext);
  if (!ctx) throw new Error('useDeviceRegistry must be used within DeviceRegistryProvider');
  return ctx;
}
