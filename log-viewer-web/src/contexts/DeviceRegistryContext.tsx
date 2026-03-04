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
import { useConfig } from './ConfigContext';
import { useWebSocket } from './WebSocketContext';
import type { RESTDevice, RESTScene, RESTCharacteristic } from '@/types/homekit-device';

interface DeviceRegistryContextValue {
  devices: RESTDevice[];
  scenes: RESTScene[];
  isLoading: boolean;
  lookupDevice: (deviceId: string) => RESTDevice | undefined;
  lookupCharacteristic: (deviceId: string, charId: string) => RESTCharacteristic | undefined;
  lookupScene: (sceneId: string) => RESTScene | undefined;
  refresh: () => Promise<void>;
}

const DeviceRegistryContext = createContext<DeviceRegistryContextValue | null>(null);

export function DeviceRegistryProvider({ children }: { children: ReactNode }) {
  const api = useApi();
  const ws = useWebSocket();
  const { config } = useConfig();

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
    } catch (err) {
      console.warn('[DeviceRegistry] Failed to load devices/scenes:', err);
    } finally {
      setIsLoading(false);
    }
  }, [api]);

  // Load on mount
  useEffect(() => {
    loadRegistry();
  }, [loadRegistry]);

  // Reload on WebSocket structural events
  useEffect(() => {
    const unsub1 = ws.onDevicesUpdated(() => loadRegistry());
    const unsub2 = ws.onReconnected(() => loadRegistry());
    return () => { unsub1(); unsub2(); };
  }, [ws, loadRegistry]);

  // Granular characteristic value updates — patch local state without REST call
  useEffect(() => {
    const unsub = ws.onCharacteristicUpdated((event) => {
      setDevices(prev => {
        const deviceIndex = prev.findIndex(d => d.id === event.deviceId);
        if (deviceIndex === -1) return prev;

        const device = prev[deviceIndex]!;
        let patched = false;

        const updatedServices = device.services.map(svc => {
          if (svc.id !== event.serviceId) return svc;
          const updatedChars = svc.characteristics.map(char => {
            if (char.id !== event.characteristicId) return char;
            patched = true;
            return { ...char, value: event.value };
          });
          return { ...svc, characteristics: updatedChars };
        });

        if (!patched) return prev;

        const updatedDevice = { ...device, services: updatedServices };
        const next = [...prev];
        next[deviceIndex] = updatedDevice;

        // Update the lookup map
        deviceMapRef.current.set(updatedDevice.id, updatedDevice);

        return next;
      });
    });
    return unsub;
  }, [ws]);

  // Periodic polling — always runs regardless of WebSocket status
  useEffect(() => {
    const interval = config.pollingInterval;
    if (interval <= 0) return;

    const timer = setInterval(() => {
      if (document.visibilityState === 'visible') {
        loadRegistry();
      }
    }, interval * 1000);

    return () => clearInterval(timer);
  }, [config.pollingInterval, loadRegistry]);

  const lookupDevice = useCallback((deviceId: string) => {
    return deviceMapRef.current.get(deviceId);
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

  const value = useMemo<DeviceRegistryContextValue>(
    () => ({
      devices,
      scenes,
      isLoading,
      lookupDevice,
      lookupCharacteristic,
      lookupScene,
      refresh: loadRegistry,
    }),
    [devices, scenes, isLoading, lookupDevice, lookupCharacteristic, lookupScene, loadRegistry],
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
