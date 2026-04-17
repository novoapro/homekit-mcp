import { useCallback, useMemo, useState, useEffect } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { useApi } from '@/hooks/useApi';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import type { AutomationBlockDraft } from './automation-editor-types';
import { newUUID } from './automation-editor-types';
import { blockAutoName, conditionAutoName } from './automation-editor-utils';
import { SearchableSelect } from './SearchableSelect';
import { HTTP_METHODS, OUTCOMES, EXEC_MODES } from './block-helpers';
import type { Automation } from '@/types/automation-log';
import './BlockEditor.css';
import './TriggerEditor.css'; // shared form styles

interface BlockEditorProps {
  draft: AutomationBlockDraft;
  showHeader?: boolean;
  currentAutomationId?: string;
  onChange: (updated: AutomationBlockDraft) => void;
  onNavigateToNested?: (info: { field: string; label: string }) => void;
}

export function BlockEditor({
  draft,
  showHeader = true,
  currentAutomationId,
  onChange,
  onNavigateToNested,
}: BlockEditorProps) {
  const registry = useDeviceRegistry();
  const api = useApi();

  const STATE_TYPE_SYMBOL: Record<string, string> = { number: '#', string: 'Aa', boolean: '◉', datetime: '⏱' };

  // Fetch global values for stateVariable, controlDevice (global mode), and engineState blocks
  const [controllerStates, setControllerStates] = useState<{ id: string; name: string; displayName?: string; type: string }[]>([]);
  const needsGlobalValues = draft.type === 'stateVariable' || draft.type === 'controlDevice' || draft.type === 'timedControl' || draft.type === 'delay';
  useEffect(() => {
    if (!needsGlobalValues) return;
    let cancelled = false;
    api.getStateVariables().then(vars => {
      if (!cancelled) setControllerStates(vars.map(v => ({ id: v.id, name: v.name, displayName: v.displayName, type: v.type })));
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [api, needsGlobalValues]);

  // Fetch callable automations (those with a 'automation' trigger)
  const [callableAutomations, setCallableAutomations] = useState<Automation[]>([]);
  useEffect(() => {
    if (draft.type !== 'executeAutomation') return;
    let cancelled = false;
    api.getAutomations().then(automations => {
      if (cancelled) return;
      const callable = automations.filter(w =>
        w.id !== currentAutomationId &&
        w.triggers.some(t => t.type === 'automation')
      );
      setCallableAutomations(callable);
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [api, draft.type, currentAutomationId]);

  const stateDisplayNames = useMemo(() => {
    const map: Record<string, string> = {};
    for (const s of controllerStates) {
      map[s.name] = s.displayName || s.name;
    }
    return map;
  }, [controllerStates]);

  const autoDescription = useMemo(
    () => draft.name || blockAutoName(draft, registry, stateDisplayNames),
    [draft, registry, stateDisplayNames],
  );

  const patch = useCallback(
    (changes: Partial<AutomationBlockDraft>) => onChange({ ...draft, ...changes }),
    [draft, onChange],
  );

  // Condition summary for blocks that have conditions
  const conditionSummary = useCallback(
    (fallback: string) => {
      if (!draft.condition) return fallback;
      const name = conditionAutoName(draft.condition, registry);
      return name || fallback;
    },
    [draft.condition, registry],
  );

  const conditionChildCount = useMemo(() => {
    if (!draft.condition) return 0;
    const c = draft.condition;
    if (c.type === 'and' || c.type === 'or') return c.conditions?.length ?? 0;
    if (c.type === 'not' && c.condition) {
      const inner = c.condition;
      if (inner.type === 'and' || inner.type === 'or') return inner.conditions?.length ?? 0;
      return 1;
    }
    return 1;
  }, [draft.condition]);

  return (
    <div className="block-editor">
      {showHeader && (
        <div className="block-editor-header">
          <span className={`block-type-badge badge-${draft.block}`}>
            {draft.block === 'action' ? 'Action' : 'Flow'}
          </span>
          <div className="block-title-group">
            <span className="block-type-label">{autoDescription}</span>
          </div>
        </div>
      )}

      {/* Optional label */}
      <div className="editor-field">
        <label>Label (optional)</label>
        <input
          className="editor-input"
          value={draft.name || ''}
          onChange={(e) => patch({ name: e.target.value || undefined })}
          placeholder="Human-readable label"
        />
      </div>

      {/* controlDevice */}
      {draft.type === 'controlDevice' && (
        <>
          <DevicePicker
            initialDeviceId={draft.deviceId}
            initialServiceId={draft.serviceId}
            initialCharId={draft.characteristicId}
            writableOnly
            onChange={(val) => patch({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId })}
          />

          {/* Single combined value picker + one value input below */}
          {(() => {
            const char = draft.deviceId && draft.characteristicId
              ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
              : undefined;
            const NUMERIC_FORMATS = new Set(['uint8', 'uint16', 'uint32', 'uint64', 'int', 'float']);
            const compatibleType = char
              ? char.format === 'bool' ? 'boolean'
                : NUMERIC_FORMATS.has(char.format) ? 'number'
                : char.format === 'string' ? 'string'
                : undefined
              : undefined;
            const compatibleStates = compatibleType
              ? controllerStates.filter(s => s.type === compatibleType)
              : controllerStates;

            if (compatibleStates.length === 0) return null;
            return (
              <div className="editor-field">
                <label>Value</label>
                <select className="editor-select"
                  value={draft.valueSource === 'global' ? (draft.valueRef?.name || '') : ''}
                  onChange={(e) => {
                    const v = e.target.value;
                    patch(v
                      ? { valueSource: 'global', valueRef: { type: 'byName', name: v } }
                      : { valueSource: 'local', valueRef: undefined });
                  }}>
                  <option value="">Use local value only</option>
                  {compatibleStates.map(s => (
                    <option key={s.id} value={s.name}>
                      ({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}
                    </option>
                  ))}
                </select>
              </div>
            );
          })()}

          <CharacteristicValueInput
            characteristic={draft.deviceId && draft.characteristicId
              ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
              : undefined}
            value={draft.value}
            onChange={(val) => patch({ value: val })}
          />
        </>
      )}

      {/* timedControl */}
      {draft.type === 'timedControl' && (
        <>
          {/* Duration: single combined picker + one seconds field below */}
          {controllerStates.filter(s => s.type === 'number').length > 0 && (
            <div className="editor-field">
              <label>Duration</label>
              <select className="editor-select"
                value={draft.durationSource === 'global' ? (draft.durationRef?.name || '') : ''}
                onChange={(e) => {
                  const v = e.target.value;
                  patch(v
                    ? { durationSource: 'global', durationRef: { type: 'byName', name: v } }
                    : { durationSource: 'local', durationRef: undefined });
                }}>
                <option value="">Use local value only</option>
                {controllerStates.filter(s => s.type === 'number').map(s => (
                  <option key={s.id} value={s.name}>
                    ({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          <div className="editor-field">
            <label>Hold seconds</label>
            <input className="editor-input" type="number" min={0} step={0.5}
              value={draft.durationSeconds ?? 5}
              onChange={(e) => patch({ durationSeconds: +e.target.value || 5 })} />
          </div>

          {/* Changes list */}
          <div className="editor-field">
            <label>Changes · reverted in this order when time is up</label>
            {(draft.changes ?? []).map((change, idx) => (
              <div key={change._draftId} style={{ border: '1px solid var(--border-color, #ddd)', borderRadius: 8, padding: 8, marginBottom: 8 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                  <strong style={{ fontSize: 12 }}>Change {idx + 1}</strong>
                  {(draft.changes?.length ?? 0) > 1 && (
                    <button type="button" className="editor-button-secondary"
                      onClick={() => {
                        const next = [...(draft.changes ?? [])];
                        next.splice(idx, 1);
                        patch({ changes: next });
                      }}>
                      Remove
                    </button>
                  )}
                </div>
                <DevicePicker
                  initialDeviceId={change.deviceId}
                  initialServiceId={change.serviceId}
                  initialCharId={change.characteristicId}
                  writableOnly
                  onChange={(val) => {
                    const next = [...(draft.changes ?? [])];
                    next[idx] = { ...change, deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId };
                    patch({ changes: next });
                  }}
                />
                {(() => {
                  const char = change.deviceId && change.characteristicId
                    ? registry.lookupCharacteristic(change.deviceId, change.characteristicId)
                    : undefined;
                  const NUMERIC_FORMATS = new Set(['uint8', 'uint16', 'uint32', 'uint64', 'int', 'float']);
                  const compatibleType = char
                    ? char.format === 'bool' ? 'boolean'
                      : NUMERIC_FORMATS.has(char.format) ? 'number'
                      : char.format === 'string' ? 'string'
                      : undefined
                    : undefined;
                  const compatibleStates = compatibleType
                    ? controllerStates.filter(s => s.type === compatibleType)
                    : controllerStates;

                  if (compatibleStates.length === 0) return null;
                  return (
                    <div className="editor-field">
                      <label>Value</label>
                      <select className="editor-select"
                        value={change.valueSource === 'global' ? (change.valueRef?.name || '') : ''}
                        onChange={(e) => {
                          const v = e.target.value;
                          const next = [...(draft.changes ?? [])];
                          next[idx] = v
                            ? { ...change, valueSource: 'global', valueRef: { type: 'byName', name: v } }
                            : { ...change, valueSource: 'local', valueRef: undefined };
                          patch({ changes: next });
                        }}>
                        <option value="">Use local value only</option>
                        {compatibleStates.map(s => (
                          <option key={s.id} value={s.name}>
                            ({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}
                          </option>
                        ))}
                      </select>
                    </div>
                  );
                })()}
                <CharacteristicValueInput
                  characteristic={change.deviceId && change.characteristicId
                    ? registry.lookupCharacteristic(change.deviceId, change.characteristicId)
                    : undefined}
                  value={change.value}
                  onChange={(val) => {
                    const next = [...(draft.changes ?? [])];
                    next[idx] = { ...change, value: val };
                    patch({ changes: next });
                  }}
                />
              </div>
            ))}
            <button type="button" className="editor-button-secondary"
              onClick={() => {
                const newChange = { _draftId: newUUID(), valueSource: 'local' as const, value: true };
                patch({ changes: [...(draft.changes ?? []), newChange] });
              }}>
              + Add Change
            </button>
          </div>
        </>
      )}

      {/* runScene */}
      {draft.type === 'runScene' && (
        <div className="editor-field">
          <label>Scene</label>
          <select className="editor-select" value={draft.sceneId || ''} onChange={(e) => patch({ sceneId: e.target.value })}>
            <option value="">-- Select scene --</option>
            {registry.scenes.map((scene) => (
              <option key={scene.id} value={scene.id}>{scene.name}</option>
            ))}
          </select>
        </div>
      )}

      {/* webhook */}
      {draft.type === 'webhook' && (
        <>
          <div className="editor-field">
            <label>URL</label>
            <input
              className="editor-input"
              type="url"
              value={draft.url || ''}
              onChange={(e) => patch({ url: e.target.value })}
              placeholder="https://example.com/hook"
            />
          </div>
          <div className="editor-field">
            <label>Method</label>
            <select className="editor-select" value={draft.method || 'POST'} onChange={(e) => patch({ method: e.target.value })}>
              {HTTP_METHODS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </div>
        </>
      )}

      {/* log */}
      {draft.type === 'log' && (
        <div className="editor-field">
          <label>Message</label>
          <textarea
            className="editor-input"
            value={draft.message || ''}
            onChange={(e) => patch({ message: e.target.value })}
            placeholder="Log message..."
            rows={2}
            style={{ resize: 'vertical' }}
          />
        </div>
      )}

      {/* stateVariable */}
      {draft.type === 'stateVariable' && (() => {
        const op = draft.operation || { operation: 'set', variableRef: { type: 'byName', name: '' } };
        const patchOp = (updates: Record<string, unknown>) => patch({ operation: { ...op, ...updates } });

        const selectedName = op.operation === 'create' ? '__create__' : (op.variableRef?.name || '');
        const selectedState = controllerStates.find(s => s.name === selectedName);
        const selectedType = selectedState?.type;

        const ALL_OPS = [
          { value: 'remove', label: 'Remove', types: [] as string[] },
          { value: 'set', label: 'Set Value', types: [] as string[] },
          { value: 'setFromCharacteristic', label: 'Set from Device', types: [] as string[] },
          { value: 'increment', label: 'Increment', types: ['number'] },
          { value: 'decrement', label: 'Decrement', types: ['number'] },
          { value: 'multiply', label: 'Multiply', types: ['number'] },
          { value: 'addState', label: 'Add State', types: ['number'] },
          { value: 'subtractState', label: 'Subtract State', types: ['number'] },
          { value: 'toggle', label: 'Toggle', types: ['boolean'] },
          { value: 'andState', label: 'AND State', types: ['boolean'] },
          { value: 'orState', label: 'OR State', types: ['boolean'] },
          { value: 'notState', label: 'NOT State', types: ['boolean'] },
          { value: 'setToNow', label: 'Set to Now', types: ['datetime'] },
          { value: 'addTime', label: 'Add Time', types: ['datetime'] },
          { value: 'subtractTime', label: 'Subtract Time', types: ['datetime'] },
        ];
        const filteredOps = selectedType
          ? ALL_OPS.filter(o => o.types.length === 0 || o.types.includes(selectedType))
          : ALL_OPS;

        const NUMERIC_FORMATS_SET = new Set(['uint8', 'uint16', 'uint32', 'uint64', 'int', 'float']);
        const BOOL_FORMATS_SET = new Set(['bool']);
        const STRING_FORMATS_SET = new Set(['string']);
        const formatFilterForType = selectedType === 'number' ? NUMERIC_FORMATS_SET
          : selectedType === 'boolean' ? BOOL_FORMATS_SET
          : selectedType === 'string' ? STRING_FORMATS_SET
          : undefined;

        const isCreate = op.operation === 'create';
        const needsAmount = ['increment', 'decrement', 'multiply'].includes(op.operation);
        const needsValue = ['set'].includes(op.operation);
        const needsOtherRef = ['addState', 'subtractState', 'andState', 'orState'].includes(op.operation);
        const needsDevice = op.operation === 'setFromCharacteristic';
        const needsTimeAmount = ['addTime', 'subtractTime'].includes(op.operation);

        const sanitizeName = (v: string) => v.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '').replace(/_+/g, '_');

        return (
          <>
            {/* Step 1: Pick state or create new */}
            <div className="editor-field">
              <label>Global Value</label>
              <select className="editor-select" value={selectedName} onChange={(e) => {
                if (e.target.value === '__create__') {
                  patchOp({ operation: 'create', variableRef: undefined, name: '', variableType: 'number', initialValue: 0 });
                } else {
                  const newOp = op.operation === 'create' ? 'set' : op.operation;
                  // Reset op if not applicable to new type
                  const newState = controllerStates.find(s => s.name === e.target.value);
                  const applicable = ALL_OPS.find(o => o.value === newOp);
                  const finalOp = applicable && (applicable.types.length === 0 || applicable.types.includes(newState?.type || ''))
                    ? newOp : 'set';
                  patchOp({ operation: finalOp, variableRef: { type: 'byName', name: e.target.value } });
                }
              }}>
                <option value="">-- Select state --</option>
                {controllerStates.map(s => <option key={s.id} value={s.name}>({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}</option>)}
                <option value="__create__">Create New...</option>
              </select>
            </div>

            {isCreate ? (
              <>
                <div className="editor-field">
                  <label>Name</label>
                  <input className="editor-input" value={op.name || ''} onChange={(e) => patchOp({ name: sanitizeName(e.target.value) })} placeholder="my_counter" />
                  <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>Lowercase, no spaces (a-z, 0-9, _)</span>
                </div>
                <div className="editor-field">
                  <label>Type</label>
                  <select className="editor-select" value={op.variableType || 'number'} onChange={(e) => {
                    const t = e.target.value;
                    const defaultValue = t === 'number' ? 0 : t === 'boolean' ? false : t === 'datetime' ? new Date().toISOString() : '';
                    patchOp({ variableType: t, initialValue: defaultValue });
                  }}>
                    <option value="number">Number</option>
                    <option value="string">String</option>
                    <option value="boolean">Boolean</option>
                    <option value="datetime">Date & Time</option>
                  </select>
                </div>
                <div className="editor-field">
                  <label>Initial Value</label>
                  {(op.variableType || 'number') === 'number' && (
                    <input className="editor-input" type="number" step="any" value={String(op.initialValue ?? 0)} onChange={(e) => patchOp({ initialValue: parseFloat(e.target.value) || 0 })} />
                  )}
                  {(op.variableType || 'number') === 'string' && (
                    <input className="editor-input" value={String(op.initialValue ?? '')} onChange={(e) => patchOp({ initialValue: e.target.value })} />
                  )}
                  {(op.variableType || 'number') === 'boolean' && (
                    <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                      <button type="button" className={`sv-switch${op.initialValue ? ' on' : ''}`} onClick={() => patchOp({ initialValue: !op.initialValue })} />
                      <span>{op.initialValue ? 'true' : 'false'}</span>
                    </label>
                  )}
                </div>
              </>
            ) : selectedName ? (
              <>
                {/* Step 2: Operation (type-filtered) */}
                <div className="editor-field">
                  <label>Operation</label>
                  <select className="editor-select" value={op.operation} onChange={(e) => {
                    const newOp = e.target.value;
                    const defaults: Record<string, unknown> = { operation: newOp };
                    // Set sensible defaults so pre-populated fields are saved even without user interaction
                    if (['set'].includes(newOp) && op.value === undefined) {
                      if (selectedType === 'number') defaults.value = 0;
                      else if (selectedType === 'boolean') defaults.value = false;
                      else if (selectedType === 'datetime') defaults.value = new Date().toISOString();
                      else defaults.value = '';
                    }
                    if (['increment', 'decrement', 'multiply'].includes(newOp) && op.by === undefined) defaults.by = 1;
                    if (['addTime', 'subtractTime'].includes(newOp)) {
                      if (op.amount === undefined) defaults.amount = 1;
                      if (op.unit === undefined) defaults.unit = 'minutes';
                    }
                    patchOp(defaults);
                  }}>
                    {filteredOps.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </select>
                </div>

                {/* Step 3: Type-specific value inputs */}
                {needsValue && (
                  <div className="editor-field">
                    <label>Value</label>
                    {selectedType === 'number' && (
                      <input className="editor-input" type="number" step="any" value={String(op.value ?? '')} onChange={(e) => patchOp({ value: e.target.value })} />
                    )}
                    {selectedType === 'boolean' && (
                      <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
                        <button type="button" className={`sv-switch${(op.value === true || op.value === 'true') ? ' on' : ''}`} onClick={() => patchOp({ value: !(op.value === true || op.value === 'true') })} />
                        <span>{(op.value === true || op.value === 'true') ? 'true' : 'false'}</span>
                      </label>
                    )}
                    {selectedType === 'datetime' && (
                      <input className="editor-input" type="datetime-local"
                        value={(() => { try { return new Date(String(op.value || '')).toISOString().slice(0, 16); } catch { return ''; } })()}
                        onChange={(e) => patchOp({ value: new Date(e.target.value).toISOString() })} />
                    )}
                    {(selectedType === 'string' || (!selectedType && selectedType !== 'datetime')) && (
                      <input className="editor-input" value={String(op.value ?? '')} onChange={(e) => patchOp({ value: e.target.value })} />
                    )}
                  </div>
                )}
                {needsAmount && (
                  <div className="editor-field">
                    <label>Amount</label>
                    <input className="editor-input" type="number" step="any" value={op.by ?? 1} onChange={(e) => patchOp({ by: parseFloat(e.target.value) || 0 })} />
                  </div>
                )}
                {needsTimeAmount && (
                  <>
                    <div className="editor-field">
                      <label>Amount</label>
                      <input className="editor-input" type="number" step="any" min={0} value={op.amount ?? 1}
                        onChange={(e) => patchOp({ amount: parseFloat(e.target.value) || 0 })} />
                    </div>
                    <div className="editor-field">
                      <label>Unit</label>
                      <select className="editor-select" value={op.unit || 'minutes'}
                        onChange={(e) => patchOp({ unit: e.target.value })}>
                        <option value="seconds">Seconds</option>
                        <option value="minutes">Minutes</option>
                        <option value="hours">Hours</option>
                        <option value="days">Days</option>
                      </select>
                    </div>
                  </>
                )}
                {needsDevice && (
                  <DevicePicker
                    initialDeviceId={op.deviceId}
                    initialServiceId={op.serviceId}
                    initialCharId={op.characteristicId}
                    formatFilter={formatFilterForType}
                    onChange={(val) => patchOp({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId })}
                  />
                )}
                {needsOtherRef && (
                  <div className="editor-field">
                    <label>Other State</label>
                    <select className="editor-select" value={op.otherRef?.name || ''} onChange={(e) => patchOp({ otherRef: { type: 'byName', name: e.target.value } })}>
                      <option value="">-- Select --</option>
                      {controllerStates.filter(s => s.name !== selectedName && (!selectedType || s.type === selectedType)).map(s => (
                        <option key={s.id} value={s.name}>({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}</option>
                      ))}
                    </select>
                  </div>
                )}
              </>
            ) : null}
          </>
        );
      })()}

      {/* delay */}
      {draft.type === 'delay' && (() => {
        const numberStates = controllerStates.filter(s => s.type === 'number');
        return (
          <>
            {numberStates.length > 0 && (
              <div className="editor-field">
                <label>Duration</label>
                <select className="editor-select"
                  value={draft.secondsSource === 'global' ? (draft.secondsRef?.name || '') : ''}
                  onChange={(e) => {
                    const v = e.target.value;
                    patch(v
                      ? { secondsSource: 'global', secondsRef: { type: 'byName', name: v } }
                      : { secondsSource: 'local', secondsRef: undefined });
                  }}>
                  <option value="">Use local value only</option>
                  {numberStates.map(s => (
                    <option key={s.id} value={s.name}>
                      ({STATE_TYPE_SYMBOL[s.type] || s.type}) {s.displayName || s.name}
                    </option>
                  ))}
                </select>
              </div>
            )}
            <div className="editor-field">
              <label>Duration (seconds)</label>
              <input className="editor-input" type="number" min={0} step={0.1}
                value={draft.seconds ?? 1}
                onChange={(e) => patch({ seconds: +e.target.value })} />
            </div>
          </>
        );
      })()}

      {/* waitForState */}
      {draft.type === 'waitForState' && (
        <>
          {onNavigateToNested && (
            <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'condition', label: 'Wait Condition' })}>
              <span className="nested-nav-icon"><Icon name="arrow-triangle-branch" size={14} /></span>
              <span className="nested-nav-text">{conditionSummary('Condition to wait for')}</span>
              <span className="nested-nav-count">{conditionChildCount}</span>
              <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
            </button>
          )}
          <div className="editor-field">
            <label>Timeout (seconds)</label>
            <input
              className="editor-input"
              type="number"
              min={1}
              value={draft.timeoutSeconds ?? 30}
              onChange={(e) => patch({ timeoutSeconds: +e.target.value })}
            />
          </div>
        </>
      )}

      {/* conditional */}
      {draft.type === 'conditional' && (
        <>
          {onNavigateToNested && (
            <>
              <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'condition', label: 'If Condition' })}>
                <span className="nested-nav-icon"><Icon name="arrow-triangle-branch" size={14} /></span>
                <span className="nested-nav-text">{conditionSummary('If Condition')}</span>
                <span className="nested-nav-count">{conditionChildCount}</span>
                <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
              </button>
              <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'thenBlocks', label: 'Then Blocks' })}>
                <span className="nested-nav-icon then"><Icon name="checkmark-circle" size={14} /></span>
                <span className="nested-nav-text">Then Blocks</span>
                <span className="nested-nav-count">{(draft.thenBlocks || []).length}</span>
                <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
              </button>
              <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'elseBlocks', label: 'Else Blocks' })}>
                <span className="nested-nav-icon else"><Icon name="xmark-circle" size={14} /></span>
                <span className="nested-nav-text">Else Blocks</span>
                <span className="nested-nav-count">{(draft.elseBlocks || []).length}</span>
                <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
              </button>
            </>
          )}
        </>
      )}

      {/* repeat */}
      {draft.type === 'repeat' && (
        <>
          <div className="editor-field-row">
            <div className="editor-field">
              <label>Count</label>
              <input className="editor-input" type="number" min={1} value={draft.count ?? 1} onChange={(e) => patch({ count: +e.target.value })} />
            </div>
            <div className="editor-field">
              <label>Delay between (sec)</label>
              <input className="editor-input" type="number" min={0} step={0.1} value={draft.delayBetweenSeconds ?? 0} onChange={(e) => patch({ delayBetweenSeconds: +e.target.value })} />
            </div>
          </div>
          {onNavigateToNested && (
            <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'blocks', label: 'Repeat Blocks' })}>
              <span className="nested-nav-icon"><Icon name="arrow-2-squarepath" size={14} /></span>
              <span className="nested-nav-text">Repeat Blocks</span>
              <span className="nested-nav-count">{(draft.blocks || []).length}</span>
              <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
            </button>
          )}
        </>
      )}

      {/* repeatWhile */}
      {draft.type === 'repeatWhile' && (
        <>
          {onNavigateToNested && (
            <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'condition', label: 'While Condition' })}>
              <span className="nested-nav-icon"><Icon name="arrow-triangle-branch" size={14} /></span>
              <span className="nested-nav-text">{conditionSummary('While Condition')}</span>
              <span className="nested-nav-count">{conditionChildCount}</span>
              <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
            </button>
          )}
          <div className="editor-field">
            <label>Max iterations</label>
            <input className="editor-input" type="number" min={1} value={draft.maxIterations ?? 10} onChange={(e) => patch({ maxIterations: +e.target.value })} />
          </div>
          {onNavigateToNested && (
            <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'blocks', label: 'Loop Blocks' })}>
              <span className="nested-nav-icon"><Icon name="arrow-2-squarepath" size={14} /></span>
              <span className="nested-nav-text">Loop Blocks</span>
              <span className="nested-nav-count">{(draft.blocks || []).length}</span>
              <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
            </button>
          )}
        </>
      )}

      {/* group */}
      {draft.type === 'group' && (
        <>
          <div className="editor-field">
            <label>Group Label</label>
            <input className="editor-input" value={draft.label || ''} onChange={(e) => patch({ label: e.target.value })} placeholder="Group name" />
          </div>
          {onNavigateToNested && (
            <button className="nested-nav-btn" type="button" onClick={() => onNavigateToNested({ field: 'blocks', label: 'Group Blocks' })}>
              <span className="nested-nav-icon"><Icon name="folder" size={14} /></span>
              <span className="nested-nav-text">Group Blocks</span>
              <span className="nested-nav-count">{(draft.blocks || []).length}</span>
              <Icon name="chevron-right" size={12} className="nested-nav-chevron" />
            </button>
          )}
        </>
      )}

      {/* return */}
      {draft.type === 'return' && (
        <div className="editor-field">
          <label>Outcome</label>
          <select className="editor-select" value={draft.outcome || 'success'} onChange={(e) => patch({ outcome: e.target.value })}>
            {OUTCOMES.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
      )}

      {/* executeAutomation */}
      {draft.type === 'executeAutomation' && (
        <>
          <SearchableSelect
            label="Target Automation"
            options={callableAutomations.map((w) => ({ id: w.id, label: w.name }))}
            selectedId={draft.targetAutomationId || ''}
            placeholder="Search automations..."
            onSelect={(id) => patch({ targetAutomationId: id })}
            onClear={() => patch({ targetAutomationId: undefined })}
          />
          {callableAutomations.length === 0 && (
            <span className="editor-hint">No callable automations found. Add a "Automation" trigger to a automation to make it callable.</span>
          )}
          <SearchableSelect
            label="Execution Mode"
            options={EXEC_MODES.map((m) => ({ id: m.value, label: m.label }))}
            selectedId={draft.executionMode || 'inline'}
            placeholder="Select mode..."
            onSelect={(id) => patch({ executionMode: id })}
            onClear={() => patch({ executionMode: 'inline' })}
          />
        </>
      )}
    </div>
  );
}
