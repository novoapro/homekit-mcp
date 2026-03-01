import { Icon } from './Icon';

interface TopBarProps {
  title: string;
  badge?: string | number | null;
  showLoading?: boolean;
  websocketEnabled: boolean;
  connectionState: 'disconnected' | 'connecting' | 'connected';
  lastPollTime: Date | null;
  onMenuClick: () => void;
}

export function TopBar({
  title,
  badge,
  showLoading = false,
  websocketEnabled,
  connectionState,
  lastPollTime,
  onMenuClick,
}: TopBarProps) {
  return (
    <header className="app-topbar">
      {/* Right: connection status indicators */}
      <div className="topbar-right">
        {websocketEnabled && (
          <div className={`status-chip ${connectionState === 'connected' ? 'status-ok' : connectionState === 'connecting' ? 'status-warn' : 'status-err'}`}>
            <span className="status-chip-label">Server </span>
            <div className={`status-dot ${connectionState === 'connected' ? 'connected' : connectionState === 'connecting' ? 'connecting' : ''}`} />
          </div>
        )}
        {lastPollTime && (
          <div className="status-chip time-update">
            <span className="status-chip-label">Updated: {lastPollTime.toLocaleTimeString()}</span>
          </div>
        )}
      </div>

      {/* Left: mobile-only controls + page title */}
      <div className="topbar-left">
        <button className="hamburger-btn" onClick={onMenuClick} aria-label="Open menu">
          <Icon name="menu" size={20} />
        </button>
        <img src="/logo.svg" alt="HomeKit MCP" className="topbar-logo" />
        <span className="topbar-title">{title}</span>
        {badge != null && <span className="topbar-badge">{badge}</span>}
        {showLoading && <span className="topbar-loading-dot" />}
      </div>
    </header>
  );
}
