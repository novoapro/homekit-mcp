import { useMemo } from 'react';
import { Icon } from './Icon';
import { getServiceIcon } from '@/utils/service-icons';
import type { RESTDevice, RESTScene } from '@/types/homekit-device';

interface DeviceScenePickerProps {
  devices: RESTDevice[];
  scenes: RESTScene[];
  selectedDeviceIds: Set<string>;
  selectedSceneIds: Set<string>;
  onToggleDevice: (id: string) => void;
  onToggleScene: (id: string) => void;
}

function getDeviceIcon(device: RESTDevice): string {
  const primary = device.services[0];
  return getServiceIcon(primary?.type) ?? getServiceIcon(primary?.name) ?? 'house';
}

export function DeviceScenePicker({
  devices, scenes, selectedDeviceIds, selectedSceneIds,
  onToggleDevice, onToggleScene,
}: DeviceScenePickerProps) {
  const devicesByRoom = useMemo(() => {
    const map = new Map<string, RESTDevice[]>();
    for (const device of devices) {
      const room = device.room ?? 'No Room';
      const list = map.get(room) ?? [];
      list.push(device);
      map.set(room, list);
    }
    return Array.from(map.entries()).sort(([a], [b]) => a.localeCompare(b));
  }, [devices]);

  return (
    <div className="aig-picker">
      {devicesByRoom.length > 0 && (
        <div className="aig-picker-section">
          <div className="aig-picker-section-title">Devices</div>
          {devicesByRoom.map(([room, roomDevices]) => (
            <div key={room} className="aig-picker-room">
              <div className="aig-picker-room-name">{room}</div>
              {roomDevices.map(device => {
                const selected = selectedDeviceIds.has(device.id);
                return (
                  <div
                    key={device.id}
                    className={`aig-picker-item${selected ? ' selected' : ''}`}
                    role="checkbox"
                    aria-checked={selected}
                    tabIndex={0}
                    onClick={() => onToggleDevice(device.id)}
                    onKeyDown={e => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); onToggleDevice(device.id); } }}
                  >
                    <span className="aig-picker-item-icon">
                      <Icon name={getDeviceIcon(device)} size={14} />
                    </span>
                    <span className="aig-picker-item-name">{device.name}</span>
                    <span className={`aig-picker-check${selected ? ' checked' : ''}`}>
                      <Icon name={selected ? 'checkmark-circle-fill' : 'circle'} size={18} />
                    </span>
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      )}

      {scenes.length > 0 && (
        <div className="aig-picker-section">
          <div className="aig-picker-section-title">Scenes</div>
          {scenes.map(scene => {
            const selected = selectedSceneIds.has(scene.id);
            return (
              <div
                key={scene.id}
                className={`aig-picker-item${selected ? ' selected' : ''}`}
                role="checkbox"
                aria-checked={selected}
                tabIndex={0}
                onClick={() => onToggleScene(scene.id)}
                onKeyDown={e => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); onToggleScene(scene.id); } }}
              >
                <span className="aig-picker-item-icon scene">
                  <Icon name="play-circle-fill" size={14} />
                </span>
                <span className="aig-picker-item-name">{scene.name}</span>
                <span className={`aig-picker-check${selected ? ' checked' : ''}`}>
                  <Icon name={selected ? 'checkmark-circle-fill' : 'circle'} size={18} />
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
