import { useState, useCallback, useRef, useEffect } from 'react';
import { Icon } from './Icon';
import { useApi } from '@/hooks/useApi';
import type { WorkflowDefinition } from '@/types/workflow-definition';
import './AIImproveDialog.css';

type Phase = 'input' | 'loading' | 'review' | 'error';

interface AIImproveDialogProps {
  open: boolean;
  workflowId: string;
  workflowName: string;
  originalWorkflow: WorkflowDefinition;
  onClose: () => void;
  onOpenInEditor: (workflow: WorkflowDefinition) => void;
}

export function AIImproveDialog({
  open,
  workflowId,
  workflowName,
  originalWorkflow,
  onClose,
  onOpenInEditor,
}: AIImproveDialogProps) {
  const api = useApi();
  const [phase, setPhase] = useState<Phase>('input');
  const [prompt, setPrompt] = useState('');
  const [improved, setImproved] = useState<WorkflowDefinition | null>(null);
  const [error, setError] = useState<string | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Focus textarea when dialog opens
  useEffect(() => {
    if (open && phase === 'input') {
      const timer = setTimeout(() => textareaRef.current?.focus(), 100);
      return () => clearTimeout(timer);
    }
  }, [open, phase]);

  // Reset state when dialog closes
  useEffect(() => {
    if (!open) {
      setPhase('input');
      setPrompt('');
      setImproved(null);
      setError(null);
    }
  }, [open]);

  const handleImprove = useCallback(async () => {
    setPhase('loading');
    setError(null);
    try {
      const trimmed = prompt.trim();
      const result = await api.improveWorkflow(workflowId, trimmed || undefined);
      setImproved(result);
      setPhase('review');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to improve workflow');
      setPhase('error');
    }
  }, [prompt, workflowId, api]);

  const handleOpenInEditor = useCallback(() => {
    if (!improved) return;
    onOpenInEditor(improved);
  }, [improved, onOpenInEditor]);

  const handleRetry = useCallback(() => {
    setPhase('input');
    setError(null);
  }, []);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (phase === 'loading') return;
        onClose();
      }
    },
    [phase, onClose],
  );

  const handleSubmitKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        handleImprove();
      }
    },
    [handleImprove],
  );

  // Build change summary
  const changeSummary = improved
    ? {
        name: improved.name !== originalWorkflow.name,
        description: improved.description !== originalWorkflow.description,
        triggers: improved.triggers.length !== originalWorkflow.triggers.length,
        triggerCount: improved.triggers.length,
        blocks: improved.blocks.length !== originalWorkflow.blocks.length,
        blockCount: improved.blocks.length,
        conditions:
          (improved.conditions?.length ?? 0) !== (originalWorkflow.conditions?.length ?? 0),
        conditionCount: improved.conditions?.length ?? 0,
      }
    : null;

  if (!open) return null;

  return (
    <div
      className="aii-overlay"
      onClick={phase !== 'loading' ? onClose : undefined}
      onKeyDown={handleKeyDown}
      role="dialog"
      aria-modal="true"
      aria-labelledby="aii-title"
    >
      <div className="aii-dialog" onClick={(e) => e.stopPropagation()}>
        {/* Input phase */}
        {phase === 'input' && (
          <>
            <div className="aii-icon-wrap">
              <Icon name="sparkles" size={24} />
            </div>
            <h3 id="aii-title" className="aii-title">Improve Workflow</h3>
            <p className="aii-subtitle">
              Describe what you'd like to change, or leave empty for an automatic review and optimization.
            </p>
            <div className="aii-workflow-badge">
              <Icon name="bolt" size={13} />
              <span>{workflowName}</span>
            </div>
            <textarea
              ref={textareaRef}
              className="aii-textarea"
              placeholder="e.g., Add a condition to only run during nighttime"
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              onKeyDown={handleSubmitKeyDown}
            />
            <div className="aii-actions">
              <button type="button" className="aii-btn secondary" onClick={onClose}>
                Cancel
              </button>
              <button type="button" className="aii-btn primary" onClick={handleImprove}>
                Improve
              </button>
            </div>
          </>
        )}

        {/* Loading phase */}
        {phase === 'loading' && (
          <>
            <div className="aii-icon-wrap">
              <Icon name="sparkles" size={24} />
            </div>
            <h3 className="aii-title">Improving Workflow</h3>
            <div className="aii-spinner" />
            <p className="aii-loading-text">Analyzing and improving your workflow...</p>
          </>
        )}

        {/* Review phase */}
        {phase === 'review' && improved && changeSummary && (
          <>
            <div className="aii-icon-wrap success">
              <Icon name="checkmark-circle" size={24} />
            </div>
            <h3 className="aii-title">Improvements Ready</h3>
            <p className="aii-result-name">{improved.name}</p>
            {improved.description && (
              <p className="aii-result-desc">{improved.description}</p>
            )}

            <div className="aii-changes">
              <div className="aii-changes-title">
                <Icon name="pencil" size={13} />
                <span>Changes</span>
              </div>
              <div className="aii-change-items">
                {changeSummary.name && (
                  <span className="aii-change-chip">Name updated</span>
                )}
                {changeSummary.description && (
                  <span className="aii-change-chip">Description updated</span>
                )}
                <span className={`aii-change-chip ${changeSummary.triggers ? 'changed' : ''}`}>
                  {changeSummary.triggerCount} trigger{changeSummary.triggerCount !== 1 ? 's' : ''}
                  {changeSummary.triggers && (
                    <span className="aii-change-delta">
                      {' '}(was {originalWorkflow.triggers.length})
                    </span>
                  )}
                </span>
                <span className={`aii-change-chip ${changeSummary.blocks ? 'changed' : ''}`}>
                  {changeSummary.blockCount} block{changeSummary.blockCount !== 1 ? 's' : ''}
                  {changeSummary.blocks && (
                    <span className="aii-change-delta">
                      {' '}(was {originalWorkflow.blocks.length})
                    </span>
                  )}
                </span>
                {(changeSummary.conditionCount > 0 || (originalWorkflow.conditions?.length ?? 0) > 0) && (
                  <span className={`aii-change-chip ${changeSummary.conditions ? 'changed' : ''}`}>
                    {changeSummary.conditionCount} guard{changeSummary.conditionCount !== 1 ? 's' : ''}
                    {changeSummary.conditions && (
                      <span className="aii-change-delta">
                        {' '}(was {originalWorkflow.conditions?.length ?? 0})
                      </span>
                    )}
                  </span>
                )}
              </div>
            </div>

            <div className="aii-actions">
              <button type="button" className="aii-btn secondary" onClick={onClose}>
                Discard
              </button>
              <button type="button" className="aii-btn primary" onClick={handleOpenInEditor}>
                Open in Editor
              </button>
            </div>
          </>
        )}

        {/* Error phase */}
        {phase === 'error' && (
          <>
            <div className="aii-icon-wrap error">
              <Icon name="exclamation-triangle" size={24} />
            </div>
            <h3 className="aii-title">Improvement Failed</h3>
            <p className="aii-error-text">{error}</p>
            <div className="aii-actions">
              <button type="button" className="aii-btn secondary" onClick={onClose}>
                Close
              </button>
              <button type="button" className="aii-btn primary" onClick={handleRetry}>
                Try Again
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
