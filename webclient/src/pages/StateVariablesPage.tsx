import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useNavigate } from 'react-router';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { useRegisterRefresh } from '@/contexts/RefreshContext';
import { useApi } from '@/hooks/useApi';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { stateLabel } from '@/lib/api';
import type { StateVariable } from '@/lib/api';
import type { Automation } from '@/types/automation-log';
import './StateVariablesPage.css';

/** Scan an automation definition (as raw JSON) for references to a state variable name. */
function automationReferencesState(automation: Automation, stateName: string): boolean {
  // Deep scan the raw JSON for variableRef.name matches and operation.name matches
  const json = JSON.stringify(automation);
  // Check for byName references: {"type":"byName","name":"<stateName>"}
  if (json.includes(`"byName","name":"${stateName}"`) || json.includes(`"byName", "name": "${stateName}"`)) return true;
  // Check for create operation with matching name
  if (json.includes(`"operation":"create"`) && json.includes(`"name":"${stateName}"`)) return true;
  return false;
}

const TYPE_ICONS: Record<string, string> = {
  number: 'number',
  string: 'textformat',
  boolean: 'switch-2',
};

function sanitizeName(input: string): string {
  return input.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '').replace(/_+/g, '_');
}

function getNameError(name: string): string | null {
  if (!name) return null;
  if (name !== name.toLowerCase()) return 'Must be lowercase';
  if (/\s/.test(name)) return 'Cannot contain spaces';
  if (!/^[a-z0-9_]+$/.test(name)) return 'Only letters, numbers, underscores';
  return null;
}

