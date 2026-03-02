import type { RESTCharacteristic } from '@/types/homekit-device';
import './CurrentValueIndicator.css';

interface CurrentValueIndicatorProps {
  characteristic: RESTCharacteristic | undefined;
  isReachable?: boolean;
}

export function CurrentValueIndicator({ characteristic, isReachable = true }: CurrentValueIndicatorProps) {
  if (!characteristic) return null;

  if (!isReachable) {
    return (
      <div className="current-value-indicator offline">
        <span className="current-value-dot" />
        <span className="current-value-label">Current:</span>
        <span className="current-value-text">Unavailable</span>
      </div>
    );
  }

  return (
    <div className="current-value-indicator">
      <span className="current-value-dot" />
      <span className="current-value-label">Current:</span>
      <span className="current-value-text">{formatValue(characteristic)}</span>
    </div>
  );
}

function formatValue(char: RESTCharacteristic): string {
  const val = char.value;
  if (val === undefined || val === null) return 'Unknown';

  // Boolean
  if (char.format === 'bool') {
    return val === true || val === 'true' || val === 1 ? 'On' : 'Off';
  }

  // Enum values with labels
  if (char.validValues && char.validValues.length > 0) {
    const match = char.validValues.find(
      vv => vv.value === val || String(vv.value) === String(val),
    );
    if (match?.description) return match.description;
  }

  // Numeric with units
  if (typeof val === 'number') {
    const formatted = char.format === 'float' ? val.toFixed(1) : String(val);
    return formatted + unitSymbol(char.units);
  }

  return String(val);
}

function unitSymbol(units?: string): string {
  switch (units) {
    case 'celsius': return '\u00B0C';
    case 'fahrenheit': return '\u00B0F';
    case '%': return '%';
    case 'arcdegrees': return '\u00B0';
    case 'seconds': return 's';
    case 'lux': return ' lux';
    case 'ppm': return ' ppm';
    case '\u00B5g/m\u00B3': return ' \u00B5g/m\u00B3';
    default: return units ? ` ${units}` : '';
  }
}
