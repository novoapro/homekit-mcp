import { Routes, Route, Navigate } from 'react-router';
import { useConfig } from '@/contexts/ConfigContext';
import { SettingsPage } from '@/pages/SettingsPage';
import { LogsPage } from '@/pages/LogsPage';
import { WorkflowsPage } from '@/pages/WorkflowsPage';
import { WorkflowDefinitionPage } from '@/pages/WorkflowDefinitionPage';
import { WorkflowExecutionListPage } from '@/pages/WorkflowExecutionListPage';
import { WorkflowExecutionDetailPage } from '@/pages/WorkflowExecutionDetailPage';
import { WorkflowEditorPage } from '@/features/workflows/editor/WorkflowEditorPage';

function ConfigGuard({ children }: { children: React.ReactNode }) {
  const { isConfigured } = useConfig();
  if (!isConfigured) return <Navigate to="/settings" replace />;
  return <>{children}</>;
}

export function AppRoutes() {
  return (
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
  );
}
