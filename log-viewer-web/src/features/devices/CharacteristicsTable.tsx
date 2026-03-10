import { useEffect, useRef, useState } from 'react';
import { characteristicDisplayName, formatCharacteristicValue, getCharacteristicDisplayUnit } from '@/utils/characteristic-types';
import { PermissionIcons } from './PermissionIcons';
import type { RESTCharacteristic } from '@/types/homekit-device';

interface CharacteristicsTableProps {
  characteristics: RESTCharacteristic[];
  serviceId: string;
}

export function CharacteristicsTable({ characteristics, serviceId }: CharacteristicsTableProps) {
  const prevValuesRef = useRef<Map<string, unknown>>(new Map());
  const [flashedKeys, setFlashedKeys] = useState<Set<string>>(new Set());

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
        return (
          <div key={char.id} className={`char-row ${isFlashed ? 'value-updated' : ''}`}>
            <span className="char-col-name" title={charType}>
              {charType ? characteristicDisplayName(charType) : char.name || 'Unknown'}
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
          </div>
        );
      })}
    </div>
  );
}
