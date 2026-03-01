import { useState, useCallback, useRef, useEffect } from 'react';
import { Icon } from './Icon';
import './AIGenerateDialog.css';

type Phase = 'input' | 'loading' | 'success' | 'error';

interface GenerateResult {
  id: string;
  name: string;
  description: string | null;
}

interface AIGenerateDialogProps {
  open: boolean;
  onClose: () => void;
  onGenerate: (prompt: string) => Promise<GenerateResult>;
  onViewWorkflow: (id: string) => void;
}

export function AIGenerateDialog({ open, onClose, onGenerate, onViewWorkflow }: AIGenerateDialogProps) {
  const [phase, setPhase] = useState<Phase>('input');
  const [prompt, setPrompt] = useState('');
  const [result, setResult] = useState<GenerateResult | null>(null);
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
      setResult(null);
      setError(null);
    }
  }, [open]);

  const handleGenerate = useCallback(async () => {
    if (!prompt.trim()) return;
    setPhase('loading');
    setError(null);
    try {
      const res = await onGenerate(prompt.trim());
      setResult(res);
      setPhase('success');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to generate workflow');
      setPhase('error');
    }
  }, [prompt, onGenerate]);

  const handleRetry = useCallback(() => {
    setPhase('input');
    setError(null);
  }, []);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (phase === 'loading') return; // Don't close during generation
        onClose();
      }
    },
    [phase, onClose],
  );

  const handleSubmitKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        handleGenerate();
      }
    },
    [handleGenerate],
  );

  if (!open) return null;

  return (
    <div className="aig-overlay" onClick={phase !== 'loading' ? onClose : undefined} onKeyDown={handleKeyDown} role="dialog" aria-modal="true" aria-labelledby="aig-title">
      <div className="aig-dialog" onClick={(e) => e.stopPropagation()}>

        {/* Input phase */}
        {phase === 'input' && (
          <>
            <div className="aig-icon-wrap">
              <Icon name="sparkles" size={24} />
            </div>
            <h3 id="aig-title" className="aig-title">Generate Workflow</h3>
            <p className="aig-subtitle">Describe the automation you want to create using natural language.</p>
            <textarea
              ref={textareaRef}
              className="aig-textarea"
              placeholder="e.g. Turn on the living room lights at sunset"
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              onKeyDown={handleSubmitKeyDown}
            />
            <div className="aig-actions">
              <button type="button" className="aig-btn secondary" onClick={onClose}>
                Cancel
              </button>
              <button
                type="button"
                className="aig-btn primary"
                disabled={!prompt.trim()}
                onClick={handleGenerate}
              >
                Generate
              </button>
            </div>
          </>
        )}

        {/* Loading phase */}
        {phase === 'loading' && (
          <>
            <div className="aig-icon-wrap">
              <Icon name="sparkles" size={24} />
            </div>
            <h3 className="aig-title">Generating Workflow</h3>
            <div className="aig-spinner" />
            <p className="aig-loading-text">Creating your automation with AI...</p>
          </>
        )}

        {/* Success phase */}
        {phase === 'success' && result && (
          <>
            <div className="aig-icon-wrap success">
              <Icon name="checkmark-circle" size={24} />
            </div>
            <h3 className="aig-title">Workflow Created</h3>
            <p className="aig-result-name">{result.name}</p>
            {result.description && (
              <p className="aig-result-desc">{result.description}</p>
            )}
            <div className="aig-actions">
              <button type="button" className="aig-btn secondary" onClick={onClose}>
                Close
              </button>
              <button
                type="button"
                className="aig-btn primary"
                onClick={() => onViewWorkflow(result.id)}
              >
                View Workflow
              </button>
            </div>
          </>
        )}

        {/* Error phase */}
        {phase === 'error' && (
          <>
            <div className="aig-icon-wrap error">
              <Icon name="exclamation-triangle" size={24} />
            </div>
            <h3 className="aig-title">Generation Failed</h3>
            <p className="aig-error-text">{error}</p>
            <div className="aig-actions">
              <button type="button" className="aig-btn secondary" onClick={onClose}>
                Close
              </button>
              <button type="button" className="aig-btn primary" onClick={handleRetry}>
                Try Again
              </button>
            </div>
          </>
        )}

      </div>
    </div>
  );
}
