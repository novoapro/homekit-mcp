import { lazy, Suspense } from 'react';
import { Routes, Route, Navigate } from 'react-router';
import { useConfig } from '@/contexts/ConfigContext';

const SettingsPage = lazy(() => import('@/pages/SettingsPage').then(m => ({ default: m.SettingsPage })));
const LogsPage = lazy(() => import('@/pages/LogsPage').then(m => ({ default: m.LogsPage })));
const AutomationsPage = lazy(() => import('@/pages/AutomationsPage').then(m => ({ default: m.AutomationsPage })));
const AutomationDefinitionPage = lazy(() => import('@/pages/AutomationDefinitionPage').then(m => ({ default: m.AutomationDefinitionPage })));
const AutomationExecutionListPage = lazy(() => import('@/pages/AutomationExecutionListPage').then(m => ({ default: m.AutomationExecutionListPage })));
const AutomationExecutionDetailPage = lazy(() => import('@/pages/AutomationExecutionDetailPage').then(m => ({ default: m.AutomationExecutionDetailPage })));
const AutomationEditorPage = lazy(() => import('@/features/automations/editor/AutomationEditorPage').then(m => ({ default: m.AutomationEditorPage })));
const DevicesPage = lazy(() => import('@/pages/DevicesPage').then(m => ({ default: m.DevicesPage })));
const UpgradePage = lazy(() => import('@/pages/UpgradePage').then(m => ({ default: m.UpgradePage })));
const StateVariablesPage = lazy(() => import('@/pages/StateVariablesPage').then(m => ({ default: m.StateVariablesPage })));

function LoadingFallback() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '50vh' }}>
      <span className="material-symbols-rounded animate-spin-custom" style={{ fontSize: 32, color: 'var(--text-tertiary)' }}>
        progress_activity
      </span>
    </div>
  );
}

function ConfigGuard({ children }: { children: React.ReactNode }) {
  const { isConfigured } = useConfig();
  if (!isConfigured) return <Navigate to="/settings" replace />;
  return <>{children}</>;
}

export function AppRoutes() {
  return (
    <Suspense fallback={<LoadingFallback />}>
      <Routes>
        <Route path="/" element={<Navigate to="/devices" replace />} />
        <Route
          path="/devices"
          element={<ConfigGuard><DevicesPage /></ConfigGuard>}
        />
        <Route
          path="/logs"
          element={<ConfigGuard><LogsPage /></ConfigGuard>}
        />
        <Route
          path="/automations"
          element={<ConfigGuard><AutomationsPage /></ConfigGuard>}
        />
        <Route
          path="/automations/new"
          element={<ConfigGuard><AutomationEditorPage /></ConfigGuard>}
        />
        <Route
          path="/automations/:automationId/edit"
          element={<ConfigGuard><AutomationEditorPage /></ConfigGuard>}
        />
        <Route
          path="/automations/:automationId/definition"
          element={<ConfigGuard><AutomationDefinitionPage /></ConfigGuard>}
        />
        <Route
          path="/automations/:automationId/:logId"
          element={<ConfigGuard><AutomationExecutionDetailPage /></ConfigGuard>}
        />
        <Route
          path="/automations/:automationId"
          element={<ConfigGuard><AutomationExecutionListPage /></ConfigGuard>}
        />
        <Route
          path="/state-variables"
          element={<ConfigGuard><StateVariablesPage /></ConfigGuard>}
        />
        <Route path="/upgrade" element={<ConfigGuard><UpgradePage /></ConfigGuard>} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<Navigate to="/automations" replace />} />
      </Routes>
    </Suspense>
  );
}
