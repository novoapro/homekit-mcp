import { useState, useEffect } from 'react';
import type { RESTCharacteristic } from '@/types/homekit-device';
import { parseSmartValue } from './workflow-editor-utils';
import './CharacteristicValueInput.css';

interface CharacteristicValueInputProps {
  /** Full characteristic metadata. If undefined, falls back to plain text input. */
  characteristic?: RESTCharacteristic;
  /** Current value */
  value: unknown;
  /** Called when the value changes (already typed: boolean, number, string). */
  onChange: (value: unknown) => void;
  /** Label shown above the input (defaults to "Value") */
  label?: string;
  /** Placeholder for text/number inputs */
  placeholder?: string;
  /** Whether to allow an "Any" option (for transition "From" fields) */
  allowAny?: boolean;
}

const NUMERIC_FORMATS = new Set(['uint8', 'uint16', 'uint32', 'uint64', 'int', 'float']);

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

export function CharacteristicValueInput({
  characteristic,
  value,
  onChange,
  label = 'Value',
  placeholder,
  allowAny = false,
}: CharacteristicValueInputProps) {
  // Track local text for uncontrolled text inputs
  const [localText, setLocalText] = useState(value != null ? String(value) : '');

  // Sync localText when value changes externally
  useEffect(() => {
    setLocalText(value != null ? String(value) : '');
  }, [value]);

  const isReadOnly = characteristic ? !characteristic.permissions.includes('write') : false;
  const unit = characteristic ? unitSymbol(characteristic.units) : '';

  // --- No metadata fallback ---
  if (!characteristic) {
    return (
      <div className="editor-field">
        <label>{label}</label>
        <input
          className="editor-input"
          value={localText}
          onChange={(e) => setLocalText(e.target.value)}
          onBlur={() => onChange(parseSmartValue(localText))}
          placeholder={placeholder ?? 'e.g. true, 50, On'}
        />
      </div>
    );
  }

  // --- Boolean toggle ---
  if (characteristic.format === 'bool') {
    const boolVal = value === true || value === 'true';
    const isAny = allowAny && value === undefined;

    return (
      <div className="editor-field">
        <label>{label}</label>
        <div className="char-toggle-wrap">
          {allowAny && (
            <button
              type="button"
              className={`char-toggle-option${isAny ? ' active' : ''}`}
              disabled={isReadOnly}
              onClick={() => onChange(undefined)}
            >
              Any
            </button>
          )}
          <button
            type="button"
            className={`char-toggle-option${!isAny && !boolVal ? ' active' : ''}`}
            disabled={isReadOnly}
            onClick={() => onChange(false)}
          >
            Off
          </button>
          <button
            type="button"
            className={`char-toggle-option${!isAny && boolVal ? ' active' : ''}`}
            disabled={isReadOnly}
            onClick={() => onChange(true)}
          >
            On
          </button>
        </div>
      </div>
    );
  }

  // --- Valid values dropdown ---
  if (characteristic.validValues && characteristic.validValues.length > 0) {
    const selectValue = value != null ? String(value) : (allowAny ? '__any__' : '');

    return (
      <div className="editor-field">
        <label>{label}{unit && <span className="char-unit">{unit}</span>}</label>
        <select
          className="editor-select"
          value={selectValue}
          disabled={isReadOnly}
          onChange={(e) => {
            if (e.target.value === '__any__') {
              onChange(undefined);
            } else {
              const num = Number(e.target.value);
              onChange(isNaN(num) ? e.target.value : num);
            }
          }}
        >
          {allowAny && <option value="__any__">Any</option>}
          {characteristic.validValues.map((vv) => (
            <option key={String(vv.value)} value={String(vv.value)}>
              {vv.description ?? String(vv.value)}
            </option>
          ))}
        </select>
      </div>
    );
  }

  // --- Numeric with full range → slider ---
  if (
    NUMERIC_FORMATS.has(characteristic.format) &&
    characteristic.minValue != null &&
    characteristic.maxValue != null
  ) {
    const numVal = typeof value === 'number' ? value : Number(value ?? characteristic.minValue);
    const step = characteristic.stepValue ?? 1;

    return (
      <div className="editor-field">
        <label>{label}</label>
        {allowAny && value === undefined ? (
          <div className="char-any-wrap">
            <span className="char-any-label">Any</span>
            <button
              type="button"
              className="char-any-clear"
              onClick={() => onChange(characteristic.minValue)}
            >
              Set value
            </button>
          </div>
        ) : (
          <div className="char-slider-wrap">
            {allowAny && (
              <button
                type="button"
                className="char-any-btn"
                title="Set to Any"
                onClick={() => onChange(undefined)}
              >
                &times;
              </button>
            )}
            <input
              type="range"
              className="char-slider"
              min={characteristic.minValue}
              max={characteristic.maxValue}
              step={step}
              value={numVal}
              disabled={isReadOnly}
              onChange={(e) => onChange(Number(e.target.value))}
            />
            <span className="char-value-readout">
              {characteristic.format === 'float' ? numVal.toFixed(1) : numVal}
              {unit && <span className="char-unit">{unit}</span>}
            </span>
          </div>
        )}
      </div>
    );
  }

  // --- Numeric without full range → number input ---
  if (NUMERIC_FORMATS.has(characteristic.format)) {
    const numVal = value != null ? String(value) : '';

    return (
      <div className="editor-field">
        <label>
          {label}
          {unit && <span className="char-unit">{unit}</span>}
        </label>
        {allowAny && value === undefined ? (
          <div className="char-any-wrap">
            <span className="char-any-label">Any</span>
            <button
              type="button"
              className="char-any-clear"
              onClick={() => onChange(0)}
            >
              Set value
            </button>
          </div>
        ) : (
          <div className="char-number-wrap">
            {allowAny && (
              <button
                type="button"
                className="char-any-btn"
                title="Set to Any"
                onClick={() => onChange(undefined)}
              >
                &times;
              </button>
            )}
            <input
              type="number"
              className="editor-input"
              value={numVal}
              step={characteristic.stepValue}
              min={characteristic.minValue}
              max={characteristic.maxValue}
              disabled={isReadOnly}
              onChange={(e) => {
                const v = e.target.value;
                onChange(v === '' ? undefined : Number(v));
              }}
            />
          </div>
        )}
      </div>
    );
  }

  // --- String / fallback → text input ---
  return (
    <div className="editor-field">
      <label>{label}</label>
      {allowAny && value === undefined ? (
        <div className="char-any-wrap">
          <span className="char-any-label">Any</span>
          <button
            type="button"
            className="char-any-clear"
            onClick={() => onChange('')}
          >
            Set value
          </button>
        </div>
      ) : (
        <div className="char-number-wrap">
          {allowAny && (
            <button
              type="button"
              className="char-any-btn"
              title="Set to Any"
              onClick={() => onChange(undefined)}
            >
              &times;
            </button>
          )}
          <input
            className="editor-input"
            value={localText}
            disabled={isReadOnly}
            onChange={(e) => setLocalText(e.target.value)}
            onBlur={() => onChange(parseSmartValue(localText))}
            placeholder={placeholder ?? 'Enter value'}
          />
        </div>
      )}
    </div>
  );
}
