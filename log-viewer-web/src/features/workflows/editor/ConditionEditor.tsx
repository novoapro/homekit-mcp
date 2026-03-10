import { useCallback, useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import { CurrentValueIndicator } from './CurrentValueIndicator';
import type { WorkflowConditionDraft } from './workflow-editor-types';
import type { TimePoint } from '@/types/workflow-definition';
import type { BlockInfo } from './workflow-editor-utils';
import './TriggerEditor.css'; // reuse shared form styles

const CONDITION_LEAF_TYPES = [
  { value: 'deviceState', label: 'Device State' },
  { value: 'timeCondition', label: 'Time Window' },
  { value: 'blockResult', label: 'Block Result' },
];

const COMPARISON_OPS = [
  { value: 'equals', label: 'Equals' },
  { value: 'notEquals', label: 'Not Equals' },
  { value: 'greaterThan', label: 'Greater Than' },
  { value: 'lessThan', label: 'Less Than' },
  { value: 'greaterThanOrEqual', label: 'Greater Than or Equal' },
  { value: 'lessThanOrEqual', label: 'Less Than or Equal' },
];

const TIME_MODES = [
  { value: 'timeRange', label: 'Between two times' },
  { value: 'beforeSunrise', label: 'Before Sunrise' },
  { value: 'afterSunrise', label: 'After Sunrise' },
  { value: 'beforeSunset', label: 'Before Sunset' },
  { value: 'afterSunset', label: 'After Sunset' },
  { value: 'daytime', label: 'Daytime (sunrise–sunset)' },
  { value: 'nighttime', label: 'Nighttime (sunset–sunrise)' },
];

interface ConditionEditorProps {
  draft: WorkflowConditionDraft;
  allowBlockResult?: boolean;
  allBlocks?: BlockInfo[];
  currentBlockDraftId?: string;
  continueOnError?: boolean;
  onChange: (updated: WorkflowConditionDraft) => void;
}

export function ConditionEditor({ draft, allBlocks, currentBlockDraftId, onChange }: ConditionEditorProps) {
  const registry = useDeviceRegistry();

  const currentOrdinal = useMemo(
    () => allBlocks?.find((b) => b._draftId === currentBlockDraftId)?.ordinal,
    [allBlocks, currentBlockDraftId],
  );

  const precedingBlocks = useMemo(() => {
    if (!allBlocks || currentOrdinal === undefined) return [];
    return allBlocks.filter((b) => b.ordinal < currentOrdinal);
  }, [allBlocks, currentOrdinal]);

  const patch = useCallback(
    (changes: Partial<WorkflowConditionDraft>) => onChange({ ...draft, ...changes }),
    [draft, onChange],
  );

  const timeStr = (tp: TimePoint | undefined): string => {
    if (!tp) return '08:00';
    if (tp.type === 'fixed') return `${String(tp.hour).padStart(2, '0')}:${String(tp.minute).padStart(2, '0')}`;
    return '';
  };

  const isMarker = (tp: TimePoint | undefined): boolean => !!tp && tp.type === 'marker';
  const markerValue = (tp: TimePoint | undefined): string => tp?.type === 'marker' ? tp.marker : 'sunset';

  return (
    <div className="trigger-editor">
      {/* Type (read-only) */}
      <div className="editor-field">
        <label>Condition Type</label>
        <div className="editor-readonly-value">
          {CONDITION_LEAF_TYPES.find((t) => t.value === draft.type)?.label || draft.type}
        </div>
      </div>

      {/* deviceState */}
      {draft.type === 'deviceState' && (
        <>
          <DevicePicker
            initialDeviceId={draft.deviceId}
            initialServiceId={draft.serviceId}
            initialCharId={draft.characteristicId}
            onChange={(val) => patch({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId })}
          />
          {draft.deviceId && draft.characteristicId && (
            <CurrentValueIndicator
              characteristic={registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)}
              isReachable={registry.lookupDevice(draft.deviceId)?.isReachable}
            />
          )}
          <div className="editor-field-row">
            <div className="editor-field">
              <label>Comparison</label>
              <select
                className="editor-select"
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                value={(draft.comparison as any)?.type || 'equals'}
                onChange={(e) => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const current = { ...(draft.comparison ?? { type: 'equals', value: true }) } as any;
                  current.type = e.target.value;
                  patch({ comparison: current });
                }}
              >
                {COMPARISON_OPS.map((op) => (
                  <option key={op.value} value={op.value}>{op.label}</option>
                ))}
              </select>
            </div>
            <CharacteristicValueInput
              characteristic={draft.deviceId && draft.characteristicId
                ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
                : undefined}
              value={(draft.comparison as any)?.value}
              forceEditable
              onChange={(val) => {
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                const current = { ...(draft.comparison ?? { type: 'equals' }) } as any;
                current.value = val;
                patch({ comparison: current });
              }}
            />
          </div>
        </>
      )}

      {/* timeCondition */}
      {draft.type === 'timeCondition' && (
        <>
          <div className="editor-field">
            <label>Mode</label>
            <select className="editor-select" value={draft.mode || 'timeRange'} onChange={(e) => patch({ mode: e.target.value })}>
              {TIME_MODES.map((m) => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
          </div>
          {draft.mode === 'timeRange' && (
            <>
              <div className="time-range-row">
                {/* Start Time */}
                <div className="time-point-cell">
                  <label>Start</label>
                  <div className="tp-mode-toggle">
                    <button type="button" className={`tp-mode-btn${!isMarker(draft.startTime) ? ' active' : ''}`} onClick={() => { if (isMarker(draft.startTime)) patch({ startTime: { type: 'fixed', hour: 20, minute: 0 } }); }}>Time</button>
                    <button type="button" className={`tp-mode-btn${isMarker(draft.startTime) ? ' active' : ''}`} onClick={() => { if (!isMarker(draft.startTime)) patch({ startTime: { type: 'marker', marker: 'sunset' } }); }}>Marker</button>
                  </div>
                  {isMarker(draft.startTime) ? (
                    <select
                      className="editor-select"
                      value={markerValue(draft.startTime)}
                      onChange={(e) => patch({ startTime: { type: 'marker', marker: e.target.value as 'midnight' | 'noon' | 'sunrise' | 'sunset' } })}
                    >
                      <option value="midnight">Midnight</option>
                      <option value="noon">Noon</option>
                      <option value="sunrise">Sunrise</option>
                      <option value="sunset">Sunset</option>
                    </select>
                  ) : (
                    <input
                      className="editor-input"
                      type="time"
                      value={timeStr(draft.startTime)}
                      onChange={(e) => {
                        const [h, m] = e.target.value.split(':');
                        patch({ startTime: { type: 'fixed', hour: +h!, minute: +m! } });
                      }}
                    />
                  )}
                </div>

                {/* End Time */}
                <div className="time-point-cell">
                  <label>End</label>
                  <div className="tp-mode-toggle">
                    <button type="button" className={`tp-mode-btn${!isMarker(draft.endTime) ? ' active' : ''}`} onClick={() => { if (isMarker(draft.endTime)) patch({ endTime: { type: 'fixed', hour: 6, minute: 0 } }); }}>Time</button>
                    <button type="button" className={`tp-mode-btn${isMarker(draft.endTime) ? ' active' : ''}`} onClick={() => { if (!isMarker(draft.endTime)) patch({ endTime: { type: 'marker', marker: 'sunrise' } }); }}>Marker</button>
                  </div>
                  {isMarker(draft.endTime) ? (
                    <select
                      className="editor-select"
                      value={markerValue(draft.endTime)}
                      onChange={(e) => patch({ endTime: { type: 'marker', marker: e.target.value as 'midnight' | 'noon' | 'sunrise' | 'sunset' } })}
                    >
                      <option value="midnight">Midnight</option>
                      <option value="noon">Noon</option>
                      <option value="sunrise">Sunrise</option>
                      <option value="sunset">Sunset</option>
                    </select>
                  ) : (
                    <input
                      className="editor-input"
                      type="time"
                      value={timeStr(draft.endTime)}
                      onChange={(e) => {
                        const [h, m] = e.target.value.split(':');
                        patch({ endTime: { type: 'fixed', hour: +h!, minute: +m! } });
                      }}
                    />
                  )}
                </div>
              </div>

              {/* Cross-midnight indicator */}
              {(() => {
                // Approximate minutes for static comparison; sunrise/sunset use rough estimates
                const toMins = (tp: TimePoint | undefined): number | null => {
                  if (!tp) return null;
                  if (tp.type === 'fixed') return tp.hour * 60 + tp.minute;
                  if (tp.type === 'marker') {
                    switch (tp.marker) {
                      case 'midnight': return 0;
                      case 'noon': return 720;
                      case 'sunrise': return 360;  // ~6:00 AM estimate
                      case 'sunset': return 1140;  // ~7:00 PM estimate
                    }
                  }
                  return null;
                };
                const hasDynamic = (tp: TimePoint | undefined) =>
                  tp?.type === 'marker' && (tp.marker === 'sunrise' || tp.marker === 'sunset');
                const sMins = toMins(draft.startTime);
                const eMins = toMins(draft.endTime);
                const dynamic = hasDynamic(draft.startTime) || hasDynamic(draft.endTime);
                if (sMins !== null && eMins !== null && sMins > eMins) {
                  return (
                    <div className="time-range-midnight">
                      <Icon name="moon" size={14} style={{ opacity: 0.6 }} />
                      {dynamic ? 'Likely spans midnight (crosses into next day)' : 'Spans midnight (crosses into next day)'}
                    </div>
                  );
                }
                return null;
              })()}
            </>
          )}
        </>
      )}

      {/* blockResult */}
      {draft.type === 'blockResult' && (
        <>
          <div className="editor-field">
            <label>Scope</label>
            <select
              className="editor-select"
              value={draft.blockResultScope?.scope || 'any'}
              onChange={(e) =>
                patch({
                  blockResultScope:
                    e.target.value === 'specific'
                      ? { scope: 'specific', blockId: draft.blockResultScope?.blockId || '' }
                      : { scope: 'any' },
                })
              }
            >
              <option value="any">Any block</option>
              <option value="specific">Specific block</option>
            </select>
          </div>
          {draft.blockResultScope?.scope === 'specific' && (
            <div className="editor-field">
              <label>Block</label>
              <select
                className="editor-select"
                value={draft.blockResultScope?.blockId || ''}
                onChange={(e) => patch({ blockResultScope: { scope: 'specific', blockId: e.target.value } })}
              >
                <option value="">-- Select block --</option>
                {precedingBlocks.map((b) => (
                  <option key={b._draftId} value={b._draftId}>
                    #{b.ordinal} {b.name}
                  </option>
                ))}
              </select>
            </div>
          )}
          <div className="editor-field">
            <label>Expected Status</label>
            <select className="editor-select" value={draft.expectedStatus || 'success'} onChange={(e) => patch({ expectedStatus: e.target.value })}>
              <option value="success">Success</option>
              <option value="failure">Failure</option>
              <option value="skipped">Skipped</option>
            </select>
          </div>
        </>
      )}
    </div>
  );
}
