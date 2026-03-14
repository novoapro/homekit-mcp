import { useRef, useEffect, useCallback, useState } from 'react';
import { NavLink } from 'react-router';
import { Icon } from './Icon';
import { useTheme } from '@/contexts/ThemeContext';
import { useSubscription } from '@/contexts/SubscriptionContext';
import { useApi } from '@/hooks/useApi';
import type { SunEvents } from '@/lib/api';

interface SidebarProps {
  isOpen: boolean;
  collapsed: boolean;
  onClose: () => void;
  onToggleCollapse: () => void;
}

function formatSunTime(isoString: string | null): string {
  if (!isoString) return '--:--';
  const date = new Date(isoString);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function Sidebar({ isOpen, collapsed, onClose, onToggleCollapse }: SidebarProps) {
  const { isDarkMode, toggle: toggleTheme } = useTheme();
  const { isPro } = useSubscription();
  const api = useApi();
  const [sunEvents, setSunEvents] = useState<SunEvents | null>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  const touchStartX = useRef(0);
  const touchCurrentX = useRef(0);
  const isSwiping = useRef(false);

  useEffect(() => {
    let cancelled = false;
    api.getAutomationRuntime()
      .then((runtime) => {
        if (!cancelled && runtime.sunEvents.locationConfigured) {
          setSunEvents(runtime.sunEvents);
        }
      })
      .catch(() => { /* ignore - server may not be reachable */ });
    return () => { cancelled = true; };
  }, [api]);

  const handleNavClick = useCallback(() => {
    if (window.innerWidth <= 768) onClose();
  }, [onClose]);

  // Touch swipe to close (mobile)
  useEffect(() => {
    const el = sidebarRef.current;
    if (!el) return;

    const onTouchStart = (e: TouchEvent) => {
      touchStartX.current = e.touches[0]!.clientX;
      touchCurrentX.current = touchStartX.current;
      isSwiping.current = false;
    };

    const onTouchMove = (e: TouchEvent) => {
      touchCurrentX.current = e.touches[0]!.clientX;
      const dx = touchStartX.current - touchCurrentX.current;
      if (dx > 10) {
        isSwiping.current = true;
        e.preventDefault();
        const offset = Math.min(dx, 280);
        el.style.transition = 'none';
        el.style.transform = `translateX(-${offset}px)`;
      }
    };

    const onTouchEnd = () => {
      el.style.transition = '';
      el.style.transform = '';
      if (isSwiping.current) {
        const dx = touchStartX.current - touchCurrentX.current;
        if (dx > 80) onClose();
      }
      isSwiping.current = false;
    };

    el.addEventListener('touchstart', onTouchStart, { passive: true });
    el.addEventListener('touchmove', onTouchMove, { passive: false });
    el.addEventListener('touchend', onTouchEnd, { passive: true });

    return () => {
      el.removeEventListener('touchstart', onTouchStart);
      el.removeEventListener('touchmove', onTouchMove);
      el.removeEventListener('touchend', onTouchEnd);
    };
  }, [onClose]);

  const navItemClass = ({ isActive }: { isActive: boolean }) =>
    `sidebar-nav-item ${isActive ? 'active' : ''}`;

  return (
    <>
      {/* Mobile backdrop */}
      {isOpen && (
        <div className="sidebar-backdrop" onClick={onClose} />
      )}

      {/* Sidebar */}
      <nav
        ref={sidebarRef}
        className={`sidebar ${collapsed ? 'collapsed' : ''} ${isOpen ? 'mobile-open' : ''}`}
      >
        {/* Logo */}
        <div className="sidebar-logo">
          <img src="/logo-nobg.png" alt="CompAI - Home Dashboard" className="sidebar-logo-img" />
          <span className="sidebar-logo-text">CompAI - Home<br />Dashboard</span>
        </div>

        {/* Mobile close */}
        <button className="sidebar-close-btn" onClick={onClose} aria-label="Close sidebar">
          <Icon name="xmark" size={18} />
        </button>

        {/* Navigation */}
        <div className="sidebar-nav">
          <NavLink to="/devices" className={navItemClass} onClick={handleNavClick}>
            <Icon name="house" size={20} />
            <span className="sidebar-nav-label">Devices</span>
          </NavLink>
          <NavLink to="/automations" className={navItemClass} onClick={handleNavClick}>
            <Icon name="play-circle-fill" size={20} />
            <span className="sidebar-nav-label">Automation+{!isPro && <span className="pro-badge">PRO</span>}</span>
          </NavLink>
          <NavLink to="/logs" className={navItemClass} onClick={handleNavClick}>
            <Icon name="bolt-circle-fill" size={20} />
            <span className="sidebar-nav-label">Logs</span>
          </NavLink>
        </div>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Footer */}
        <div className="sidebar-footer">
          <div className="sidebar-divider" />

          {sunEvents && (
            <div className="sidebar-sun-events">
              {sunEvents.cityName && (
                <span className="sidebar-nav-label sidebar-sun-city">
                  <Icon name="map-pin" size={10} />
                  {sunEvents.cityName}
                </span>
              )}
              <div className="sidebar-sun-times">
                <div className="sidebar-sun-row">
                  <Icon name="sunrise" size={14} />
                  <span className="sidebar-sun-time">{formatSunTime(sunEvents.sunrise)}</span>
                </div>
                <div className="sidebar-sun-row">
                  <Icon name="sunset" size={14} />
                  <span className="sidebar-sun-time">{formatSunTime(sunEvents.sunset)}</span>
                </div>
              </div>
            </div>
          )}

          <button className="sidebar-nav-item sidebar-footer-item" onClick={toggleTheme}>
            <Icon name={isDarkMode ? 'sun' : 'moon'} size={20} />
            <span className="sidebar-nav-label">{isDarkMode ? 'Light Mode' : 'Dark Mode'}</span>
          </button>

          <NavLink to="/settings" className={navItemClass} onClick={handleNavClick}>
            <Icon name="gear" size={20} />
            <span className="sidebar-nav-label">Settings</span>
          </NavLink>

          <button className="sidebar-nav-item sidebar-footer-item sidebar-collapse-toggle" onClick={onToggleCollapse} aria-label="Toggle sidebar">
            <Icon name="sidebar-left" size={18} />
            <span className="sidebar-nav-label">Collapse</span>
          </button>
        </div>
      </nav>
    </>
  );
}
