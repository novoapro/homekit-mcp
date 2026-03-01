import { useState, useCallback } from 'react';
import { Switch } from '@headlessui/react';
import { useConfig } from '@/contexts/ConfigContext';
import { useWebSocket } from '@/contexts/WebSocketContext';
import { Icon } from '@/components/Icon';
import './SettingsPage.css';

export function SettingsPage() {
  const { config, setConfig, save } = useConfig();
  const ws = useWebSocket();

  const [localState, setLocalState] = useState({
    serverAddress: config.serverAddress,
    serverPort: config.serverPort,
    bearerToken: config.bearerToken,
    pollingInterval: config.pollingInterval,
    websocketEnabled: config.websocketEnabled,
  });

  const [connectionStatus, setConnectionStatus] = useState<'idle' | 'testing' | 'success' | 'error'>('idle');
  const [saved, setSaved] = useState(false);

  const updateField = useCallback(<K extends keyof typeof localState>(key: K, value: (typeof localState)[K]) => {
    setLocalState(prev => ({ ...prev, [key]: value }));
  }, []);

  const applyToConfig = useCallback(() => {
    setConfig(localState);
  }, [localState, setConfig]);

  const testConnection = useCallback(async () => {
    applyToConfig();
    setConnectionStatus('testing');
    try {
      const url = `http://${localState.serverAddress}:${localState.serverPort}/health`;
      const res = await fetch(url);
      setConnectionStatus(res.ok ? 'success' : 'error');
    } catch {
      setConnectionStatus('error');
    }
    setTimeout(() => setConnectionStatus('idle'), 3000);
  }, [applyToConfig, localState.serverAddress, localState.serverPort]);

  const handleSave = useCallback(() => {
    applyToConfig();
    save(localState);

    // Reconnect or disconnect WebSocket based on new settings
    if (localState.websocketEnabled) {
      ws.reconnect();
    } else {
      ws.disconnect();
    }

    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }, [applyToConfig, save, localState, ws]);

  return (
    <div className="settings-page">
      <div className="page-header">
        <h1 className="page-title">Settings</h1>
      </div>

      <div className="settings-card">
        <h3 className="section-heading">Connection</h3>

        <div className="form-group">
          <label htmlFor="serverAddress">Server Address</label>
          <input
            id="serverAddress"
            type="text"
            value={localState.serverAddress}
            onChange={e => updateField('serverAddress', e.target.value)}
            placeholder="localhost"
            className="form-input"
          />
          <span className="hint">IP address or hostname of the HomeKit MCP server</span>
        </div>

        <div className="form-group">
          <label htmlFor="serverPort">Port</label>
          <input
            id="serverPort"
            type="number"
            value={localState.serverPort}
            onChange={e => updateField('serverPort', Number(e.target.value))}
            placeholder="3000"
            className="form-input"
            min={1}
            max={65535}
          />
        </div>

        <div className="form-group">
          <label htmlFor="bearerToken">Bearer Token</label>
          <input
            id="bearerToken"
            type="password"
            value={localState.bearerToken}
            onChange={e => updateField('bearerToken', e.target.value)}
            placeholder="Enter your API token"
            className="form-input"
          />
          <span className="hint">Found in the HomeKit MCP app settings under API tokens</span>
        </div>

        <div className="form-group">
          <label htmlFor="pollingInterval">Polling Interval (seconds)</label>
          <input
            id="pollingInterval"
            type="number"
            value={localState.pollingInterval}
            onChange={e => updateField('pollingInterval', Number(e.target.value))}
            placeholder="10"
            className="form-input"
            min={0}
            max={300}
          />
          <span className="hint">Set to 0 to disable auto-polling</span>
        </div>

        <h3 className="section-heading">Real-time Updates</h3>

        <div className="form-group">
          <div className="toggle-row">
            <label>Enable WebSocket</label>
            <Switch
              checked={localState.websocketEnabled}
              onChange={v => updateField('websocketEnabled', v)}
              className={`toggle-switch ${localState.websocketEnabled ? 'active' : ''}`}
            >
              <span className="toggle-switch-knob" />
            </Switch>
          </div>
          <span className="hint">When enabled, logs update instantly via WebSocket. When disabled, falls back to polling only.</span>
        </div>

        <div className="button-row">
          <button className="btn btn-secondary" onClick={testConnection}>
            {connectionStatus === 'testing' ? (
              <><Icon name="spinner" size={16} className="animate-spin-custom" /><span>Testing...</span></>
            ) : connectionStatus === 'success' ? (
              <><Icon name="checkmark-circle-fill" size={16} /><span>Connected</span></>
            ) : connectionStatus === 'error' ? (
              <><Icon name="xmark-circle-fill" size={16} /><span>Failed</span></>
            ) : (
              <><Icon name="wifi" size={16} /><span>Test Connection</span></>
            )}
          </button>

          <button className="btn btn-primary" onClick={handleSave}>
            {saved ? (
              <><Icon name="checkmark-circle-fill" size={16} /><span>Saved!</span></>
            ) : (
              <span>Save Settings</span>
            )}
          </button>
        </div>

        {connectionStatus === 'success' && (
          <div className="status-message success animate-fade-in">
            Successfully connected to the server
          </div>
        )}
        {connectionStatus === 'error' && (
          <div className="status-message error animate-fade-in">
            Could not connect. Check the address, port, and that the server is running.
          </div>
        )}
      </div>
    </div>
  );
}
