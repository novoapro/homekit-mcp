import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type { RESTDevice, RESTService } from '@/types/homekit-device';
import './DevicePicker.css';

export interface DevicePickerValue {
  deviceId: string;
  serviceId: string;
  characteristicId: string;
}

interface PickerOption {
  id: string;
  label: string;
  secondary?: string;
}

interface DevicePickerProps {
  initialDeviceId?: string;
  initialServiceId?: string;
  initialCharId?: string;
  /** When true, only show characteristics with write permission (and hide services/devices with none). */
  writableOnly?: boolean;
  onChange: (value: DevicePickerValue) => void;
}

function SearchableSelect({
  label,
  options,
  selectedId,
  onSelect,
  onClear,
  placeholder,
}: {
  label: string;
  options: PickerOption[];
  selectedId: string;
  onSelect: (id: string) => void;
  onClear: () => void;
  placeholder: string;
}) {
  const [query, setQuery] = useState('');
  const [isOpen, setIsOpen] = useState(false);
  const [focusedIndex, setFocusedIndex] = useState(-1);
  const wrapRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const selectedLabel = useMemo(() => options.find((o) => o.id === selectedId)?.label ?? '', [options, selectedId]);

  const filtered = useMemo(() => {
    if (!query) return options;
    const q = query.toLowerCase();
    return options.filter(
      (o) => o.label.toLowerCase().includes(q) || (o.secondary ?? '').toLowerCase().includes(q),
    );
  }, [options, query]);

  // Close on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setIsOpen(false);
        setQuery('');
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setFocusedIndex((prev) => Math.min(prev + 1, filtered.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setFocusedIndex((prev) => Math.max(prev - 1, 0));
      } else if (e.key === 'Enter' && focusedIndex >= 0 && filtered[focusedIndex]) {
        e.preventDefault();
        onSelect(filtered[focusedIndex]!.id);
        setIsOpen(false);
        setQuery('');
        inputRef.current?.blur();
      } else if (e.key === 'Escape') {
        setIsOpen(false);
        setQuery('');
        inputRef.current?.blur();
      }
    },
    [filtered, focusedIndex, onSelect],
  );

  return (
    <div className="picker-field" ref={wrapRef}>
      <label>{label}</label>
      <div className="picker-input-wrap">
        <input
          ref={inputRef}
          className="picker-input"
          value={isOpen ? query : selectedLabel}
          placeholder={placeholder}
          onFocus={() => {
            setIsOpen(true);
            setQuery('');
            setFocusedIndex(-1);
          }}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={handleKeyDown}
        />
        {selectedId && (
          <button
            className="picker-clear"
            onClick={(e) => {
              e.stopPropagation();
              onClear();
              setQuery('');
            }}
            title="Clear"
            type="button"
          >
            <Icon name="xmark-circle-fill" size={14} />
          </button>
        )}
      </div>
      {isOpen && (
        <div className="picker-dropdown">
          {filtered.length === 0 ? (
            <div className="picker-empty">No results</div>
          ) : (
            filtered.map((opt, i) => (
              <div
                key={opt.id}
                className={`picker-option${i === focusedIndex ? ' focused' : ''}${opt.id === selectedId ? ' selected' : ''}`}
                onMouseDown={(e) => {
                  e.preventDefault();
                  onSelect(opt.id);
                  setIsOpen(false);
                  setQuery('');
                }}
                onMouseEnter={() => setFocusedIndex(i)}
              >
                <span>{opt.label}</span>
                {opt.secondary && <span className="picker-opt-secondary">{opt.secondary}</span>}
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
}

export function DevicePicker({ initialDeviceId, initialServiceId, initialCharId, writableOnly = false, onChange }: DevicePickerProps) {
  const registry = useDeviceRegistry();

  const [selectedDeviceId, setSelectedDeviceId] = useState(initialDeviceId ?? '');
  const [selectedServiceId, setSelectedServiceId] = useState(initialServiceId ?? '');
  const [selectedCharId, setSelectedCharId] = useState(initialCharId ?? '');

  // Filter helpers for writableOnly mode
  const hasWritableChar = useCallback(
    (svc: RESTService) => svc.characteristics.some((c) => c.permissions.includes('write')),
    [],
  );

  const selectedDevice = useMemo<RESTDevice | undefined>(
    () => registry.devices.find((d) => d.id === selectedDeviceId),
    [registry.devices, selectedDeviceId],
  );

  const selectedService = useMemo<RESTService | undefined>(
    () => selectedDevice?.services.find((s) => s.id === selectedServiceId),
    [selectedDevice, selectedServiceId],
  );

  const deviceOptions = useMemo<PickerOption[]>(
    () => {
      let devices = registry.devices;
      if (writableOnly) {
        devices = devices.filter((d) => d.services.some(hasWritableChar));
      }
      return devices.map((d) => ({ id: d.id, label: d.name, secondary: d.room || undefined }));
    },
    [registry.devices, writableOnly, hasWritableChar],
  );

  const serviceOptions = useMemo<PickerOption[]>(
    () => {
      let services = selectedDevice?.services ?? [];
      if (writableOnly) {
        services = services.filter(hasWritableChar);
      }
      return services.map((s) => ({
        id: s.id,
        label: s.name || s.type,
        secondary: s.name ? s.type : undefined,
      }));
    },
    [selectedDevice, writableOnly, hasWritableChar],
  );

  const charOptions = useMemo<PickerOption[]>(
    () => {
      let chars = selectedService?.characteristics ?? [];
      if (writableOnly) {
        chars = chars.filter((c) => c.permissions.includes('write'));
      }
      return chars.map((c) => ({
        id: c.id,
        label: c.name || c.id,
        secondary: c.type !== c.name ? c.type : undefined,
      }));
    },
    [selectedService, writableOnly],
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
