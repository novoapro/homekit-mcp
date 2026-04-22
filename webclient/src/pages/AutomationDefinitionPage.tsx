import { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, useNavigate } from 'react-router';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { Icon } from '@/components/Icon';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { AIImproveDialog } from '@/components/AIImproveDialog';
import { DefinitionTrigger } from '@/features/automations/DefinitionTrigger';
import { DefinitionCondition } from '@/features/automations/DefinitionCondition';
import { DefinitionBlockTree } from '@/features/automations/DefinitionBlockTree';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from '@/contexts/WebSocketContext';
import type { AutomationDefinition } from '@/types/automation-definition';
import './AutomationDefinitionPage.css';

export function AutomationDefinitionPage() {
  const { automationId } = useParams<{ automationId: string }>();
  const navigate = useNavigate();
  const api = useApi();
  const ws = useWebSocket();

  const [automation, setAutomation] = useState<AutomationDefinition | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  useSetTopBar(automation?.name ?? 'Automation', null, isLoading);
  const [isDuplicating, setIsDuplicating] = useState(false);
  const [isTriggering, setIsTriggering] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadAutomation = useCallback(async () => {
    if (!automationId) return;
    setIsLoading(true);
    setError(null);
    try {
      const wf = await api.getAutomation(automationId);
      setAutomation(wf);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load automation');
    } finally {
      setIsLoading(false);
    }
  }, [api, automationId]);

  useEffect(() => {
    loadAutomation();
  }, [loadAutomation]);

  // Reload on WebSocket automations_updated if this automation changed.
  // Use a ref so the effect doesn't re-run (and re-fetch) when loadAutomation changes.
  const loadRef = useRef(loadAutomation);
  loadRef.current = loadAutomation;

  useEffect(() => {
    const unsub = ws.onAutomationsUpdated((automations) => {
      if (automations.some(w => w.id === automationId)) {
        loadRef.current();
      }
    });
    return unsub;
  }, [ws, automationId]);

  const goBack = useCallback(() => {
    navigate('/automations');
  }, [navigate]);

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [showImproveDialog, setShowImproveDialog] = useState(false);

  const confirmDelete = useCallback(async () => {
    if (!automation) return;
    try {
      await api.deleteAutomation(automation.id);
      navigate('/automations');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to delete automation');
    }
    setShowDeleteConfirm(false);
  }, [api, automation, navigate]);

  const duplicateAutomation = useCallback(async () => {
    if (!automation) return;
    setIsDuplicating(true);
    try {
      const created = await api.createAutomation({
        name: `${automation.name} (Copy)`,
        description: automation.description,
        isEnabled: false,
        continueOnError: automation.continueOnError,
        retriggerPolicy: automation.retriggerPolicy,
        loggingOverride: automation.loggingOverride,
        triggers: automation.triggers,
        conditions: automation.conditions,
        blocks: automation.blocks,
      });
      navigate(`/automations/${created.id}/edit`);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to duplicate automation');
    } finally {
      setIsDuplicating(false);
    }
  }, [api, automation, navigate]);

  const triggerAutomation = useCallback(async () => {
    if (!automation) return;
    setIsTriggering(true);
    try {
      await api.triggerAutomation(automation.id);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to trigger automation');
    } finally {
      setIsTriggering(false);
    }
  }, [api, automation]);

  const handleOpenImprovedInEditor = useCallback((improved: AutomationDefinition) => {
    if (!automationId) return;
    setShowImproveDialog(false);
    navigate(`/automations/${automationId}/edit`, { state: { aiDraft: improved } });
  }, [automationId, navigate]);

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
        <span>Back to Automations</span>
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

      {automation && (
        <>
          {/* Header Section */}
          <div className="wfd-section wfd-header-section animate-fade-in">
            <div className="wfd-header-row">
              <h2 className="wfd-automation-name">{automation.name}</h2>
              <div className="wfd-header-actions">
                <div className="wfd-header-actions-row">
                  <button className="wfd-icon-btn" onClick={triggerAutomation} disabled={isTriggering} title="Run Now">
                    <Icon name={isTriggering ? 'spinner' : 'play-circle-fill'} size={16} />
                  </button>
                  <button className="wfd-icon-btn" onClick={() => setShowImproveDialog(true)} title="Improve with AI">
                    <Icon name="sparkles" size={16} />
                  </button>
                  <button className="wfd-icon-btn" onClick={() => navigate(`/automations/${automationId}/edit`)} title="Edit">
                    <Icon name="pencil" size={16} />
                  </button>
                  <button className="wfd-icon-btn" onClick={duplicateAutomation} disabled={isDuplicating} title="Duplicate">
                    <Icon name="copy" size={16} />
                  </button>
                  <button className="wfd-icon-btn wfd-danger" onClick={() => setShowDeleteConfirm(true)} title="Delete">
                    <Icon name="trash" size={16} />
                  </button>
                </div>
                {automation.isEnabled ? (
                  <span className="wfd-status-badge wfd-enabled">Enabled</span>
                ) : (
                  <span className="wfd-status-badge wfd-disabled">Disabled</span>
                )}
              </div>
            </div>
            {automation.description && (
              <p className="wfd-description">{automation.description}</p>
            )}
          </div>

          {/* Metadata Chips */}
          <div className="wfd-meta-chips animate-fade-in">
            <span className="wfd-chip wfd-chip-executions">
              <Icon name="play-circle-fill" size={13} />
              <span className="wfd-chip-label">Executions</span>
              <span className="wfd-chip-value">{automation.metadata.totalExecutions}</span>
            </span>
            {automation.metadata.lastTriggeredAt && (
              <span className="wfd-chip wfd-chip-triggered">
                <Icon name="clock" size={13} />
                <span className="wfd-chip-label">Last triggered</span>
                <span className="wfd-chip-value">{formatDate(automation.metadata.lastTriggeredAt)}</span>
              </span>
            )}
            <span className={`wfd-chip wfd-chip-failures ${automation.metadata.consecutiveFailures > 0 ? 'wfd-chip-failures-active' : ''}`}>
              <Icon name="exclamation-circle-fill" size={13} />
              <span className="wfd-chip-label">Consecutive failures</span>
              <span className="wfd-chip-value">{automation.metadata.consecutiveFailures}</span>
            </span>
            <span className="wfd-chip wfd-chip-updated">
              <Icon name="refresh-circle-fill" size={13} />
              <span className="wfd-chip-label">Updated</span>
              <span className="wfd-chip-value">{formatDate(automation.updatedAt)}</span>
            </span>
            <span className={`wfd-chip wfd-chip-error-policy ${automation.continueOnError ? 'wfd-chip-yes' : ''}`}>
              <Icon name="forward-circle-fill" size={13} />
              <span className="wfd-chip-label">Continue on error</span>
              <span className="wfd-chip-value">{automation.continueOnError ? 'Yes' : 'No'}</span>
            </span>
            {automation.metadata.tags?.map((tag, i) => (
              <span key={i} className="wfd-chip wfd-chip-tag">
                <Icon name="funnel" size={13} />
                <span className="wfd-chip-value">{tag}</span>
              </span>
            ))}
          </div>

          {/* Triggers Section */}
          <div className="wfd-section animate-fade-in">
            <h3 className="wfd-section-title">
              Triggers <span className="wfd-count">({automation.triggers.length})</span>
            </h3>
            <div className="wfd-tree-content wfd-triggers">
              {automation.triggers.map((trigger, i) => (
                <DefinitionTrigger key={i} trigger={trigger} depth={0} />
              ))}
            </div>
          </div>

          {/* Execution Guards Section */}
          {automation.conditions && automation.conditions.length > 0 && (
            <div className="wfd-section animate-fade-in">
              <h3 className="wfd-section-title">Execution Guards</h3>
              <div className="wfd-tree-content">
                {automation.conditions.map((condition, i) => (
                  <DefinitionCondition key={i} condition={condition} depth={0} isFirst={i === 0} isLast={i === automation.conditions!.length - 1} />
                ))}
              </div>
            </div>
          )}

          {/* Blocks Section */}
          <div className="wfd-section animate-fade-in">
            <h3 className="wfd-section-title">
              Blocks <span className="wfd-count">({automation.blocks.length})</span>
            </h3>
            <div className="wfd-tree-content">
              {automation.blocks.map((block, i) => (
                <DefinitionBlockTree key={block.blockId} block={block} depth={0} index={i} isFirst={i === 0} isLast={i === automation.blocks.length - 1} />
              ))}
            </div>
          </div>

          {/* Execution Logs Button */}
          <button className="wfd-exec-logs-btn" onClick={() => navigate(`/automations/${automationId}`)}>
            <span>View Execution Logs</span>
            <Icon name="chevron-right" size={16} />
          </button>
        </>
      )}

      <ConfirmDialog
        open={showDeleteConfirm}
        title="Delete Automation"
        message={`Delete "${automation?.name}"? This cannot be undone.`}
        confirmLabel="Delete"
        destructive
        onConfirm={confirmDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      {automation && automationId && (
        <AIImproveDialog
          open={showImproveDialog}
          automationId={automationId}
          automationName={automation.name}
          originalAutomation={automation}
          onClose={() => setShowImproveDialog(false)}
          onOpenInEditor={handleOpenImprovedInEditor}
        />
      )}
    </div>
  );
}
