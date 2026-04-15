import { useCallback, useMemo, useState, useEffect } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { useApi } from '@/hooks/useApi';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import { CurrentValueIndicator } from './CurrentValueIndicator';
import type { AutomationConditionDraft } from './automation-editor-types';
import type { TimePoint } from '@/types/automation-definition';
import type { BlockInfo } from './automation-editor-utils';
import './TriggerEditor.css'; // reuse shared form styles

const CONDITION_LEAF_TYPES = [
  { value: 'deviceState', label: 'Device State' },
  { value: 'timeCondition', label: 'Time Window' },
  { value: 'engineState', label: 'Global Value' },
  { value: 'blockResult', label: 'Block Result' },
];

const COMPARISON_OPS = [
  { value: 'equals', label: 'Equals', types: [] as string[] },
  { value: 'notEquals', label: 'Not Equals', types: [] as string[] },
  { value: 'greaterThan', label: 'Greater Than', types: ['number', 'datetime'] },
  { value: 'lessThan', label: 'Less Than', types: ['number', 'datetime'] },
  { value: 'greaterThanOrEqual', label: 'Greater or Equal', types: ['number', 'datetime'] },
  { value: 'lessThanOrEqual', label: 'Less or Equal', types: ['number', 'datetime'] },
  { value: 'isEmpty', label: 'Is Empty', types: ['string'] },
  { value: 'isNotEmpty', label: 'Is Not Empty', types: ['string'] },
  { value: 'contains', label: 'Contains', types: ['string'] },
];

const NO_VALUE_OPS = new Set(['isEmpty', 'isNotEmpty']);

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
  draft: AutomationConditionDraft;
  allowBlockResult?: boolean;
  allBlocks?: BlockInfo[];
  currentBlockDraftId?: string;
  continueOnError?: boolean;
  onChange: (updated: AutomationConditionDraft) => void;
}

