import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router';
import { Icon } from '@/components/Icon';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { DefinitionTrigger } from '@/features/workflows/DefinitionTrigger';
import { DefinitionCondition } from '@/features/workflows/DefinitionCondition';
import { DefinitionBlockTree } from '@/features/workflows/DefinitionBlockTree';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from '@/contexts/WebSocketContext';
import type { WorkflowDefinition } from '@/types/workflow-definition';
import './WorkflowDefinitionPage.css';

export function WorkflowDefinitionPage() {
  const { workflowId } = useParams<{ workflowId: string }>();
  const navigate = useNavigate();
  const api = useApi();
  const ws = useWebSocket();

  const [workflow, setWorkflow] = useState<WorkflowDefinition | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isDuplicating, setIsDuplicating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadWorkflow = useCallback(async () => {
    if (!workflowId) return;
    setIsLoading(true);
    setError(null);
    try {
      const wf = await api.getWorkflow(workflowId);
      setWorkflow(wf);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load workflow');
    } finally {
      setIsLoading(false);
    }
  }, [api, workflowId]);

  useEffect(() => {
    loadWorkflow();
  }, [loadWorkflow]);

  // Reload on WebSocket workflows_updated if this workflow changed
  useEffect(() => {
    const unsub = ws.onWorkflowsUpdated((workflows) => {
      if (workflows.some(w => w.id === workflowId)) {
        loadWorkflow();
      }
    });
    return unsub;
  }, [ws, workflowId, loadWorkflow]);

  const goBack = useCallback(() => {
    navigate('/workflows');
  }, [navigate]);

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const confirmDelete = useCallback(async () => {
    if (!workflow) return;
    try {
      await api.deleteWorkflow(workflow.id);
      navigate('/workflows');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to delete workflow');
    }
    setShowDeleteConfirm(false);
  }, [api, workflow, navigate]);

  const duplicateWorkflow = useCallback(async () => {
    if (!workflow) return;
    setIsDuplicating(true);
    try {
      const created = await api.createWorkflow({
        name: `${workflow.name} (Copy)`,
        description: workflow.description,
        isEnabled: false,
        continueOnError: workflow.continueOnError,
        retriggerPolicy: workflow.retriggerPolicy,
        triggers: workflow.triggers,
        conditions: workflow.conditions,
        blocks: workflow.blocks,
      });
      navigate(`/workflows/${created.id}/edit`);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to duplicate workflow');
    } finally {
      setIsDuplicating(false);
    }
  }, [api, workflow, navigate]);

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleString(undefined, {
      month: 'short', day: 'numeric', year: '2-digit',
      hour: '2-digit', minute: '2-digit',
    });
  }

  return (
    <div className="wfd-page">
      <button className="wfd-back-btn" onClick={goBack}>
        <span style={{ transform: 'rotate(90deg)', display: 'inline-flex' }}>
          <Icon name="chevron-down" size={14} />
        </span>
        <span>Back to Workflows</span>
      </button>

      {isLoading && (
        <div className="wfd-loading">
          <Icon name="spinner" size={24} className="animate-spin" />
          <span>Loading...</span>
        </div>
      )}

      {error && (
        <div className="wfd-error-banner animate-fade-in">
          <Icon name="exclamation-triangle" size={16} />
          <span>{error}</span>
        </div>
      )}

      {workflow && (
        <>
          {/* Header Section */}
          <div className="wfd-section wfd-header-section animate-fade-in">
            <div className="wfd-header-row">
              <div className="wfd-header-info">
                <div className="wfd-name-row">
                  {workflow.isEnabled ? (
                    <span className="wfd-status-badge wfd-enabled">Enabled</span>
                  ) : (
                    <span className="wfd-status-badge wfd-disabled">Disabled</span>
                  )}
                  <h2 className="wfd-workflow-name">{workflow.name}</h2>
                </div>
                {workflow.description && (
                  <p className="wfd-description">{workflow.description}</p>
                )}
              </div>
              <div className="wfd-header-actions">
                <button className="wfd-icon-btn" onClick={() => navigate(`/workflows/${workflowId}/edit`)} title="Edit">
                  <Icon name="pencil" size={16} />
                </button>
                <button className="wfd-icon-btn" onClick={duplicateWorkflow} disabled={isDuplicating} title="Duplicate">
                  <Icon name="copy" size={16} />
                </button>
                <button className="wfd-icon-btn wfd-danger" onClick={() => setShowDeleteConfirm(true)} title="Delete">
                  <Icon name="trash" size={16} />
                </button>
              </div>
            </div>
          </div>

          {/* Metadata Chips */}
          <div className="wfd-meta-chips animate-fade-in">
            <span className="wfd-chip wfd-chip-executions">
              <Icon name="play-circle-fill" size={13} />
              <span className="wfd-chip-label">Executions</span>
              <span className="wfd-chip-value">{workflow.metadata.totalExecutions}</span>
            </span>
            {workflow.metadata.lastTriggeredAt && (
              <span className="wfd-chip wfd-chip-triggered">
                <Icon name="clock" size={13} />
                <span className="wfd-chip-label">Last triggered</span>
                <span className="wfd-chip-value">{formatDate(workflow.metadata.lastTriggeredAt)}</span>
              </span>
            )}
            <span className={`wfd-chip wfd-chip-failures ${workflow.metadata.consecutiveFailures > 0 ? 'wfd-chip-failures-active' : ''}`}>
              <Icon name="exclamation-circle-fill" size={13} />
              <span className="wfd-chip-label">Consecutive failures</span>
              <span className="wfd-chip-value">{workflow.metadata.consecutiveFailures}</span>
            </span>
            <span className="wfd-chip wfd-chip-updated">
              <Icon name="refresh-circle-fill" size={13} />
              <span className="wfd-chip-label">Updated</span>
              <span className="wfd-chip-value">{formatDate(workflow.updatedAt)}</span>
            </span>
            <span className={`wfd-chip wfd-chip-error-policy ${workflow.continueOnError ? 'wfd-chip-yes' : ''}`}>
              <Icon name="forward-circle-fill" size={13} />
              <span className="wfd-chip-label">Continue on error</span>
              <span className="wfd-chip-value">{workflow.continueOnError ? 'Yes' : 'No'}</span>
            </span>
            {workflow.metadata.tags?.map((tag, i) => (
              <span key={i} className="wfd-chip wfd-chip-tag">
                <Icon name="funnel" size={13} />
                <span className="wfd-chip-value">{tag}</span>
              </span>
            ))}
          </div>

          {/* Triggers Section */}
          <div className="wfd-section animate-fade-in">
            <h3 className="wfd-section-title">
              Triggers <span className="wfd-count">({workflow.triggers.length})</span>
            </h3>
            <div className="wfd-tree-content">
              {workflow.triggers.map((trigger, i) => (
                <DefinitionTrigger key={i} trigger={trigger} depth={0} />
              ))}
            </div>
          </div>

          {/* Guard Conditions Section */}
          {workflow.conditions && workflow.conditions.length > 0 && (
            <div className="wfd-section animate-fade-in">
              <h3 className="wfd-section-title">Guard Conditions</h3>
              <div className="wfd-tree-content">
                {workflow.conditions.map((condition, i) => (
                  <DefinitionCondition key={i} condition={condition} depth={0} />
                ))}
              </div>
            </div>
          )}

          {/* Blocks Section */}
          <div className="wfd-section animate-fade-in">
            <h3 className="wfd-section-title">
              Blocks <span className="wfd-count">({workflow.blocks.length})</span>
            </h3>
            <div className="wfd-tree-content">
              {workflow.blocks.map((block, i) => (
                <DefinitionBlockTree key={block.blockId} block={block} depth={0} index={i} />
              ))}
            </div>
          </div>

          {/* Execution Logs Button */}
          <button className="wfd-exec-logs-btn" onClick={() => navigate(`/workflows/${workflowId}`)}>
            <span>View Execution Logs</span>
            <Icon name="chevron-right" size={16} />
          </button>
        </>
      )}

      <ConfirmDialog
        open={showDeleteConfirm}
        title="Delete Workflow"
        message={`Delete "${workflow?.name}"? This cannot be undone.`}
        confirmLabel="Delete"
        destructive
        onConfirm={confirmDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />
    </div>
  );
}
