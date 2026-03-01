import { useState, useCallback } from 'react';
import { Sidebar } from '@/components/Sidebar';
import { TopBar } from '@/components/TopBar';
import { PageTransition } from '@/components/PageTransition';
import { AppRoutes } from '@/router';
import { useConfig } from '@/contexts/ConfigContext';
import { useWebSocket } from '@/contexts/WebSocketContext';
import '@/components/Sidebar.css';
import '@/components/TopBar.css';

export function App() {
  const { config } = useConfig();
  const ws = useWebSocket();

  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(() =>
    localStorage.getItem('hk-log-viewer:sidebar-collapsed') === 'true',
  );

  const toggleSidebarCollapse = useCallback(() => {
    setSidebarCollapsed(prev => {
      const next = !prev;
      localStorage.setItem('hk-log-viewer:sidebar-collapsed', String(next));
      return next;
    });
  }, []);

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar
        isOpen={sidebarOpen}
        collapsed={sidebarCollapsed}
        onClose={() => setSidebarOpen(false)}
        onToggleCollapse={toggleSidebarCollapse}
      />

      {/* Sidebar offset — desktop only */}
      <style>{`
        @media (min-width: 769px) {
          .content-offset-expanded { margin-left: var(--sidebar-width); }
          .content-offset-collapsed { margin-left: var(--sidebar-collapsed-width); }
        }
      `}</style>
      <div
        className={`flex flex-col flex-1 overflow-hidden ${sidebarCollapsed ? 'content-offset-collapsed' : 'content-offset-expanded'}`}
        style={{ transition: 'margin-left var(--sidebar-transition)' }}
      >
        <TopBar
          title="HomeKit MCP"
          websocketEnabled={config.websocketEnabled}
          connectionState={ws.connectionState}
          lastPollTime={null}
          onMenuClick={() => setSidebarOpen(true)}
        />

        <main className="flex-1 overflow-y-auto overflow-x-hidden">
          <PageTransition>
            <AppRoutes />
          </PageTransition>
        </main>
      </div>
    </div>
  );
}
