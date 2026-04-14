import { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { useRegisterRefresh } from '@/contexts/RefreshContext';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { ConfirmDialog } from '@/components/ConfirmDialog';
import { AIGenerateDialog } from '@/components/AIGenerateDialog';
import { AutomationCard } from '@/features/automations/AutomationCard';
import { useApi } from '@/hooks/useApi';
import { useConfig } from '@/contexts/ConfigContext';
import { useWebSocket } from '@/contexts/WebSocketContext';
import { useSubscription } from '@/contexts/SubscriptionContext';
import { SubscriptionRequiredError } from '@/lib/api';
import type { Automation } from '@/types/automation-log';
import './AutomationsPage.css';

export function AutomationsPage() {
  const api = useApi();
  const ws = useWebSocket();
  const { config } = useConfig();
  const { isPro } = useSubscription();
  const navigate = useNavigate();

  const [automations, setAutomations] = useState<Automation[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [requiresSubscription, setRequiresSubscription] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  useSetTopBar('Automation+', automations.length > 0 ? automations.length : null, isLoading);

  // Selection mode
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const loadAutomations = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const wfs = await api.getAutomations();
      setAutomations(wfs);
    } catch (err: unknown) {
      if (err instanceof SubscriptionRequiredError) {
        setRequiresSubscription(true);
      } else {
        setError(err instanceof Error ? err.message : 'Failed to load automations');
      }
    } finally {
      setIsLoading(false);
    }
  }, [api]);

  useRegisterRefresh(loadAutomations);

  useEffect(() => {
    loadAutomations();
  }, [loadAutomations]);

  // WebSocket: real-time automation list updates
  useEffect(() => {
    const unsub = ws.onAutomationsUpdated((updated) => {
      setAutomations(updated);
    });
    return unsub;
  }, [ws]);

  // Periodic polling — safety net regardless of WebSocket status
  useEffect(() => {
    const interval = config.pollingInterval;
    if (interval <= 0) return;

    const timer = setInterval(() => {
      if (document.visibilityState === 'visible') {
        loadAutomations();
      }
    }, interval * 1000);

    return () => clearInterval(timer);
  }, [config.pollingInterval, loadAutomations]);

  const filteredAutomations = useMemo(() => {
    if (!searchQuery.trim()) return automations;
    const q = searchQuery.toLowerCase();
    return automations.filter((wf) => wf.name.toLowerCase().includes(q));
  }, [automations, searchQuery]);

  const toggleAutomation = useCallback(async (automationId: string, enabled: boolean) => {
    // Optimistic update
    setAutomations(prev => prev.map(w => w.id === automationId ? { ...w, isEnabled: enabled } : w));

    try {
      const updated = await api.updateAutomation(automationId, { isEnabled: enabled });
      setAutomations(prev => prev.map(w => w.id === updated.id ? updated : w));
    } catch {
      // Revert
      setAutomations(prev => prev.map(w => w.id === automationId ? { ...w, isEnabled: !enabled } : w));
      setError('Failed to update automation');
    }
  }, [api]);

  const [deleteTarget, setDeleteTarget] = useState<Automation | null>(null);
  const [showAIDialog, setShowAIDialog] = useState(false);

  const handleDelete = useCallback((automationId: string) => {
    const wf = automations.find(w => w.id === automationId) ?? null;
    setDeleteTarget(wf);
  }, [automations]);

  const handleClick = useCallback((automationId: string) => {
    navigate(`/automations/${automationId}/definition`);
  }, [navigate]);

  // Bulk delete confirmation
  const [bulkDeletePending, setBulkDeletePending] = useState(false);

  const handleGenerate = useCallback(async (prompt: string, deviceIds?: string[], sceneIds?: string[]) => {
    return api.generateAutomation(prompt, deviceIds, sceneIds);
  }, [api]);

  const handleViewAutomation = useCallback((id: string) => {
    setShowAIDialog(false);
    navigate(`/automations/${id}/definition`);
  }, [navigate]);

  const confirmDelete = useCallback(async () => {
    if (!deleteTarget) return;
    try {
      await api.deleteAutomation(deleteTarget.id);
      setAutomations(prev => prev.filter(w => w.id !== deleteTarget.id));
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to delete automation');
    }
    setDeleteTarget(null);
  }, [api, deleteTarget]);

  // Selection mode handlers
  const enterSelectionMode = useCallback((automationId: string) => {
    setSelectionMode(true);
    setSelectedIds(new Set([automationId]));
  }, []);

  const toggleSelection = useCallback((automationId: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(automationId)) {
        next.delete(automationId);
      } else {
        next.add(automationId);
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
    setSelectedIds(new Set(filteredAutomations.map(wf => wf.id)));
  }, [filteredAutomations]);

  // Derive enable/disable counts from selection
  const selectedAutomations = useMemo(() =>
    automations.filter(w => selectedIds.has(w.id)),
    [automations, selectedIds]
  );
  const enabledCount = useMemo(() => selectedAutomations.filter(w => w.isEnabled).length, [selectedAutomations]);
  const disabledCount = useMemo(() => selectedAutomations.filter(w => !w.isEnabled).length, [selectedAutomations]);

  // Bulk set enabled state — skips automations already in the desired state
  const bulkSetEnabled = useCallback(async (enabled: boolean) => {
    const toUpdate = selectedAutomations.filter(w => w.isEnabled !== enabled);
    if (toUpdate.length === 0) { exitSelectionMode(); return; }

    const ids = toUpdate.map(w => w.id);
    // Optimistic
    setAutomations(prev => prev.map(w => ids.includes(w.id) ? { ...w, isEnabled: enabled } : w));

    try {
      await Promise.all(ids.map(id => api.updateAutomation(id, { isEnabled: enabled })));
    } catch {
      setError(`Failed to ${enabled ? 'enable' : 'disable'} some automations`);
      loadAutomations();
    }
    exitSelectionMode();
  }, [selectedAutomations, api, exitSelectionMode, loadAutomations]);

  // Bulk delete
  const confirmBulkDelete = useCallback(async () => {
    const ids = Array.from(selectedIds);
    try {
      await Promise.all(ids.map(id => api.deleteAutomation(id)));
      setAutomations(prev => prev.filter(w => !ids.includes(w.id)));
    } catch {
      setError('Failed to delete some automations');
      loadAutomations();
    }
    setBulkDeletePending(false);
    exitSelectionMode();
  }, [selectedIds, api, exitSelectionMode, loadAutomations]);

  const selectedCount = selectedIds.size;

  if (requiresSubscription || (!isPro && !isLoading && !error)) {
    return (
      <div className="auto-list-page">
        <div className="auto-page-header">
          <h1 className="auto-page-title">Automations</h1>
        </div>
        <div style={{ maxWidth: 500, margin: '60px auto', textAlign: 'center', padding: '0 20px' }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            width: 56, height: 56, borderRadius: 14,
            backgroundColor: 'rgba(255, 204, 0, 0.15)', marginBottom: 16,
          }}>
            <Icon name="crown-fill" size={28} style={{ color: '#FFCC00' }} />
          </div>
          <h2 style={{ fontSize: 20, fontWeight: 700, color: 'var(--text-primary)', margin: '0 0 8px' }}>
            Automations require Pro
          </h2>
          <p style={{ fontSize: 14, color: 'var(--text-secondary)', margin: '0 0 20px', lineHeight: 1.5 }}>
            Create powerful automations with triggers, conditions, and actions.
            Upgrade to Pro in the CompAI - Home macOS app.
          </p>
          <a
            href="/upgrade"
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 8,
              padding: '10px 24px', borderRadius: 10,
              background: 'rgba(255, 204, 0, 0.15)', color: '#FFCC00',
              fontWeight: 600, fontSize: 14, textDecoration: 'none',
            }}
          >
            <Icon name="crown-fill" size={16} />
            Learn More
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="auto-list-page">
      {/* Desktop page header */}
      <div className="auto-page-header">
        <h1 className="auto-page-title">Automations</h1>
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
                placeholder="Search automations..."
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
            <button className="wf-new-btn" onClick={() => navigate('/automations/new')}>
              <Icon name="plus" size={15} />
              New Automation
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
                placeholder="Search automations..."
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
            <button className="wf-toolbar-icon-btn primary" onClick={() => navigate('/automations/new')} title="New Automation">
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
      {isLoading && automations.length === 0 && (
        <div className="wf-skeleton-list">
          {Array.from({ length: 10 }, (_, i) => (
            <div key={i} className="wf-skeleton-card skeleton" style={{ animationDelay: `${i * 100}ms` }} />
          ))}
        </div>
      )}

      {/* Empty */}
      {!isLoading && automations.length === 0 && !error && (
        <EmptyState
          icon="bolt-circle-fill"
          title="No automations"
          message="No automations yet. Tap New Automation to create your first automation."
        />
      )}

      {/* Search no results */}
      {!isLoading && automations.length > 0 && filteredAutomations.length === 0 && searchQuery.trim() && (
        <EmptyState
          icon="magnifyingglass"
          title="No matches"
          message={`No automations matching "${searchQuery}".`}
        />
      )}

      {/* Controller States access row */}
      {!selectionMode && !isLoading && automations.length > 0 && (
        <div style={{ padding: '0 var(--spacing-md)' }}>
          <div
            className="auto-card"
            style={{
              display: 'flex', alignItems: 'center', gap: 12,
              marginBottom: 'var(--card-gap, 8px)', cursor: 'pointer',
              background: 'color-mix(in srgb, teal 5%, var(--bg-card))',
              borderLeft: '3px solid teal',
            }}
            onClick={() => navigate('/state-variables')}
          >
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              width: 36, height: 36, borderRadius: 10,
              background: 'color-mix(in srgb, teal 12%, transparent)',
            }}>
              <Icon name="state-variable" size={18} style={{ color: 'teal' }} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-primary)' }}>Controller States</div>
              <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>Manage persistent state for your automations</div>
            </div>
            <Icon name="chevron-right" size={14} style={{ color: 'var(--text-tertiary)' }} />
          </div>
        </div>
      )}

      {/* Automation card list */}
      {filteredAutomations.length > 0 && (
        <div className={`auto-card-list${selectionMode ? ' with-bulk-bar' : ''}`}>
          {filteredAutomations.map((wf, i) => (
            <AutomationCard
              key={wf.id}
              automation={wf}
              index={i}
              onToggleEnabled={toggleAutomation}
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
        onViewAutomation={handleViewAutomation}
      />

      <ConfirmDialog
        open={!!deleteTarget}
        title="Delete Automation"
        message={`Delete "${deleteTarget?.name}"? This cannot be undone.`}
        confirmLabel="Delete"
        destructive
        onConfirm={confirmDelete}
        onCancel={() => setDeleteTarget(null)}
      />

      <ConfirmDialog
        open={bulkDeletePending}
        title="Delete Automations"
        message={`Delete ${selectedCount} automation${selectedCount !== 1 ? 's' : ''}? This cannot be undone.`}
        confirmLabel="Delete All"
        destructive
        onConfirm={confirmBulkDelete}
        onCancel={() => setBulkDeletePending(false)}
      />
    </div>
  );
}
