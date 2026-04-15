import { useMemo, useCallback, useState, useEffect } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import { CurrentValueIndicator } from './CurrentValueIndicator';
import { useConfig } from '@/contexts/ConfigContext';
import type { AutomationTriggerDraft, AutomationConditionDraft } from './automation-editor-types';
import { newUUID } from './automation-editor-types';
import { conditionAutoName, type StateDisplayNames } from './automation-editor-utils';
import { useApi } from '@/hooks/useApi';
import type { StateVariable } from '@/lib/api';
import './TriggerEditor.css';

const SCHEDULE_TYPES = [
  { value: 'once', label: 'Once' },
  { value: 'daily', label: 'Daily' },
  { value: 'weekly', label: 'Weekly' },
  { value: 'interval', label: 'Interval' },
];

const TRIGGER_CONDITIONS = [
  { value: 'changed', label: 'Changes' },
  { value: 'equals', label: 'Equals' },
  { value: 'notEquals', label: 'Not Equals' },
  { value: 'greaterThan', label: 'Greater Than' },
  { value: 'lessThan', label: 'Less Than' },
  { value: 'greaterThanOrEqual', label: 'Greater Than or Equal' },
  { value: 'lessThanOrEqual', label: 'Less Than or Equal' },
  { value: 'transitioned', label: 'Transitioned' },
];

const RETRIGGER_POLICIES = [
  { value: 'ignoreNew', label: 'Ignore new (default)' },
  { value: 'cancelAndRestart', label: 'Cancel & restart' },
  { value: 'queueAndExecute', label: 'Queue & execute' },
  { value: 'cancelOnly', label: 'Cancel only' },
];

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];


interface TriggerEditorProps {
  draft: AutomationTriggerDraft;
  onChange: (updated: AutomationTriggerDraft) => void;
  onOpenGuardPanel?: () => void;
}

