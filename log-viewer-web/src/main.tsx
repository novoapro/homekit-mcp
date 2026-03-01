import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router';
import { ThemeProvider } from '@/contexts/ThemeContext';
import { ConfigProvider } from '@/contexts/ConfigContext';
import { WebSocketProvider } from '@/contexts/WebSocketContext';
import { DeviceRegistryProvider } from '@/contexts/DeviceRegistryContext';
import { App } from '@/App';
import './index.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
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
  </StrictMode>,
);
