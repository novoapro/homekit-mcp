import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import { ErrorBoundary } from '@/components/ErrorBoundary';
import { ThemeProvider } from '@/contexts/ThemeContext';
import { ConfigProvider } from '@/contexts/ConfigContext';
import { WebSocketProvider } from '@/contexts/WebSocketContext';
import { DeviceRegistryProvider } from '@/contexts/DeviceRegistryContext';
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
                <App />
              </DeviceRegistryProvider>
            </WebSocketProvider>
          </ConfigProvider>
        </ThemeProvider>
      </BrowserRouter>
    </ErrorBoundary>
  </StrictMode>,
);
