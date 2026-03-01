import { useCallback, useMemo } from 'react';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import type { WorkflowConditionDraft } from './workflow-editor-types';
import { newConditionLeaf } from './workflow-editor-utils';
import type { BlockInfo } from './workflow-editor-utils';
import './TriggerEditor.css'; // reuse shared form styles

const CONDITION_LEAF_TYPES = [
  { value: 'deviceState', label: 'Device State' },
  { value: 'timeCondition', label: 'Time Window' },
  { value: 'sceneActive', label: 'Scene Active' },
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
  { value: 'between', label: 'Between two times' },
  { value: 'before', label: 'Before a time' },
  { value: 'after', label: 'After a time' },
  { value: 'daytime', label: 'Daytime (sunrise-sunset)' },
  { value: 'nighttime', label: 'Nighttime (sunset-sunrise)' },
];

interface ConditionEditorProps {
  draft: WorkflowConditionDraft;
  allowBlockResult?: boolean;
  allBlocks?: BlockInfo[];
  currentBlockDraftId?: string;
  continueOnError?: boolean;
  onChange: (updated: WorkflowConditionDraft) => void;
}

export function ConditionEditor({ draft, allowBlockResult = true, allBlocks, currentBlockDraftId, continueOnError, onChange }: ConditionEditorProps) {
  const registry = useDeviceRegistry();

  const currentOrdinal = useMemo(
    () => allBlocks?.find((b) => b._draftId === currentBlockDraftId)?.ordinal,
    [allBlocks, currentBlockDraftId],
  );

  const precedingBlocks = useMemo(() => {
    if (!allBlocks || currentOrdinal === undefined) return [];
    return allBlocks.filter((b) => b.ordinal < currentOrdinal);
  }, [allBlocks, currentOrdinal]);

  const leafTypes = useMemo(() => {
    const isFirstBlock = currentOrdinal === 1;
    const shouldHideBlockResult = !allowBlockResult || !continueOnError || isFirstBlock || precedingBlocks.length === 0;
    return shouldHideBlockResult
      ? CONDITION_LEAF_TYPES.filter((t) => t.value !== 'blockResult')
      : CONDITION_LEAF_TYPES;
  }, [allowBlockResult, continueOnError, currentOrdinal, precedingBlocks.length]);

  const patch = useCallback(
    (changes: Partial<WorkflowConditionDraft>) => onChange({ ...draft, ...changes }),
    [draft, onChange],
  );

  const timeStr = (t: { hour: number; minute: number } | undefined): string => {
    if (!t) return '08:00';
    return `${String(t.hour).padStart(2, '0')}:${String(t.minute).padStart(2, '0')}`;
  };

  return (
    <div className="trigger-editor">
      {/* Type selector */}
      <div className="editor-field">
        <label>Condition Type</label>
        <select
          className="editor-select"
          value={draft.type}
          onChange={(e) => onChange(newConditionLeaf(e.target.value))}
        >
          {leafTypes.map((t) => (
            <option key={t.value} value={t.value}>{t.label}</option>
          ))}
        </select>
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
            <select className="editor-select" value={draft.mode || 'between'} onChange={(e) => patch({ mode: e.target.value })}>
              {TIME_MODES.map((m) => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
          </div>
          {(draft.mode === 'between' || draft.mode === 'after') && (
            <div className="editor-field">
              <label>Start Time</label>
              <input
                className="editor-input"
                type="time"
                value={timeStr(draft.startTime)}
                onChange={(e) => {
                  const [h, m] = e.target.value.split(':');
                  patch({ startTime: { hour: +h!, minute: +m! } });
                }}
              />
            </div>
          )}
          {(draft.mode === 'between' || draft.mode === 'before') && (
            <div className="editor-field">
              <label>End Time</label>
              <input
                className="editor-input"
                type="time"
                value={timeStr(draft.endTime)}
                onChange={(e) => {
                  const [h, m] = e.target.value.split(':');
                  patch({ endTime: { hour: +h!, minute: +m! } });
                }}
              />
            </div>
          )}
        </>
      )}

      {/* sceneActive */}
      {draft.type === 'sceneActive' && (
        <>
          <div className="editor-field">
            <label>Scene</label>
            <select className="editor-select" value={draft.sceneId || ''} onChange={(e) => patch({ sceneId: e.target.value })}>
              <option value="">-- Select scene --</option>
              {registry.scenes.map((scene) => (
                <option key={scene.id} value={scene.id}>{scene.name}</option>
              ))}
            </select>
          </div>
          <div className="editor-field">
            <label>State</label>
            <select className="editor-select" value={draft.isActive !== false ? 'true' : 'false'} onChange={(e) => patch({ isActive: e.target.value === 'true' })}>
              <option value="true">Is Active</option>
              <option value="false">Is Not Active</option>
            </select>
          </div>
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
