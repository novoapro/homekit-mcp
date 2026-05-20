import { useEffect, useRef, useState, useCallback } from 'react';
import { characteristicDisplayName, formatCharacteristicValue, getCharacteristicDisplayUnit } from '@/utils/characteristic-types';
import { PermissionIcons } from './PermissionIcons';
import { Icon } from '@/components/Icon';
import { useConfig } from '@/contexts/ConfigContext';
import type { RESTCharacteristic } from '@/types/homekit-device';

interface CharacteristicsTableProps {
  characteristics: RESTCharacteristic[];
  serviceId: string;
  deviceId: string;
}

function coerceToInt(val: unknown): number {
  if (typeof val === 'boolean') return val ? 1 : 0;
  if (typeof val === 'number') return Math.round(val);
  return 0;
}

function sampleValue(char: RESTCharacteristic): string {
  const vv = char.validValues;
  if (vv && vv.length > 0) {
    if (char.value != null) {
      const numeric = coerceToInt(char.value);
      if (vv.some(v => v.value === numeric)) return String(numeric);
    }
    return String(vv[0]!.value);
  }
  if (char.value != null) {
    if (typeof char.value === 'boolean') return String(char.value);
    if (typeof char.value === 'number') return String(char.value);
    return String(char.value);
  }
  switch (char.format) {
    case 'bool': return 'true';
    case 'int': case 'uint8': case 'uint16': case 'uint32': case 'uint64':
      return char.minValue != null ? String(char.minValue) : '0';
    case 'float':
      return char.minValue != null ? String(char.minValue) : '0.0';
    default: return 'value';
  }
}

function sampleJsonValue(char: RESTCharacteristic): string {
  if (char.validValues && char.validValues.length > 0) {
    return sampleValue(char);
  }
  const val = char.value;
  if (val != null) {
    if (typeof val === 'boolean' || typeof val === 'number') return JSON.stringify(val);
    return JSON.stringify(String(val));
  }
  switch (char.format) {
    case 'bool': return 'true';
    case 'int': case 'uint8': case 'uint16': case 'uint32': case 'uint64':
      return char.minValue != null ? String(Math.round(char.minValue)) : '0';
    case 'float':
      return char.minValue != null ? String(char.minValue) : '0.0';
    default: return '"value"';
  }
}

function possibleValues(char: RESTCharacteristic): string {
  if (char.validValues && char.validValues.length > 0) {
    return char.validValues.map(v => {
      const label = v.label ?? String(v.value);
      return label !== String(v.value) ? `${v.value} (${label})` : String(v.value);
    }).join(', ');
  }
  switch (char.format) {
    case 'bool':
      return 'true (On), false (Off)';
    case 'int': case 'uint8': case 'uint16': case 'uint32': case 'uint64': {
      const min = char.minValue ?? 0;
      const max = char.maxValue ?? 255;
      const step = char.stepValue != null ? ` (step: ${char.stepValue})` : '';
      return `${min} – ${max}${step}`;
    }
    case 'float': {
      const min = char.minValue ?? 0.0;
      const max = char.maxValue ?? 100.0;
      const step = char.stepValue != null ? ` (step: ${char.stepValue})` : '';
      return `${min} – ${max}${step}`;
    }
    case 'string':
      return 'string';
    default:
      return 'any';
  }
}

export function CharacteristicsTable({ characteristics, serviceId, deviceId }: CharacteristicsTableProps) {
  const { baseUrl } = useConfig();
  const prevValuesRef = useRef<Map<string, unknown>>(new Map());
  const [flashedKeys, setFlashedKeys] = useState<Set<string>>(new Set());
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  useEffect(() => {
    const newFlashed = new Set<string>();
    for (const char of characteristics) {
      const key = `${serviceId}-${char.id}`;
      const prev = prevValuesRef.current.get(key);
      if (prev !== undefined && prev !== char.value) {
        newFlashed.add(key);
      }
      prevValuesRef.current.set(key, char.value);
    }
    if (newFlashed.size > 0) {
      setFlashedKeys(newFlashed);
      const timer = setTimeout(() => setFlashedKeys(new Set()), 1500);
      return () => clearTimeout(timer);
    }
  }, [characteristics, serviceId]);

  const copyText = useCallback((text: string, key: string) => {
    navigator.clipboard.writeText(text).then(() => {
      setCopiedKey(key);
      setTimeout(() => setCopiedKey(null), 1500);
    });
  }, []);

  return (
    <div className="char-table">
      <div className="char-table-header">
        <span className="char-col-name">Characteristic</span>
        <span className="char-col-value">Value</span>
        <span className="char-col-perms">Permissions</span>
      </div>
      {characteristics.map(char => {
        const key = `${serviceId}-${char.id}`;
        const isFlashed = flashedKeys.has(key);
        const charType = char.type || char.name || '';
        const pv = possibleValues(char);
        const controlUrl = `${baseUrl}/devices/${deviceId}/control`;
        const urlText = [
          `// Device ID: ${deviceId}`,
          `// Possible values: ${pv}`,
          `// Method: PUT (query params as fallback for simple integrations)`,
          `${controlUrl}?characteristic_id=${char.id}&value=${sampleValue(char)}`,
        ].join('\n');
        const jsonText = [
          `// Device ID: ${deviceId}`,
          `// Possible values: ${pv}`,
          `// PUT ${controlUrl}`,
          JSON.stringify({
            characteristic_id: char.id,
            value: JSON.parse(sampleJsonValue(char)),
          }, null, 2),
        ].join('\n');
        return (
          <div key={char.id} className={`char-row ${isFlashed ? 'value-updated' : ''}`}>
            <span className="char-col-name" title={charType}>
              <span>{charType ? characteristicDisplayName(charType) : char.name || 'Unknown'}</span>
              <span className="char-id-label">{char.id}</span>
            </span>
            <span className="char-col-value">
              <span className="char-value-text">
                {charType ? formatCharacteristicValue(char.value, charType) : String(char.value ?? '--')}
              </span>
              {charType && getCharacteristicDisplayUnit(charType, char.units) && (
                <span className="char-units">{getCharacteristicDisplayUnit(charType, char.units)}</span>
              )}
            </span>
            <span className="char-col-perms">
              <PermissionIcons permissions={char.permissions} />
            </span>
            <span className="char-col-actions">
              <button
                className="char-copy-btn"
                title="Copy characteristic ID"
                onClick={() => copyText(char.id, `id-${char.id}`)}
              >
                <Icon name="copy" size={12} />
                {copiedKey === `id-${char.id}` && <span className="char-copied-tip">Copied!</span>}
              </button>
              {char.permissions.includes('write') && (
                <>
                  <button
                    className="char-copy-btn"
                    title="Copy GET control URL"
                    onClick={() => copyText(urlText, `url-${char.id}`)}
                  >
                    <Icon name="link" size={12} />
                    {copiedKey === `url-${char.id}` && <span className="char-copied-tip">Copied!</span>}
                  </button>
                  <button
                    className="char-copy-btn"
                    title="Copy PUT JSON payload"
                    onClick={() => copyText(jsonText, `json-${char.id}`)}
                  >
                    <Icon name="doc-text" size={12} />
                    {copiedKey === `json-${char.id}` && <span className="char-copied-tip">Copied!</span>}
                  </button>
                </>
              )}
            </span>
          </div>
        );
      })}
    </div>
  );
}
