import { useMemo, useCallback } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import type { WorkflowTriggerDraft } from './workflow-editor-types';
import { triggerAutoName } from './workflow-editor-utils';
import './TriggerEditor.css';

const TRIGGER_TYPES = [
  { value: 'deviceStateChange', label: 'Device State Change' },
  { value: 'schedule', label: 'Schedule' },
  { value: 'sunEvent', label: 'Sun Event' },
  { value: 'webhook', label: 'Webhook' },
  { value: 'workflow', label: 'Callable (by other workflows)' },
];

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
  index: number;
  draft: WorkflowTriggerDraft;
  onChange: (updated: WorkflowTriggerDraft) => void;
  onRemove: () => void;
}

export function TriggerEditor({ index, draft, onChange, onRemove }: TriggerEditorProps) {
  const registry = useDeviceRegistry();

  const autoDescription = useMemo(
    () => draft.name || triggerAutoName(draft, registry),
    [draft, registry],
  );

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conditionType = (draft.condition as any)?.type ?? 'changed';
  const patch = useCallback(
    (changes: Partial<WorkflowTriggerDraft>) => onChange({ ...draft, ...changes }),
    [draft, onChange],
  );

  const onTypeChange = useCallback(
    (type: string) => {
      const base: WorkflowTriggerDraft = {
        _draftId: draft._draftId,
        type: type as WorkflowTriggerDraft['type'],
      };
      if (type === 'schedule') base.scheduleType = 'daily';
      if (type === 'sunEvent') { base.event = 'sunrise'; base.offsetMinutes = 0; }
      onChange(base);
    },
    [draft._draftId, onChange],
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
      <div className="trigger-header">
        <span className="trigger-index">Trigger {index + 1}</span>
        <span className="trigger-auto-name">{autoDescription}</span>
        <button className="trigger-remove-btn" onClick={onRemove} title="Remove trigger" type="button">
          <Icon name="xmark-circle-fill" size={16} />
        </button>
      </div>

      {/* Type selector */}
      <div className="editor-field">
        <label>Type</label>
        <select className="editor-select" value={draft.type} onChange={(e) => onTypeChange(e.target.value)}>
          {TRIGGER_TYPES.map((t) => (
            <option key={t.value} value={t.value}>{t.label}</option>
          ))}
        </select>
      </div>

      {/* deviceStateChange */}
      {draft.type === 'deviceStateChange' && (
        <>
          <DevicePicker
            initialDeviceId={draft.deviceId}
            initialServiceId={draft.serviceId}
            initialCharId={draft.characteristicId}
            onChange={(val) => patch({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId })}
          />
          <div className="editor-field">
            <label>Condition</label>
            <select
              className="editor-select"
              value={conditionType}
              onChange={(e) => {
                const type = e.target.value;
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                let condition: any = { type };
                if (type !== 'changed') condition.value = true;
                if (type === 'transitioned') { delete condition.value; condition.from = undefined; condition.to = true; }
                patch({ condition });
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
              value={(draft.condition as any)?.value}
              onChange={(val) => {
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                const current = { ...(draft.condition ?? { type: 'equals' }) } as any;
                current.value = val;
                patch({ condition: current });
              }}
            />
          )}
          {conditionType === 'transitioned' && (
            <div className="editor-field-row">
              <CharacteristicValueInput
                characteristic={draft.deviceId && draft.characteristicId
                  ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
                  : undefined}
                value={(draft.condition as any)?.from}
                label="From"
                allowAny
                onChange={(val) => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const current = { ...(draft.condition ?? { type: 'transitioned' }) } as any;
                  current.from = val;
                  patch({ condition: current });
                }}
              />
              <CharacteristicValueInput
                characteristic={draft.deviceId && draft.characteristicId
                  ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
                  : undefined}
                value={(draft.condition as any)?.to}
                label="To"
                onChange={(val) => {
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const current = { ...(draft.condition ?? { type: 'transitioned' }) } as any;
                  current.to = val;
                  patch({ condition: current });
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
              onChange={(e) => patch({
                scheduleType: e.target.value,
                scheduleDays: e.target.value === 'weekly' ? [1, 2, 3, 4, 5] : undefined,
              })}
            >
              {SCHEDULE_TYPES.map((s) => (
                <option key={s.value} value={s.value}>{s.label}</option>
              ))}
            </select>
          </div>

          {(draft.scheduleType || 'daily') === 'once' && (
            <div className="editor-field">
              <label>Date</label>
              <input
                className="editor-input"
                type="date"
                value={draft.scheduleDate || ''}
                onChange={(e) => patch({ scheduleDate: e.target.value })}
              />
            </div>
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
        </div>
      )}

      {/* workflow */}
      {draft.type === 'workflow' && (
        <div className="trigger-info-box">
          This workflow can be triggered by other workflows using the Execute Workflow block.
        </div>
      )}

      {/* Retrigger policy */}
      {(draft.type === 'deviceStateChange' || draft.type === 'sunEvent') && (
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
    </div>
  );
}
