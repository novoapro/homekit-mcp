import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import { ErrorBoundary } from '@/components/ErrorBoundary';
import { ThemeProvider } from '@/contexts/ThemeContext';
import { ConfigProvider } from '@/contexts/ConfigContext';
import { WebSocketProvider } from '@/contexts/WebSocketContext';
import { DeviceRegistryProvider } from '@/contexts/DeviceRegistryContext';
import { TopBarProvider } from '@/contexts/TopBarContext';
import { RefreshProvider } from '@/contexts/RefreshContext';
import { App } from '@/App';
import './index.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <ThemeProvider>
          <ConfigProvider>
            <WebSocketProvider>
              <DeviceRegistryProvider>
                <TopBarProvider>
                  <RefreshProvider>
                    <App />
                  </RefreshProvider>
                </TopBarProvider>
              </DeviceRegistryProvider>
            </WebSocketProvider>
          </ConfigProvider>
        </ThemeProvider>
      </BrowserRouter>
    </ErrorBoundary>
  </StrictMode>,
);