export function TriggerEditor({ draft, onChange, onOpenGuardPanel }: TriggerEditorProps) {
  const registry = useDeviceRegistry();
  const { baseUrl } = useConfig();
  const [copied, setCopied] = useState<'token' | 'url' | null>(null);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conditionType = (draft.matchOperator as any)?.type ?? 'changed';
  const patch = useCallback(
    (changes: Partial<AutomationTriggerDraft>) => onChange({ ...draft, ...changes }),
    [draft, onChange],
  );

  const timeString = (t: { hour: number; minute: number } | undefined): string => {
    if (!t) return '08:00';
    return `${String(t.hour).padStart(2, '0')}:${String(t.minute).padStart(2, '0')}`;
  };

  const onTimeChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const [h, m] = e.target.value.split(':');
      patch({ scheduleTime: { hour: +h!, minute: +m! } });
    },
    [patch],
  );

  const toggleDay = useCallback(
    (dayIdx: number) => {
      const current = draft.scheduleDays ?? [];
      const next = current.includes(dayIdx) ? current.filter((d) => d !== dayIdx) : [...current, dayIdx].sort();
      patch({ scheduleDays: next });
    },
    [draft.scheduleDays, patch],
  );

  return (
    <div className="trigger-editor">
      {/* ── Common fields ── */}

      {/* Label */}
      <div className="editor-field">
        <label>Label (optional)</label>
        <input
          className="editor-input"
          value={draft.name || ''}
          onChange={(e) => patch({ name: e.target.value || undefined })}
          placeholder="Human-readable label"
        />
      </div>

      {/* Trigger guard */}
      <TriggerConditionsSection draft={draft} onChange={onChange} onOpenGuardPanel={onOpenGuardPanel} />

      {/* Retrigger policy */}
      {draft.type !== 'automation' && (
        <div className="editor-field">
          <label>Retrigger Policy</label>
          <select
            className="editor-select"
            value={draft.retriggerPolicy || 'ignoreNew'}
            onChange={(e) => patch({ retriggerPolicy: e.target.value })}
          >
            {RETRIGGER_POLICIES.map((p) => (
              <option key={p.value} value={p.value}>{p.label}</option>
            ))}
          </select>
        </div>
      )}

      {/* ── Type-specific fields ── */}
      <div className="trigger-type-fields">
        <span className="trigger-type-fields-label">Event Settings</span>

        {/* deviceStateChange */}
        {draft.type === 'deviceStateChange' && (
          <>
            <DevicePicker
              initialDeviceId={draft.deviceId}
              initialServiceId={draft.serviceId}
              initialCharId={draft.characteristicId}
              notifiableOnly
              onChange={(val) => patch({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId })}
            />
            {draft.deviceId && draft.characteristicId && (
              <CurrentValueIndicator
                characteristic={registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)}
                isReachable={registry.lookupDevice(draft.deviceId)?.isReachable}
              />
            )}
            <div className="editor-field">
              <label>Match Operator</label>
              <select
                className="editor-select"
                value={conditionType}
                onChange={(e) => {
                  const type = e.target.value;
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  let condition: any = { type };
                  if (type !== 'changed') condition.value = true;
                  if (type === 'transitioned') { delete condition.value; condition.from = undefined; condition.to = true; }
                  patch({ matchOperator: condition });
                }}
              >
                {TRIGGER_CONDITIONS.map((c) => (
                  <option key={c.value} value={c.value}>{c.label}</option>
                ))}
              </select>
            </div>
            {conditionType !== 'changed' && conditionType !== 'transitioned' && (
              <CharacteristicValueInput
                characteristic={draft.deviceId && draft.characteristicId
                  ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
                  : undefined}
                value={(draft.matchOperator as any)?.value}
                forceEditable
                onChange={(val) => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const current = { ...(draft.matchOperator ?? { type: 'equals' }) } as any;
                  current.value = val;
                  patch({ matchOperator: current });
                }}
              />
            )}
            {conditionType === 'transitioned' && (
              <div className="editor-field-row">
                <CharacteristicValueInput
                  characteristic={draft.deviceId && draft.characteristicId
                    ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
                    : undefined}
                  value={(draft.matchOperator as any)?.from}
                  label="From"
                  allowAny
                  forceEditable
                  onChange={(val) => {
                    // eslint-disable-next-line @typescript-eslint/no-explicit-any
                    const current = { ...(draft.matchOperator ?? { type: 'transitioned' }) } as any;
                    current.from = val;
                    patch({ matchOperator: current });
                  }}
                />
                <CharacteristicValueInput
                  characteristic={draft.deviceId && draft.characteristicId
                    ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
                    : undefined}
                  value={(draft.matchOperator as any)?.to}
                  label="To"
                  allowAny
                  forceEditable
                  onChange={(val) => {
                    // eslint-disable-next-line @typescript-eslint/no-explicit-any
                    const current = { ...(draft.matchOperator ?? { type: 'transitioned' }) } as any;
                    current.to = val;
                    patch({ matchOperator: current });
                  }}
                />
              </div>
            )}
          </>
        )}

        {/* schedule */}
        {draft.type === 'schedule' && (
          <>
            <div className="editor-field">
              <label>Schedule Type</label>
              <select
                className="editor-select"
                value={draft.scheduleType || 'daily'}
                onChange={(e) => {
                  const st = e.target.value;
                  patch({
                    scheduleType: st,
                    scheduleTime: draft.scheduleTime ?? { hour: 8, minute: 0 },
                    scheduleDays: st === 'weekly' ? [1, 2, 3, 4, 5] : undefined,
                  });
                }}
              >
                {SCHEDULE_TYPES.map((s) => (
                  <option key={s.value} value={s.value}>{s.label}</option>
                ))}
              </select>
            </div>

            {(draft.scheduleType || 'daily') === 'once' && (
              <>
                <div className="editor-field">
                  <label>Date</label>
                  <input
                    className="editor-input"
                    type="date"
                    value={draft.scheduleDate || ''}
                    onChange={(e) => patch({ scheduleDate: e.target.value })}
                  />
                </div>
                <div className="editor-field">
                  <label>Time</label>
                  <input className="editor-input" type="time" value={timeString(draft.scheduleTime)} onChange={onTimeChange} />
                </div>
              </>
            )}

            {(draft.scheduleType || 'daily') === 'daily' && (
              <div className="editor-field">
                <label>Time</label>
                <input className="editor-input" type="time" value={timeString(draft.scheduleTime)} onChange={onTimeChange} />
              </div>
            )}

            {draft.scheduleType === 'weekly' && (
              <>
                <div className="editor-field">
                  <label>Time</label>
                  <input className="editor-input" type="time" value={timeString(draft.scheduleTime)} onChange={onTimeChange} />
                </div>
                <div className="day-picker-section">
                  <span className="day-label">Days</span>
                  <div className="day-toggle-group">
                    {DAYS.map((day, i) => (
                      <button
                        key={day}
                        type="button"
                        className={`day-toggle${(draft.scheduleDays ?? []).includes(i) ? ' active' : ''}`}
                        onClick={() => toggleDay(i)}
                      >
                        {day}
                      </button>
                    ))}
                  </div>
                </div>
              </>
            )}

            {draft.scheduleType === 'interval' && (
              <div className="editor-field">
                <label>Every (seconds)</label>
                <input
                  className="editor-input"
                  type="number"
                  min={1}
                  value={draft.scheduleIntervalSeconds ?? 60}
                  onChange={(e) => patch({ scheduleIntervalSeconds: +e.target.value })}
                />
              </div>
            )}
          </>
        )}

        {/* sunEvent */}
        {draft.type === 'sunEvent' && (
          <div className="editor-field-row">
            <div className="editor-field">
              <label>Event</label>
              <select className="editor-select" value={draft.event || 'sunrise'} onChange={(e) => patch({ event: e.target.value as 'sunrise' | 'sunset' })}>
                <option value="sunrise">Sunrise</option>
                <option value="sunset">Sunset</option>
              </select>
            </div>
            <div className="editor-field">
              <label>Offset (minutes)</label>
              <input
                className="editor-input"
                type="number"
                value={draft.offsetMinutes ?? 0}
                onChange={(e) => patch({ offsetMinutes: +e.target.value })}
                placeholder="0 = exact, negative = before"
              />
            </div>
          </div>
        )}

        {/* webhook */}
        {draft.type === 'webhook' && (
          <div className="trigger-info-box">
            <strong>Token:</strong> {draft.token || '(auto-generated on save)'}
            {draft.token && (
              <div className="tree-copy-actions">
                <button
                  type="button"
                  className="tree-copy-btn"
                  onClick={() => {
                    navigator.clipboard.writeText(draft.token!);
                    setCopied('token');
                    setTimeout(() => setCopied(null), 2000);
                  }}
                >
                  <Icon name={copied === 'token' ? 'checkmark' : 'doc-on-doc'} size={12} />
                  {copied === 'token' ? 'Copied' : 'Copy token'}
                </button>
                <button
                  type="button"
                  className="tree-copy-btn"
                  onClick={() => {
                    navigator.clipboard.writeText(`${baseUrl}/automations/webhook/${draft.token}`);
                    setCopied('url');
                    setTimeout(() => setCopied(null), 2000);
                  }}
                >
                  <Icon name={copied === 'url' ? 'checkmark' : 'doc-on-doc'} size={12} />
                  {copied === 'url' ? 'Copied' : 'Copy URL'}
                </button>
              </div>
            )}
          </div>
        )}

        {/* automation */}
        {draft.type === 'automation' && (
          <div className="trigger-info-box">
            This automation can be triggered by other automations using the Execute Automation block.
          </div>
        )}

      </div>
    </div>
  );
}

