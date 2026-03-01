import { lazy, Suspense } from 'react';
import { Routes, Route, Navigate } from 'react-router';
import { useConfig } from '@/contexts/ConfigContext';

const SettingsPage = lazy(() => import('@/pages/SettingsPage').then(m => ({ default: m.SettingsPage })));
const LogsPage = lazy(() => import('@/pages/LogsPage').then(m => ({ default: m.LogsPage })));
const WorkflowsPage = lazy(() => import('@/pages/WorkflowsPage').then(m => ({ default: m.WorkflowsPage })));
const WorkflowDefinitionPage = lazy(() => import('@/pages/WorkflowDefinitionPage').then(m => ({ default: m.WorkflowDefinitionPage })));
const WorkflowExecutionListPage = lazy(() => import('@/pages/WorkflowExecutionListPage').then(m => ({ default: m.WorkflowExecutionListPage })));
const WorkflowExecutionDetailPage = lazy(() => import('@/pages/WorkflowExecutionDetailPage').then(m => ({ default: m.WorkflowExecutionDetailPage })));
const WorkflowEditorPage = lazy(() => import('@/features/workflows/editor/WorkflowEditorPage').then(m => ({ default: m.WorkflowEditorPage })));

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
        <Route path="/" element={<Navigate to="/workflows" replace />} />
        <Route
          path="/logs"
          element={<ConfigGuard><LogsPage /></ConfigGuard>}
        />
        <Route
          path="/workflows"
          element={<ConfigGuard><WorkflowsPage /></ConfigGuard>}
        />
        <Route
          path="/workflows/new"
          element={<ConfigGuard><WorkflowEditorPage /></ConfigGuard>}
        />
        <Route
          path="/workflows/:workflowId/edit"
          element={<ConfigGuard><WorkflowEditorPage /></ConfigGuard>}
        />
        <Route
          path="/workflows/:workflowId/definition"
          element={<ConfigGuard><WorkflowDefinitionPage /></ConfigGuard>}
        />
        <Route
          path="/workflows/:workflowId/:logId"
          element={<ConfigGuard><WorkflowExecutionDetailPage /></ConfigGuard>}
        />
        <Route
          path="/workflows/:workflowId"
          element={<ConfigGuard><WorkflowExecutionListPage /></ConfigGuard>}
        />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<Navigate to="/workflows" replace />} />
      </Routes>
    </Suspense>
  );
}
