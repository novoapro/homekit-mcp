import { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { useRegisterRefresh } from '@/contexts/RefreshContext';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { AIGenerateDialog } from '@/components/AIGenerateDialog';
import { WorkflowCard } from '@/features/workflows/WorkflowCard';
import { useApi } from '@/hooks/useApi';
import { useConfig } from '@/contexts/ConfigContext';
import { useWebSocket } from '@/contexts/WebSocketContext';
import type { Workflow } from '@/types/workflow-log';
import './WorkflowsPage.css';

export function WorkflowsPage() {
  const api = useApi();
  const ws = useWebSocket();
  const { config } = useConfig();
  const navigate = useNavigate();

  const [workflows, setWorkflows] = useState<Workflow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  useSetTopBar('Workflows', workflows.length > 0 ? workflows.length : null, isLoading);

  // Selection mode
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const loadWorkflows = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const wfs = await api.getWorkflows();
      setWorkflows(wfs);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load workflows');
    } finally {
      setIsLoading(false);
    }
  }, [api]);

  useRegisterRefresh(loadWorkflows);

  useEffect(() => {
    loadWorkflows();
  }, [loadWorkflows]);

  // WebSocket: real-time workflow list updates
  useEffect(() => {
    const unsub = ws.onWorkflowsUpdated((updated) => {
      setWorkflows(updated);
    });
    return unsub;
  }, [ws]);

  // Periodic polling — safety net regardless of WebSocket status
  useEffect(() => {
    const interval = config.pollingInterval;
    if (interval <= 0) return;

    const timer = setInterval(() => {
      if (document.visibilityState === 'visible') {
        loadWorkflows();
      }
    }, interval * 1000);

    return () => clearInterval(timer);
  }, [config.pollingInterval, loadWorkflows]);

  const filteredWorkflows = useMemo(() => {
    if (!searchQuery.trim()) return workflows;
    const q = searchQuery.toLowerCase();
    return workflows.filter((wf) => wf.name.toLowerCase().includes(q));
  }, [workflows, searchQuery]);

  const toggleWorkflow = useCallback(async (workflowId: string, enabled: boolean) => {
    // Optimistic update
    setWorkflows(prev => prev.map(w => w.id === workflowId ? { ...w, isEnabled: enabled } : w));

    try {
      const updated = await api.updateWorkflow(workflowId, { isEnabled: enabled });
      setWorkflows(prev => prev.map(w => w.id === updated.id ? updated : w));
    } catch {
      // Revert
      setWorkflows(prev => prev.map(w => w.id === workflowId ? { ...w, isEnabled: !enabled } : w));
      setError('Failed to update workflow');
    }
  }, [api]);

  const [deleteTarget, setDeleteTarget] = useState<Workflow | null>(null);
  const [showAIDialog, setShowAIDialog] = useState(false);

  const handleDelete = useCallback((workflowId: string) => {
    const wf = workflows.find(w => w.id === workflowId) ?? null;
    setDeleteTarget(wf);
  }, [workflows]);

  const handleClick = useCallback((workflowId: string) => {
    navigate(`/workflows/${workflowId}/definition`);
  }, [navigate]);

  // Bulk delete confirmation
  const [bulkDeletePending, setBulkDeletePending] = useState(false);

  const handleGenerate = useCallback(async (prompt: string, deviceIds?: string[], sceneIds?: string[]) => {
    return api.generateWorkflow(prompt, deviceIds, sceneIds);
  }, [api]);

  const handleViewWorkflow = useCallback((id: string) => {
    setShowAIDialog(false);
    navigate(`/workflows/${id}/definition`);
  }, [navigate]);

  const confirmDelete = useCallback(async () => {
    if (!deleteTarget) return;
    try {
      await api.deleteWorkflow(deleteTarget.id);
      setWorkflows(prev => prev.filter(w => w.id !== deleteTarget.id));
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to delete workflow');
    }
    setDeleteTarget(null);
  }, [api, deleteTarget]);

  // Selection mode handlers
  const enterSelectionMode = useCallback((workflowId: string) => {
    setSelectionMode(true);
    setSelectedIds(new Set([workflowId]));
  }, []);

  const toggleSelection = useCallback((workflowId: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(workflowId)) {
        next.delete(workflowId);
      } else {
        next.add(workflowId);
      }
      // Exit selection mode if nothing selected
      if (next.size === 0) {
        setSelectionMode(false);
      }
      return next;
    });
  }, []);

  const exitSelectionMode = useCallback(() => {
    setSelectionMode(false);
    setSelectedIds(new Set());
  }, []);

  const selectAll = useCallback(() => {
    setSelectedIds(new Set(filteredWorkflows.map(wf => wf.id)));
  }, [filteredWorkflows]);

  // Derive enable/disable counts from selection
  const selectedWorkflows = useMemo(() =>
    workflows.filter(w => selectedIds.has(w.id)),
    [workflows, selectedIds]
  );
  const enabledCount = useMemo(() => selectedWorkflows.filter(w => w.isEnabled).length, [selectedWorkflows]);
  const disabledCount = useMemo(() => selectedWorkflows.filter(w => !w.isEnabled).length, [selectedWorkflows]);

  // Bulk set enabled state — skips workflows already in the desired state
  const bulkSetEnabled = useCallback(async (enabled: boolean) => {
    const toUpdate = selectedWorkflows.filter(w => w.isEnabled !== enabled);
    if (toUpdate.length === 0) { exitSelectionMode(); return; }

    const ids = toUpdate.map(w => w.id);
    // Optimistic
    setWorkflows(prev => prev.map(w => ids.includes(w.id) ? { ...w, isEnabled: enabled } : w));

    try {
      await Promise.all(ids.map(id => api.updateWorkflow(id, { isEnabled: enabled })));
    } catch {
      setError(`Failed to ${enabled ? 'enable' : 'disable'} some workflows`);
      loadWorkflows();
    }
    exitSelectionMode();
  }, [selectedWorkflows, api, exitSelectionMode, loadWorkflows]);

  // Bulk delete
  const confirmBulkDelete = useCallback(async () => {
    const ids = Array.from(selectedIds);
    try {
      await Promise.all(ids.map(id => api.deleteWorkflow(id)));
      setWorkflows(prev => prev.filter(w => !ids.includes(w.id)));
    } catch {
      setError('Failed to delete some workflows');
      loadWorkflows();
    }
    setBulkDeletePending(false);
    exitSelectionMode();
  }, [selectedIds, api, exitSelectionMode, loadWorkflows]);

  const selectedCount = selectedIds.size;

  return (
    <div className="wf-list-page">
      {/* Desktop page header */}
      <div className="wf-page-header">
        <h1 className="wf-page-title">Workflows</h1>
        {isLoading && <span className="wf-loading-dot" />}

        {selectionMode ? (
          <div className="wf-selection-header">
            <span className="wf-selection-count">{selectedCount} selected</span>
            <button className="wf-selection-select-all" onClick={selectAll}>Select All</button>
            <button className="wf-selection-cancel" onClick={exitSelectionMode}>Cancel</button>
          </div>
        ) : (
          <>
            <div className="wf-search-wrap desktop">
              <Icon name="magnifying-glass" size={13} className="wf-search-icon" />
              <input
                className="wf-search-input"
                type="text"
                placeholder="Search workflows..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
              {searchQuery && (
                <button className="wf-search-clear" onClick={() => setSearchQuery('')} type="button">
                  <Icon name="xmark-circle-fill" size={14} />
                </button>
              )}
            </div>
            <button className="wf-ai-btn" onClick={() => setShowAIDialog(true)}>
              <Icon name="sparkles" size={15} />
              Generate with AI
            </button>
            <button className="wf-new-btn" onClick={() => navigate('/workflows/new')}>
              <Icon name="plus" size={15} />
              New Workflow
            </button>
          </>
        )}
      </div>

      {/* Mobile toolbar: search + icon CTAs */}
      <div className="wf-mobile-toolbar">
        {selectionMode ? (
          <>
            <span className="wf-selection-count">{selectedCount} selected</span>
            <button className="wf-selection-select-all" onClick={selectAll}>All</button>
            <button className="wf-selection-cancel" onClick={exitSelectionMode}>Cancel</button>
          </>
        ) : (
          <>
            <div className="wf-search-wrap">
              <Icon name="magnifying-glass" size={13} className="wf-search-icon" />
              <input
                className="wf-search-input"
                type="text"
                placeholder="Search workflows..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
              {searchQuery && (
                <button className="wf-search-clear" onClick={() => setSearchQuery('')} type="button">
                  <Icon name="xmark-circle-fill" size={14} />
                </button>
              )}
            </div>
            <button className="wf-toolbar-icon-btn ai" onClick={() => setShowAIDialog(true)} title="Generate with AI">
              <Icon name="sparkles" size={17} />
            </button>
            <button className="wf-toolbar-icon-btn primary" onClick={() => navigate('/workflows/new')} title="New Workflow">
              <Icon name="plus" size={17} />
            </button>
          </>
        )}
      </div>

      {/* Error */}
      {error && (
        <div className="wf-error-banner animate-fade-in">
          <Icon name="exclamation-triangle" size={16} />
          <span>{error}</span>
        </div>
      )}

      {/* Skeleton Loading */}
      {isLoading && workflows.length === 0 && (
        <div className="wf-skeleton-list">
          {Array.from({ length: 10 }, (_, i) => (
            <div key={i} className="wf-skeleton-card skeleton" style={{ animationDelay: `${i * 100}ms` }} />
          ))}
        </div>
      )}

      {/* Empty */}
      {!isLoading && workflows.length === 0 && !error && (
        <EmptyState
          icon="bolt-circle-fill"
          title="No workflows"
          message="No workflows yet. Tap New Workflow to create your first automation."
        />
      )}

      {/* Search no results */}
      {!isLoading && workflows.length > 0 && filteredWorkflows.length === 0 && searchQuery.trim() && (
        <EmptyState
          icon="magnifyingglass"
          title="No matches"
          message={`No workflows matching "${searchQuery}".`}
        />
      )}

      {/* Workflow card list */}
      {filteredWorkflows.length > 0 && (
        <div className={`wf-card-list${selectionMode ? ' with-bulk-bar' : ''}`}>
          {filteredWorkflows.map((wf, i) => (
            <WorkflowCard
              key={wf.id}
              workflow={wf}
              index={i}
              onToggleEnabled={toggleWorkflow}
              onDelete={handleDelete}
              onClick={handleClick}
              selectionMode={selectionMode}
              isSelected={selectedIds.has(wf.id)}
              onSelect={toggleSelection}
              onLongPress={enterSelectionMode}
            />
          ))}
        </div>
      )}

      {/* Bulk operations bar */}
      {selectionMode && selectedCount > 0 && (
        <div className="wf-bulk-bar">
          {disabledCount > 0 && (
            <button className="wf-bulk-btn enable" onClick={() => bulkSetEnabled(true)}>
              <Icon name="play-circle-fill" size={16} />
              <span>Enable ({disabledCount})</span>
            </button>
          )}
          {enabledCount > 0 && (
            <button className="wf-bulk-btn disable" onClick={() => bulkSetEnabled(false)}>
              <Icon name="stop-circle" size={16} />
              <span>Disable ({enabledCount})</span>
            </button>
          )}
          <button className="wf-bulk-btn delete" onClick={() => setBulkDeletePending(true)}>
            <Icon name="trash" size={16} />
            <span>Remove ({selectedCount})</span>
          </button>
        </div>
      )}

      <AIGenerateDialog
        open={showAIDialog}
        onClose={() => setShowAIDialog(false)}
        onGenerate={handleGenerate}
        onViewWorkflow={handleViewWorkflow}
      />

      <ConfirmDialog
        open={!!deleteTarget}
        title="Delete Workflow"
        message={`Delete "${deleteTarget?.name}"? This cannot be undone.`}
        confirmLabel="Delete"
        destructive
        onConfirm={confirmDelete}
        onCancel={() => setDeleteTarget(null)}
      />

      <ConfirmDialog
        open={bulkDeletePending}
        title="Delete Workflows"
        message={`Delete ${selectedCount} workflow${selectedCount !== 1 ? 's' : ''}? This cannot be undone.`}
        confirmLabel="Delete All"
        destructive
        onConfirm={confirmBulkDelete}
        onCancel={() => setBulkDeletePending(false)}
      />
    </div>
  );
}
