import { useState, useCallback } from 'react';
import { Switch } from '@headlessui/react';
import { useConfig } from '@/contexts/ConfigContext';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { useWebSocket } from '@/contexts/WebSocketContext';
import { Icon } from '@/components/Icon';
import './SettingsPage.css';

export function SettingsPage() {
  const { config, setConfig, save } = useConfig();
  const ws = useWebSocket();
  useSetTopBar('Settings');

  const [localState, setLocalState] = useState({
    serverAddress: config.serverAddress,
    serverPort: config.serverPort,
    bearerToken: config.bearerToken,
    pollingInterval: config.pollingInterval,
    websocketEnabled: config.websocketEnabled,
    useHTTPS: config.useHTTPS,
    authMethod: config.authMethod,
    oauthClientId: config.oauthClientId,
    oauthClientSecret: config.oauthClientSecret,
  });

  const [pendingAuthSwitch, setPendingAuthSwitch] = useState<'bearer' | 'oauth' | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'idle' | 'testing' | 'success' | 'error'>('idle');
  const [saved, setSaved] = useState(false);

  const updateField = useCallback(<K extends keyof typeof localState>(key: K, value: (typeof localState)[K]) => {
    setLocalState(prev => ({ ...prev, [key]: value }));
  }, []);

  const testConnection = useCallback(async () => {
    setConnectionStatus('testing');
    try {
      const protocol = localState.useHTTPS ? 'https' : 'http';
      const url = `${protocol}://${localState.serverAddress}:${localState.serverPort}/health`;
      const res = await fetch(url);
      setConnectionStatus(res.ok ? 'success' : 'error');
    } catch {
      setConnectionStatus('error');
    }
    setTimeout(() => setConnectionStatus('idle'), 3000);
  }, [localState.serverAddress, localState.serverPort, localState.useHTTPS]);

  const [validationError, setValidationError] = useState<string | null>(null);

  const handleSave = useCallback(() => {
    // Validate server address (hostname, IP, or localhost)
    const addressPattern = /^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?$/;
    if (!addressPattern.test(localState.serverAddress)) {
      setValidationError('Invalid server address. Use a hostname or IP address.');
      return;
    }
    if (localState.serverPort < 1 || localState.serverPort > 65535 || !Number.isInteger(localState.serverPort)) {
      setValidationError('Port must be an integer between 1 and 65535.');
      return;
    }
    setValidationError(null);

    const stateToSave = { ...localState };
    if (stateToSave.authMethod === 'oauth') {
      stateToSave.bearerToken = '';
    } else {
      stateToSave.oauthClientId = '';
      stateToSave.oauthClientSecret = '';
    }

    setConfig(stateToSave);
    save(stateToSave);

    // Reconnect or disconnect WebSocket based on new settings
    if (localState.websocketEnabled) {
      ws.reconnect();
    } else {
      ws.disconnect();
    }

    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }, [setConfig, save, localState, ws]);

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
            maxLength={253}
          />
          <span className="hint">IP address or hostname of the CompAI - Home server</span>
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
          <div className="toggle-row">
            <label>Use HTTPS / WSS</label>
            <Switch
              checked={localState.useHTTPS}
              onChange={v => updateField('useHTTPS', v)}
              className={`toggle-switch ${localState.useHTTPS ? 'active' : ''}`}
            >
              <span className="toggle-switch-knob" />
            </Switch>
          </div>
          <span className="hint">Enable for encrypted connections (requires server TLS support)</span>
        </div>

        <div className="form-group">
          <label>Authentication Method</label>
          <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
            <button
              className={`btn ${localState.authMethod === 'bearer' ? 'btn-primary' : 'btn-secondary'}`}
              style={{ flex: 1 }}
              onClick={() => {
                if (localState.authMethod !== 'bearer') setPendingAuthSwitch('bearer');
              }}
            >
              Bearer Token
            </button>
            <button
              className={`btn ${localState.authMethod === 'oauth' ? 'btn-primary' : 'btn-secondary'}`}
              style={{ flex: 1 }}
              onClick={() => {
                if (localState.authMethod !== 'oauth') setPendingAuthSwitch('oauth');
              }}
            >
              OAuth
            </button>
          </div>
        </div>

        {pendingAuthSwitch && (
          <div
            style={{
              position: 'fixed', inset: 0, zIndex: 1000,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(4px)',
            }}
            onClick={() => setPendingAuthSwitch(null)}
          >
            <div
              style={{
                background: 'var(--color-bg-primary, #1c1c1e)',
                borderRadius: 12, padding: 24, maxWidth: 400, width: '90%',
                boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
              }}
              onClick={e => e.stopPropagation()}
            >
              <h3 style={{ margin: '0 0 8px', fontSize: 16 }}>Switch Authentication Method?</h3>
              <p style={{ margin: '0 0 20px', fontSize: 14, color: 'var(--color-text-secondary)' }}>
                Switching to <strong>{pendingAuthSwitch === 'oauth' ? 'OAuth' : 'Bearer Token'}</strong> will
                clear your current {localState.authMethod === 'oauth' ? 'OAuth client ID and secret' : 'Bearer token'}.
              </p>
              <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
                <button
                  className="btn btn-secondary"
                  onClick={() => setPendingAuthSwitch(null)}
                >
                  Cancel
                </button>
                <button
                  className="btn btn-primary"
                  onClick={() => {
                    if (pendingAuthSwitch === 'oauth') {
                      setLocalState(prev => ({ ...prev, authMethod: 'oauth', bearerToken: '' }));
                    } else {
                      setLocalState(prev => ({ ...prev, authMethod: 'bearer', oauthClientId: '', oauthClientSecret: '' }));
                    }
                    setPendingAuthSwitch(null);
                  }}
                >
                  Switch
                </button>
              </div>
            </div>
          </div>
        )}

        {localState.authMethod === 'bearer' ? (
          <div className="form-group">
            <label htmlFor="bearerToken">Bearer Token</label>
            <input
              id="bearerToken"
              type="password"
              value={localState.bearerToken}
              onChange={e => updateField('bearerToken', e.target.value)}
              placeholder="Enter your API token"
              className="form-input"
              maxLength={512}
            />
            <span className="hint">Found in the CompAI - Home app settings under API tokens</span>
          </div>
        ) : (
          <>
            <div className="form-group">
              <label htmlFor="oauthClientId">Client ID</label>
              <input
                id="oauthClientId"
                type="text"
                value={localState.oauthClientId}
                onChange={e => updateField('oauthClientId', e.target.value)}
                placeholder="Enter OAuth client ID"
                className="form-input"
                maxLength={512}
              />
            </div>
            <div className="form-group">
              <label htmlFor="oauthClientSecret">Client Secret</label>
              <input
                id="oauthClientSecret"
                type="password"
                value={localState.oauthClientSecret}
                onChange={e => updateField('oauthClientSecret', e.target.value)}
                placeholder="Enter OAuth client secret"
                className="form-input"
                maxLength={512}
              />
              <span className="hint">Generate OAuth credentials in the CompAI - Home app under Server → OAuth Credentials</span>
            </div>
          </>
        )}

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

        {validationError && (
          <div className="status-message error animate-fade-in">
            {validationError}
          </div>
        )}
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