// Per-trigger guard section (summary + open panel)
function TriggerConditionsSection({ draft, onChange, onOpenGuardPanel }: { draft: AutomationTriggerDraft; onChange: (d: AutomationTriggerDraft) => void; onOpenGuardPanel?: () => void }) {
  const registry = useDeviceRegistry();
  const api = useApi();

  // Load global value display names for condition summaries
  const [stateNames, setStateNames] = useState<StateDisplayNames>({});
  useEffect(() => {
    let cancelled = false;
    api.getStateVariables().then((vars: StateVariable[]) => {
      if (cancelled) return;
      const map: StateDisplayNames = {};
      for (const v of vars) map[v.name] = v.displayName || v.name;
      setStateNames(map);
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [api]);

  const hasConditions = draft.conditions && draft.conditions.length > 0 && draft.conditions[0];
  const root = hasConditions ? draft.conditions![0]! : null;

  const condCount = useMemo(() => {
    if (!root) return 0;
    function countLeaves(c: AutomationConditionDraft): number {
      if (c.type === 'and' || c.type === 'or') return (c.conditions ?? []).reduce((s, ch) => s + countLeaves(ch), 0);
      if (c.type === 'not') return c.condition ? countLeaves(c.condition) : 0;
      return 1;
    }
    return countLeaves(root);
  }, [root]);

  const addConditions = useCallback(() => {
    const emptyRoot: AutomationConditionDraft = { _draftId: newUUID(), type: 'and', conditions: [] };
    onChange({ ...draft, conditions: [emptyRoot] });
    requestAnimationFrame(() => onOpenGuardPanel?.());
  }, [draft, onChange, onOpenGuardPanel]);

  return (
    <div className="editor-field">
      <label>Trigger Guard</label>
      {!hasConditions ? (
        <button className="wfe-condition-add-btn" onClick={addConditions} type="button" style={{ marginTop: 4 }}>
          <Icon name="plus-circle" size={14} />
          Add Trigger Guard
        </button>
      ) : (
        <div
          className="trigger-guard-summary"
          onClick={() => onOpenGuardPanel?.()}
        >
          <Icon name="arrow-triangle-branch" size={14} style={{ opacity: 0.5 }} />
          <div className="trigger-guard-summary-info">
            <span className="trigger-guard-summary-name">{conditionAutoName(root!, registry, undefined, stateNames)}</span>
            <span className="trigger-guard-summary-meta">{condCount} condition{condCount !== 1 ? 's' : ''} — tap to edit</span>
          </div>
          <span className="child-badge logic">
            {root!.type === 'not' ? 'NOT' : root!.type.toUpperCase()}
          </span>
          <Icon name="chevron-right" size={12} style={{ color: 'var(--text-tertiary)', opacity: 0.3 }} />
        </div>
      )}
    </div>
  );
}
