import { memo, useCallback, useState } from 'react';
import { Icon } from '@/components/Icon';
import { getServiceIcon } from '@/utils/service-icons';
import { CharacteristicsTable } from './CharacteristicsTable';
import type { RESTDevice } from '@/types/homekit-device';

interface DeviceCardProps {
  device: RESTDevice;
  isExpanded: boolean;
  onToggleDevice: (deviceId: string) => void;
}

export const DeviceCard = memo(function DeviceCard({ device, isExpanded, onToggleDevice }: DeviceCardProps) {
  const primaryService = device.services[0];
  const iconName = getServiceIcon(primaryService?.type) ?? getServiceIcon(primaryService?.name) ?? 'house';
  const serviceCount = device.services.length;
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const handleToggle = useCallback(() => {
    onToggleDevice(device.id);
  }, [onToggleDevice, device.id]);

  const copyText = useCallback((text: string, key: string) => {
    navigator.clipboard.writeText(text).then(() => {
      setCopiedKey(key);
      setTimeout(() => setCopiedKey(null), 1500);
    });
  }, []);

  return (
    <div className={`device-card ${isExpanded ? 'expanded' : ''}`}>
      <button className="device-card-header" onClick={handleToggle} type="button">
        <span className="device-card-icon">
          <Icon name={iconName} size={22} style={{ color: 'var(--tint-main)' }} />
        </span>
        <div className="device-card-info">
          <span className="device-card-name">{device.name}</span>
          <span className="device-card-meta">
            {device.room && (
              <span className="device-room-badge">{device.room}</span>
            )}
            <span className="device-service-count">
              {serviceCount} {serviceCount === 1 ? 'service' : 'services'}
            </span>
          </span>
        </div>
        <div className="device-card-right">
          <span
            className={`reachability-dot ${device.isReachable ? 'reachable' : 'unreachable'}`}
            title={device.isReachable ? 'Reachable' : 'Unreachable'}
          />
          <Icon
            name={isExpanded ? 'chevron-down' : 'chevron-right'}
            size={18}
            className="device-card-chevron"
          />
        </div>
      </button>

      {isExpanded && (
        <div className="device-card-body">
          <div className="device-id-row">
            <span className="device-id-label">Device ID</span>
            <span className="device-id-value">{device.id}</span>
            <button
              className="char-copy-btn"
              title="Copy device ID"
              onClick={() => copyText(device.id, `dev-${device.id}`)}
            >
              <Icon name="copy" size={12} />
              {copiedKey === `dev-${device.id}` && <span className="char-copied-tip">Copied!</span>}
            </button>
          </div>
          {device.services.map(svc => {
            const svcIcon = getServiceIcon(svc.type) ?? getServiceIcon(svc.name) ?? 'slider-horizontal';
            return (
              <div key={svc.id} className="device-service-section">
                <div className="device-service-header">
                  <Icon name={svcIcon} size={16} style={{ color: 'var(--text-secondary)' }} />
                  <span className="device-service-name">{svc.name}</span>
                  <span className="device-service-type-badge">{svc.type}</span>
                  <button
                    className="char-copy-btn"
                    title="Copy service ID"
                    onClick={() => copyText(svc.id, `svc-${svc.id}`)}
                  >
                    <Icon name="copy" size={11} />
                    {copiedKey === `svc-${svc.id}` && <span className="char-copied-tip">Copied!</span>}
                  </button>
                </div>
                <div className="device-service-id">
                  {svc.id}
                </div>
                <CharacteristicsTable
                  characteristics={svc.characteristics}
                  serviceId={svc.id}
                  deviceId={device.id}
                />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
});