export function ConditionEditor({ draft, allBlocks, currentBlockDraftId, onChange }: ConditionEditorProps) {
  const registry = useDeviceRegistry();
  const api = useApi();

  const STATE_TYPE_SYMBOL: Record<string, string> = { number: '#', string: 'Aa', boolean: '◉', datetime: '⏱' };

  const [controllerStates, setControllerStates] = useState<{ id: string; name: string; displayName?: string; type: string }[]>([]);
  useEffect(() => {
    if (draft.type !== 'engineState') return;
    let cancelled = false;
    api.getStateVariables().then(vars => {
      if (!cancelled) setControllerStates(vars.map(v => ({ id: v.id, name: v.name, displayName: v.displayName, type: v.type })));
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [api, draft.type]);

  const currentOrdinal = useMemo(
    () => allBlocks?.find((b) => b._draftId === currentBlockDraftId)?.ordinal,
    [allBlocks, currentBlockDraftId],
  );

  const precedingBlocks = useMemo(() => {
    if (!allBlocks || currentOrdinal === undefined) return [];
    return allBlocks.filter((b) => b.ordinal < currentOrdinal);
  }, [allBlocks, currentOrdinal]);

  const patch = useCallback(
    (changes: Partial<AutomationConditionDraft>) => onChange({ ...draft, ...changes }),
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

      {/* engineState */}
      {draft.type === 'engineState' && (() => {
        const comp = draft.comparison as unknown as { type?: string; value?: unknown } | undefined;
        const compType = comp?.type || 'equals';
        const compVal = comp?.value ?? '';
        const selectedName = draft.variableRef?.name || '';
        const selectedState = controllerStates.find(s => s.name === selectedName);
        const selectedType = selectedState?.type;

        return (
          <>
            <div className="editor-field">
              <label>Global Value</label>
              <select
                className="editor-select"
                value={selectedName}
                onChange={(e) => {
                  const name = e.target.value;
                  const state = controllerStates.find(s => s.name === name);
                  // Set a type-appropriate default comparison value
                  const defaultVal = state?.type === 'number' ? 0
                    : state?.type === 'boolean' ? true
                    : state?.type === 'datetime' ? '__now__'
                    : '';
                  patch({
                    variableRef: { type: 'byName', name },
                    comparison: { type: 'equals', value: defaultVal } as unknown as typeof draft.comparison,
                  });
                }}
              >
                <option value="">-- Select state --</option>
                {controllerStates.map(s => (
                  <option key={s.id} value={s.name}>({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}</option>
                ))}
              </select>
            </div>
            {selectedName && (
              <>
                <div className="editor-field">
                  <label>Comparison</label>
                  <select
                    className="editor-select"
                    value={compType}
                    onChange={(e) => {
                      patch({ comparison: { type: e.target.value, value: compVal } as unknown as typeof draft.comparison });
                    }}
                  >
                    {(selectedType
                      ? COMPARISON_OPS.filter(op => op.types.length === 0 || op.types.includes(selectedType))
                      : COMPARISON_OPS
                    ).map((op) => (
                      <option key={op.value} value={op.value}>{op.label}</option>
                    ))}
                  </select>
                </div>
                {!NO_VALUE_OPS.has(compType) && (
                <div className="editor-field">
                  <label>Compare To</label>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <select
                      className="editor-select"
                      style={{ width: 'auto', flex: '0 0 auto' }}
                      value={draft.stateCompareMode || 'literal'}
                      onChange={(e) => patch({ stateCompareMode: e.target.value as 'literal' | 'stateRef' })}
                    >
                      <option value="literal">Value</option>
                      <option value="stateRef">State</option>
                    </select>
                    {(draft.stateCompareMode || 'literal') === 'literal' && (
                      <>
                        {selectedType === 'number' && (
                          <input className="editor-input" style={{ flex: 1 }} type="number" step="any" value={String(compVal)}
                            onChange={(e) => patch({ comparison: { type: compType, value: e.target.value } as unknown as typeof draft.comparison })} />
                        )}
                        {selectedType === 'boolean' && (
                          <>
                            <button type="button" className={`sv-switch${(compVal === true || compVal === 'true') ? ' on' : ''}`}
                              onClick={() => patch({ comparison: { type: compType, value: !(compVal === true || compVal === 'true') } as unknown as typeof draft.comparison })} />
                            <span style={{ fontSize: 'var(--font-size-sm)', fontFamily: 'var(--font-mono)', color: 'var(--text-secondary)' }}>{(compVal === true || compVal === 'true') ? 'true' : 'false'}</span>
                          </>
                        )}
                        {selectedType === 'datetime' && (() => {
                          const cv = String(compVal ?? '');
                          const isNow = cv === '__now__';
                          const isRelative = !isNow && cv.startsWith('__now') && cv.endsWith('__');
                          const dtMode = isNow ? 'now' : isRelative ? 'relative' : 'specific';
                          // Parse relative offset for UI
                          let relAmount = 24, relUnit = 'h', relSign = '-';
                          if (isRelative) {
                            const inner = cv.slice(5, -2); // e.g. "-24h"
                            const m = inner.match(/^([+-]?)(\d+(?:\.\d+)?)([smhd])$/);
                            if (m) { relSign = m[1] || '+'; relAmount = parseFloat(m[2]!); relUnit = m[3]!; }
                          }
                          const buildSentinel = (sign: string, amt: number, unit: string) => `__now${sign}${amt}${unit}__`;
                          const patchDt = (val: unknown) => patch({ comparison: { type: compType, value: val } as unknown as typeof draft.comparison, dynamicDateValue: typeof val === 'string' && (val === '__now__' || (val.startsWith('__now') && val.endsWith('__'))) ? val : undefined });
                          return (
                            <div style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: 1 }}>
                              <select className="editor-select" value={dtMode}
                                onChange={(e) => {
                                  if (e.target.value === 'now') patchDt('__now__');
                                  else if (e.target.value === 'relative') patchDt(buildSentinel('-', 24, 'h'));
                                  else patchDt(new Date().toISOString());
                                }}>
                                <option value="now">Now (current time)</option>
                                <option value="relative">Relative to now</option>
                                <option value="specific">Specific date</option>
                              </select>
                              {dtMode === 'relative' && (
                                <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                                  <input className="editor-input" type="number" min={0} step="any"
                                    style={{ width: 70 }} value={relAmount}
                                    onChange={(e) => patchDt(buildSentinel(relSign, parseFloat(e.target.value) || 0, relUnit))} />
                                  <select className="editor-select" style={{ flex: 1 }} value={relUnit}
                                    onChange={(e) => patchDt(buildSentinel(relSign, relAmount, e.target.value))}>
                                    <option value="m">Minutes</option>
                                    <option value="h">Hours</option>
                                    <option value="d">Days</option>
                                  </select>
                                  <select className="editor-select" style={{ flex: 1 }} value={relSign === '-' ? 'ago' : 'from_now'}
                                    onChange={(e) => patchDt(buildSentinel(e.target.value === 'ago' ? '-' : '+', relAmount, relUnit))}>
                                    <option value="ago">ago</option>
                                    <option value="from_now">from now</option>
                                  </select>
                                </div>
                              )}
                              {dtMode === 'specific' && (
                                <input className="editor-input" type="datetime-local"
                                  value={(() => { try { return new Date(cv).toISOString().slice(0, 16); } catch { return ''; } })()}
                                  onChange={(e) => patchDt(new Date(e.target.value).toISOString())} />
                              )}
                            </div>
                          );
                        })()}
                        {(selectedType === 'string' || (!selectedType && selectedType !== 'datetime')) && (
                          <input className="editor-input" style={{ flex: 1 }} value={String(compVal)}
                            onChange={(e) => patch({ comparison: { type: compType, value: e.target.value } as unknown as typeof draft.comparison })} />
                        )}
                      </>
                    )}
                    {(draft.stateCompareMode || 'literal') === 'stateRef' && (
                      <select className="editor-select" style={{ flex: 1 }} value={draft.compareToStateRef?.name || ''}
                        onChange={(e) => patch({ compareToStateRef: { type: 'byName', name: e.target.value } })}>
                        <option value="">-- Select --</option>
                        {controllerStates.filter(s => s.name !== selectedName && (!selectedType || s.type === selectedType)).map(s => (
                          <option key={s.id} value={s.name}>({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}</option>
                        ))}
                      </select>
                    )}
                  </div>
                </div>
                )}
              </>
            )}
          </>
        );
      })()}
    </div>
  );
}
