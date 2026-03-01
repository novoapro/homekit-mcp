import { useCallback, useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { DevicePicker } from './DevicePicker';
import { CharacteristicValueInput } from './CharacteristicValueInput';
import type { WorkflowBlockDraft } from './workflow-editor-types';
import { blockAutoName, conditionAutoName } from './workflow-editor-utils';
import { HTTP_METHODS, OUTCOMES, EXEC_MODES } from './block-helpers';
import './BlockEditor.css';
import './TriggerEditor.css'; // shared form styles

interface BlockEditorProps {
  draft: WorkflowBlockDraft;
  showHeader?: boolean;
  onChange: (updated: WorkflowBlockDraft) => void;
  onNavigateToNested?: (info: { field: string; label: string }) => void;
}

export function BlockEditor({
  draft,
  showHeader = true,
  onChange,
  onNavigateToNested,
}: BlockEditorProps) {
  const registry = useDeviceRegistry();

  const autoDescription = useMemo(
    () => draft.name || blockAutoName(draft, registry),
    [draft, registry],
  );

  const patch = useCallback(
    (changes: Partial<WorkflowBlockDraft>) => onChange({ ...draft, ...changes }),
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
          <CharacteristicValueInput
            characteristic={draft.deviceId && draft.characteristicId
              ? registry.lookupCharacteristic(draft.deviceId, draft.characteristicId)
              : undefined}
            value={draft.value}
            onChange={(val) => patch({ value: val })}
          />
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

      {/* delay */}
      {draft.type === 'delay' && (
        <div className="editor-field">
          <label>Duration (seconds)</label>
          <input
            className="editor-input"
            type="number"
            min={0}
            step={0.1}
            value={draft.seconds ?? 1}
            onChange={(e) => patch({ seconds: +e.target.value })}
          />
        </div>
      )}

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

      {/* stop */}
      {draft.type === 'stop' && (
        <div className="editor-field">
          <label>Outcome</label>
          <select className="editor-select" value={draft.outcome || 'success'} onChange={(e) => patch({ outcome: e.target.value })}>
            {OUTCOMES.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
      )}

      {/* executeWorkflow */}
      {draft.type === 'executeWorkflow' && (
        <>
          <div className="editor-field">
            <label>Target Workflow ID</label>
            <input className="editor-input" value={draft.targetWorkflowId || ''} onChange={(e) => patch({ targetWorkflowId: e.target.value })} placeholder="Workflow UUID" />
          </div>
          <div className="editor-field">
            <label>Execution Mode</label>
            <select className="editor-select" value={draft.executionMode || 'async'} onChange={(e) => patch({ executionMode: e.target.value })}>
              {EXEC_MODES.map((m) => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
          </div>
        </>
      )}
    </div>
  );
}
