import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { WorkflowCard } from '@/features/workflows/WorkflowCard';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from '@/contexts/WebSocketContext';
import type { Workflow } from '@/types/workflow-log';
import './WorkflowsPage.css';

export function WorkflowsPage() {
  const api = useApi();
  const ws = useWebSocket();
  const navigate = useNavigate();

  const [workflows, setWorkflows] = useState<Workflow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

  const toggleWorkflow = useCallback(async (workflow: Workflow, enabled: boolean) => {
    // Optimistic update
    setWorkflows(prev => prev.map(w => w.id === workflow.id ? { ...w, isEnabled: enabled } : w));

    try {
      const updated = await api.updateWorkflow(workflow.id, { isEnabled: enabled });
      setWorkflows(prev => prev.map(w => w.id === updated.id ? updated : w));
    } catch {
      // Revert
      setWorkflows(prev => prev.map(w => w.id === workflow.id ? { ...w, isEnabled: !enabled } : w));
      setError('Failed to update workflow');
    }
  }, [api]);

  const [deleteTarget, setDeleteTarget] = useState<Workflow | null>(null);

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

  return (
    <div className="wf-list-page">
      {/* Page header */}
      <div className="wf-page-header">
        <h1 className="wf-page-title">Workflows</h1>
        {isLoading && <span className="wf-loading-dot" />}
        <button className="wf-new-btn" onClick={() => navigate('/workflows/new')}>
          <Icon name="plus" size={15} />
          New Workflow
        </button>
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

      {/* Workflow card list */}
      {workflows.length > 0 && (
        <div className="wf-card-list">
          {workflows.map((wf, i) => (
            <WorkflowCard
              key={wf.id}
              workflow={wf}
              index={i}
              onToggleEnabled={(enabled) => toggleWorkflow(wf, enabled)}
              onDelete={() => setDeleteTarget(wf)}
              onClick={() => navigate(`/workflows/${wf.id}/definition`)}
            />
          ))}
        </div>
      )}

      {/* Mobile FAB */}
      <button className="wf-fab" onClick={() => navigate('/workflows/new')}>
        <Icon name="plus" size={18} />
      </button>

      <ConfirmDialog
        open={!!deleteTarget}
        title="Delete Workflow"
        message={`Delete "${deleteTarget?.name}"? This cannot be undone.`}
        confirmLabel="Delete"
        destructive
        onConfirm={confirmDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  );
}
