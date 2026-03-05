import { useState, useCallback, useRef, useEffect } from 'react';
import { Icon } from './Icon';
import { DeviceScenePicker } from './DeviceScenePicker';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { getServiceIcon } from '@/utils/service-icons';
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
  onGenerate: (prompt: string, deviceIds?: string[], sceneIds?: string[]) => Promise<GenerateResult>;
  onViewWorkflow: (id: string) => void;
}

export function AIGenerateDialog({ open, onClose, onGenerate, onViewWorkflow }: AIGenerateDialogProps) {
  const [phase, setPhase] = useState<Phase>('input');
  const [prompt, setPrompt] = useState('');
  const [result, setResult] = useState<GenerateResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selectedDeviceIds, setSelectedDeviceIds] = useState<Set<string>>(new Set());
  const [selectedSceneIds, setSelectedSceneIds] = useState<Set<string>>(new Set());
  const [showPicker, setShowPicker] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const { devices, scenes } = useDeviceRegistry();

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
      setSelectedDeviceIds(new Set());
      setSelectedSceneIds(new Set());
      setShowPicker(false);
    }
  }, [open]);

  const handleGenerate = useCallback(async () => {
    if (!prompt.trim()) return;
    setPhase('loading');
    setError(null);
    try {
      const dIds = selectedDeviceIds.size > 0 ? Array.from(selectedDeviceIds) : undefined;
      const sIds = selectedSceneIds.size > 0 ? Array.from(selectedSceneIds) : undefined;
      const res = await onGenerate(prompt.trim(), dIds, sIds);
      setResult(res);
      setPhase('success');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to generate workflow');
      setPhase('error');
    }
  }, [prompt, selectedDeviceIds, selectedSceneIds, onGenerate]);

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
        handleGenerate();
      }
    },
    [handleGenerate],
  );

  const toggleDevice = useCallback((id: string) => {
    setSelectedDeviceIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }, []);

  const toggleScene = useCallback((id: string) => {
    setSelectedSceneIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }, []);

  const removeDevice = useCallback((id: string) => {
    setSelectedDeviceIds(prev => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const removeScene = useCallback((id: string) => {
    setSelectedSceneIds(prev => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const selectionCount = selectedDeviceIds.size + selectedSceneIds.size;

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

            {/* Selected items as pills */}
            {selectionCount > 0 && (
              <div className="aig-selected-pills">
                {Array.from(selectedDeviceIds).map(id => {
                  const device = devices.find(d => d.id === id);
                  if (!device) return null;
                  const iconName = getServiceIcon(device.services[0]?.type) ?? getServiceIcon(device.services[0]?.name) ?? 'house';
                  return (
                    <span key={id} className="aig-pill">
                      <span className="aig-pill-icon"><Icon name={iconName} size={12} /></span>
                      <span className="aig-pill-name">{device.name}</span>
                      {device.room && <span className="aig-pill-room">{device.room}</span>}
                      <button
                        type="button"
                        className="aig-pill-remove"
                        onClick={() => removeDevice(id)}
                        aria-label={`Remove ${device.name}`}
                      >
                        <Icon name="xmark" size={10} />
                      </button>
                    </span>
                  );
                })}
                {Array.from(selectedSceneIds).map(id => {
                  const scene = scenes.find(s => s.id === id);
                  if (!scene) return null;
                  return (
                    <span key={id} className="aig-pill scene">
                      <span className="aig-pill-icon"><Icon name="play-circle-fill" size={12} /></span>
                      <span className="aig-pill-name">{scene.name}</span>
                      <button
                        type="button"
                        className="aig-pill-remove"
                        onClick={() => removeScene(id)}
                        aria-label={`Remove ${scene.name}`}
                      >
                        <Icon name="xmark" size={10} />
                      </button>
                    </span>
                  );
                })}
              </div>
            )}

            {/* Picker toggle */}
            {(devices.length > 0 || scenes.length > 0) && (
              <button
                type="button"
                className="aig-picker-toggle"
                onClick={() => setShowPicker(prev => !prev)}
              >
                <Icon name={showPicker ? 'chevron-up' : 'chevron-down'} size={14} />
                {showPicker ? 'Hide device picker' : 'Select specific devices & scenes'}
                {selectionCount > 0 && (
                  <span className="aig-picker-count">{selectionCount}</span>
                )}
              </button>
            )}

            {/* Inline picker */}
            {showPicker && (
              <DeviceScenePicker
                devices={devices}
                scenes={scenes}
                selectedDeviceIds={selectedDeviceIds}
                selectedSceneIds={selectedSceneIds}
                onToggleDevice={toggleDevice}
                onToggleScene={toggleScene}
              />
            )}

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
