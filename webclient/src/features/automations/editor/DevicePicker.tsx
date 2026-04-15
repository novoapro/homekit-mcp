import { useState, useMemo, useCallback } from 'react';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { SearchableSelect } from './SearchableSelect';
import type { SelectOption } from './SearchableSelect';
import type { RESTDevice, RESTService } from '@/types/homekit-device';
import './DevicePicker.css';

export interface DevicePickerValue {
  deviceId: string;
  serviceId: string;
  characteristicId: string;
}

interface DevicePickerProps {
  initialDeviceId?: string;
  initialServiceId?: string;
  initialCharId?: string;
  /** When true, only show characteristics with write permission (and hide services/devices with none). */
  writableOnly?: boolean;
  /** When true, only show characteristics with notify permission (for triggers that need state change events). */
  notifiableOnly?: boolean;
  /** When set, only show characteristics whose format is in this set (e.g. new Set(['bool']) or new Set(['uint8','int','float'])). */
  formatFilter?: Set<string>;
  onChange: (value: DevicePickerValue) => void;
}

export function DevicePicker({ initialDeviceId, initialServiceId, initialCharId, writableOnly = false, notifiableOnly = false, formatFilter, onChange }: DevicePickerProps) {
  const registry = useDeviceRegistry();

  const [selectedDeviceId, setSelectedDeviceId] = useState(initialDeviceId ?? '');
  const [selectedServiceId, setSelectedServiceId] = useState(initialServiceId ?? '');
  const [selectedCharId, setSelectedCharId] = useState(initialCharId ?? '');

  // Filter helpers for writableOnly / notifiableOnly / formatFilter modes
  const hasWritableChar = useCallback(
    (svc: RESTService) => svc.characteristics.some((c) => c.permissions.includes('write')),
    [],
  );

  const hasNotifiableChar = useCallback(
    (svc: RESTService) => svc.characteristics.some((c) => c.permissions.includes('notify')),
    [],
  );

  const hasMatchingFormat = useCallback(
    (svc: RESTService) => !formatFilter || svc.characteristics.some((c) => formatFilter.has(c.format)),
    [formatFilter],
  );

  const selectedDevice = useMemo<RESTDevice | undefined>(
    () => registry.devices.find((d) => d.id === selectedDeviceId),
    [registry.devices, selectedDeviceId],
  );

  const selectedService = useMemo<RESTService | undefined>(
    () => selectedDevice?.services.find((s) => s.id === selectedServiceId),
    [selectedDevice, selectedServiceId],
  );

  const deviceOptions = useMemo<SelectOption[]>(
    () => {
      let devices = registry.devices;
      if (writableOnly) {
        devices = devices.filter((d) => d.services.some(hasWritableChar));
      }
      if (notifiableOnly) {
        devices = devices.filter((d) => d.services.some(hasNotifiableChar));
      }
      if (formatFilter) {
        devices = devices.filter((d) => d.services.some(hasMatchingFormat));
      }
      return devices.map((d) => ({ id: d.id, label: d.name, secondary: d.room || undefined }));
    },
    [registry.devices, writableOnly, notifiableOnly, formatFilter, hasWritableChar, hasNotifiableChar, hasMatchingFormat],
  );

  const serviceOptions = useMemo<SelectOption[]>(
    () => {
      let services = selectedDevice?.services ?? [];
      if (writableOnly) {
        services = services.filter(hasWritableChar);
      }
      if (notifiableOnly) {
        services = services.filter(hasNotifiableChar);
      }
      if (formatFilter) {
        services = services.filter(hasMatchingFormat);
      }
      return services.map((s) => ({
        id: s.id,
        label: s.name || s.type,
        secondary: s.name ? s.type : undefined,
      }));
    },
    [selectedDevice, writableOnly, notifiableOnly, formatFilter, hasWritableChar, hasNotifiableChar, hasMatchingFormat],
  );

  const charOptions = useMemo<SelectOption[]>(
    () => {
      let chars = selectedService?.characteristics ?? [];
      if (writableOnly) {
        chars = chars.filter((c) => c.permissions.includes('write'));
      }
      if (notifiableOnly) {
        chars = chars.filter((c) => c.permissions.includes('notify'));
      }
      if (formatFilter) {
        chars = chars.filter((c) => formatFilter.has(c.format));
      }
      return chars.map((c) => ({
        id: c.id,
        label: c.name || c.id,
        secondary: c.type !== c.name ? c.type : undefined,
      }));
    },
    [selectedService, writableOnly, notifiableOnly, formatFilter],
  );

  const emit = useCallback(
    (devId: string, svcId: string, charId: string) => {
      onChange({ deviceId: devId, serviceId: svcId, characteristicId: charId });
    },
    [onChange],
  );

  return (
    <div className="device-picker">
      <SearchableSelect
        label="Device"
        options={deviceOptions}
        selectedId={selectedDeviceId}
        placeholder="Search devices..."
        onSelect={(id) => {
          setSelectedDeviceId(id);
          setSelectedServiceId('');
          setSelectedCharId('');
          emit(id, '', '');
        }}
        onClear={() => {
          setSelectedDeviceId('');
          setSelectedServiceId('');
          setSelectedCharId('');
          emit('', '', '');
        }}
      />

      {selectedDevice && (
        <SearchableSelect
          label="Service"
          options={serviceOptions}
          selectedId={selectedServiceId}
          placeholder="Search services..."
          onSelect={(id) => {
            setSelectedServiceId(id);
            setSelectedCharId('');
            emit(selectedDeviceId, id, '');
          }}
          onClear={() => {
            setSelectedServiceId('');
            setSelectedCharId('');
            emit(selectedDeviceId, '', '');
          }}
        />
      )}

      {selectedService && (
        <SearchableSelect
          label="Characteristic"
          options={charOptions}
          selectedId={selectedCharId}
          placeholder="Search characteristics..."
          onSelect={(id) => {
            setSelectedCharId(id);
            emit(selectedDeviceId, selectedServiceId, id);
          }}
          onClear={() => {
            setSelectedCharId('');
            emit(selectedDeviceId, selectedServiceId, '');
          }}
        />
      )}
    </div>
  );
}