export function StateVariablesPage() {
  const api = useApi();
  const navigate = useNavigate();
  const [variables, setVariables] = useState<StateVariable[]>([]);
  const [automations, setAutomations] = useState<Automation[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<StateVariable | null>(null);

  // Edit state
  const [editNumberValue, setEditNumberValue] = useState(0);
  const [editStringValue, setEditStringValue] = useState('');
  const [editBoolValue, setEditBoolValue] = useState(false);

  useSetTopBar('Controller States', variables.length > 0 ? variables.length : null, isLoading);

  const loadVariables = useCallback(async () => {
    try {
      setIsLoading(true);
      const [vars, wfs] = await Promise.all([api.getStateVariables(), api.getAutomations().catch(() => [] as Automation[])]);
      setVariables(vars);
      setAutomations(wfs);
    } catch { /* ignore */ } finally {
      setIsLoading(false);
    }
  }, [api]);

  /** Get automations that reference a given state name */
  const referencingAutomations = useCallback((stateName: string) => {
    return automations.filter(a => automationReferencesState(a, stateName));
  }, [automations]);

  useEffect(() => { loadVariables(); }, [loadVariables]);
  useRegisterRefresh(loadVariables);

  const startEdit = (v: StateVariable) => {
    setEditingId(v.id);
    switch (v.type) {
      case 'number': setEditNumberValue(typeof v.value === 'number' ? v.value : 0); break;
      case 'boolean': setEditBoolValue(!!v.value); break;
      default: setEditStringValue(String(v.value ?? '')); break;
    }
  };

  const handleUpdate = async (v: StateVariable) => {
    let value: unknown;
    switch (v.type) {
      case 'number': value = editNumberValue; break;
      case 'boolean': value = editBoolValue; break;
      default: value = editStringValue;
    }
    await api.updateStateVariable(v.id, value);
    setEditingId(null);
    await loadVariables();
  };

  const handleDelete = (v: StateVariable) => {
    setDeleteTarget(v);
  };

  const confirmDelete = async () => {
    if (!deleteTarget) return;
    await api.deleteStateVariable(deleteTarget.id);
    setDeleteTarget(null);
    await loadVariables();
  };

  const deleteTargetRefs = useMemo(() => {
    if (!deleteTarget) return [];
    return referencingAutomations(deleteTarget.name);
  }, [deleteTarget, referencingAutomations]);

  const displayValue = (v: StateVariable) => {
    if (v.type === 'boolean') return v.value ? 'true' : 'false';
    return String(v.value ?? '');
  };

  return (
    <div className="sv-page">
      {/* Header */}
      <div className="sv-page-header">
        <button className="sv-back-btn" onClick={() => navigate('/automations')} title="Back to Automations">
          <Icon name="chevron-left" size={18} />
        </button>
        <h1 className="sv-page-title">Controller States</h1>
        {isLoading && <span className="wf-loading-dot" />}
        <button className="sv-new-btn" onClick={() => setShowCreateDialog(true)} type="button">
          <Icon name="plus" size={15} />
          New State
        </button>
      </div>

      {/* Card area */}
      <div className="sv-card-area">
        {/* Empty state */}
        {!isLoading && variables.length === 0 && (
          <EmptyState
            icon="state-variable"
            title="No controller states"
            message="Controller states store persistent data that automations can read and modify across executions. Tap New State to create one."
          />
        )}

        {/* Grid of state cards */}
        {variables.length > 0 && (
          <div className="sv-grid">
            {variables.map((v) => {
              const refs = referencingAutomations(v.name);
              return (
              <div key={v.id} className="sv-card">
                <div className="sv-card-header">
                  <div className="sv-card-icon">
                    <Icon name={TYPE_ICONS[v.type] || 'tag'} size={16} />
                  </div>
                  <div className="sv-card-meta">
                    <span className="sv-card-label">{stateLabel(v)}</span>
                    <span className="sv-card-name">{v.name}</span>
                  </div>
                  <div className="sv-card-actions">
                    <button className="sv-icon-btn sv-icon-btn-danger" onClick={() => handleDelete(v)} title="Delete" type="button">
                      <Icon name="trash" size={13} />
                    </button>
                  </div>
                </div>

                <div className="sv-card-body">
                  {editingId === v.id ? (
                    <div className="sv-card-edit">
                      {v.type === 'number' && (
                        <input className="sv-input sv-card-input" type="number" step="any" value={editNumberValue}
                          onChange={(e) => setEditNumberValue(parseFloat(e.target.value) || 0)}
                          onKeyDown={(e) => e.key === 'Enter' && handleUpdate(v)} autoFocus />
                      )}
                      {v.type === 'string' && (
                        <input className="sv-input sv-card-input" value={editStringValue}
                          onChange={(e) => setEditStringValue(e.target.value)}
                          onKeyDown={(e) => e.key === 'Enter' && handleUpdate(v)} autoFocus />
                      )}
                      {v.type === 'boolean' && (
                        <label className="sv-toggle-row" onClick={() => setEditBoolValue(!editBoolValue)}>
                          <button type="button" className={`sv-switch${editBoolValue ? ' on' : ''}`} onClick={(e) => { e.stopPropagation(); setEditBoolValue(!editBoolValue); }} />
                          <span className="sv-toggle-label">{editBoolValue ? 'true' : 'false'}</span>
                        </label>
                      )}
                      <div className="sv-card-edit-actions">
                        <button className="sv-btn sv-btn-sm" onClick={() => setEditingId(null)} type="button">Cancel</button>
                        <button className="sv-btn sv-btn-primary sv-btn-sm" onClick={() => handleUpdate(v)} type="button">Save</button>
                      </div>
                    </div>
                  ) : (
                    <div className="sv-card-value-row" onClick={() => startEdit(v)} title="Click to edit value">
                      <span className="sv-card-value">{displayValue(v)}</span>
                      <Icon name="pencil" size={12} className="sv-card-edit-hint" />
                    </div>
                  )}
                </div>

                {refs.length > 0 && (
                  <div className="sv-card-refs">
                    <Icon name="bolt" size={11} />
                    <span>Used in {refs.length} automation{refs.length !== 1 ? 's' : ''}</span>
                  </div>
                )}
              </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Delete confirmation */}
      <ConfirmDialog
        open={!!deleteTarget}
        title="Delete Controller State"
        message={deleteTargetRefs.length > 0
          ? `"${deleteTarget?.displayName || deleteTarget?.name}" is used in ${deleteTargetRefs.length} automation${deleteTargetRefs.length !== 1 ? 's' : ''}: ${deleteTargetRefs.map(a => a.name).join(', ')}. Those automations may fail after deletion.`
          : `Delete "${deleteTarget?.displayName || deleteTarget?.name}"? This cannot be undone.`
        }
        confirmLabel="Delete"
        destructive
        onConfirm={confirmDelete}
        onCancel={() => setDeleteTarget(null)}
      />

      {/* Create dialog */}
      {showCreateDialog && (
        <CreateStateDialog
          onClose={() => setShowCreateDialog(false)}
          onCreate={async (name, displayName, type, value) => {
            await api.createStateVariable({ name, displayName: displayName || undefined, type, value });
            setShowCreateDialog(false);
            await loadVariables();
          }}
        />
      )}
    </div>
  );
}

// MARK: - Create State Dialog

interface CreateStateDialogProps {
  onClose: () => void;
  onCreate: (name: string, displayName: string, type: string, value: unknown) => Promise<void>;
}

function CreateStateDialog({ onClose, onCreate }: CreateStateDialogProps) {
  const [name, setName] = useState('');
  const [newDisplayName, setNewDisplayName] = useState('');
  const [type, setType] = useState<'number' | 'string' | 'boolean'>('number');
  const [numberValue, setNumberValue] = useState(0);
  const [stringValue, setStringValue] = useState('');
  const [boolValue, setBoolValue] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const t = setTimeout(() => inputRef.current?.focus(), 100);
    return () => clearTimeout(t);
  }, []);

  const error = getNameError(name);
  const canCreate = name.trim().length > 0 && !error && !isCreating;

  const handleSubmit = async () => {
    if (!canCreate) return;
    setIsCreating(true);
    let value: unknown;
    switch (type) {
      case 'number': value = numberValue; break;
      case 'boolean': value = boolValue; break;
      default: value = stringValue;
    }
    await onCreate(name.trim(), newDisplayName.trim(), type, value);
  };

  return (
    <div className="sv-dialog-overlay" onClick={onClose} role="dialog" aria-modal="true">
      <div className="sv-dialog" onClick={(e) => e.stopPropagation()}>
        <div className="sv-dialog-icon-wrap">
          <Icon name="state-variable" size={24} />
        </div>
        <h3 className="sv-dialog-title">New Controller State</h3>
        <p className="sv-dialog-desc">Create a persistent state that automations can read and modify.</p>

        <div className="sv-dialog-fields">
          <div className="sv-dialog-field">
            <label className="sv-dialog-label">Identifier</label>
            <input
              ref={inputRef}
              className="sv-input mono"
              placeholder="my_counter"
              value={name}
              onChange={(e) => setName(sanitizeName(e.target.value))}
              onKeyDown={(e) => e.key === 'Enter' && handleSubmit()}
            />
            {error
              ? <span className="sv-dialog-error">{error}</span>
              : name
                ? <span className="sv-dialog-hint">Looks good</span>
                : <span className="sv-dialog-hint">Lowercase letters, numbers, underscores only</span>
            }
          </div>

          <div className="sv-dialog-field">
            <label className="sv-dialog-label">Display Name</label>
            <input
              className="sv-input"
              placeholder="e.g. Living Room Counter"
              value={newDisplayName}
              onChange={(e) => setNewDisplayName(e.target.value)}
            />
            <span className="sv-dialog-hint">Human-readable name shown in the UI</span>
          </div>

          <div className="sv-dialog-field">
            <label className="sv-dialog-label">Type</label>
            <div className="sv-type-selector">
              {(['number', 'string', 'boolean'] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  className={`sv-type-option${type === t ? ' active' : ''}`}
                  onClick={() => setType(t)}
                >
                  <Icon name={TYPE_ICONS[t] || 'tag'} size={16} />
                  <span>{t.charAt(0).toUpperCase() + t.slice(1)}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="sv-dialog-field">
            <label className="sv-dialog-label">Initial Value</label>
            {type === 'number' && (
              <input className="sv-input" type="number" step="any" value={numberValue}
                onChange={(e) => setNumberValue(parseFloat(e.target.value) || 0)}
                onKeyDown={(e) => e.key === 'Enter' && handleSubmit()} />
            )}
            {type === 'string' && (
              <input className="sv-input" value={stringValue}
                onChange={(e) => setStringValue(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleSubmit()}
                placeholder="Enter text..." />
            )}
            {type === 'boolean' && (
              <div className="sv-bool-selector">
                <button type="button" className={`sv-bool-option${boolValue ? ' active' : ''}`} onClick={() => setBoolValue(true)}>
                  true
                </button>
                <button type="button" className={`sv-bool-option${!boolValue ? ' active' : ''}`} onClick={() => setBoolValue(false)}>
                  false
                </button>
              </div>
            )}
          </div>
        </div>

        <div className="sv-dialog-actions">
          <button type="button" className="sv-dialog-btn cancel" onClick={onClose}>Cancel</button>
          <button type="button" className={`sv-dialog-btn confirm${isCreating ? ' loading' : ''}`} onClick={handleSubmit} disabled={!canCreate}>
            {isCreating ? 'Creating...' : 'Create'}
          </button>
        </div>
      </div>
    </div>
  );
}
