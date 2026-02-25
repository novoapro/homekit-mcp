import { Component, input, output, inject, ElementRef, AfterViewInit, OnDestroy } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { IconComponent } from './icon.component';
import { ThemeService } from '../../core/services/theme.service';
import { ConfigService } from '../../core/services/config.service';
import { PollingService } from '../../core/services/polling.service';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, IconComponent],
  template: `
    <!-- Backdrop -->
    @if (isOpen()) {
      <div class="sidebar-backdrop" [class.visible]="isOpen()" (click)="close()"></div>
    }

    <!-- Sidebar Panel -->
    <nav class="sidebar-panel" [class.open]="isOpen()">
      <div class="sidebar-header">
        <div class="sidebar-logo">
          <app-icon name="house" [size]="22" />
          <span>HomeKit Logs</span>
        </div>
        <button class="close-btn" (click)="close()">
          <app-icon name="xmark" [size]="18" />
        </button>
      </div>

      <div class="sidebar-nav">
        <a routerLink="/logs" routerLinkActive="active" class="nav-item" (click)="close()">
          <app-icon name="bolt-circle-fill" [size]="20" />
          <span>Logs</span>
        </a>
        <a routerLink="/workflows" routerLinkActive="active" class="nav-item" (click)="close()">
          <app-icon name="play-circle-fill" [size]="20" />
          <span>Workflows</span>
        </a>
        <a routerLink="/settings" routerLinkActive="active" class="nav-item" (click)="close()">
          <app-icon name="gear" [size]="20" />
          <span>Settings</span>
        </a>
      </div>

      <div class="sidebar-divider"></div>

      <div class="sidebar-section">
        <button class="sidebar-row" (click)="theme.toggle()">
          <app-icon [name]="theme.isDarkMode() ? 'sun' : 'moon'" [size]="20" />
          <span>{{ theme.isDarkMode() ? 'Light Mode' : 'Dark Mode' }}</span>
        </button>

        <div class="sidebar-row info-row">
          <div class="connection-indicator" [class.connected]="config.isConfigured()"></div>
          <span>{{ config.isConfigured() ? 'Connected' : 'Not configured' }}</span>
        </div>

        @if (polling.lastPollTime()) {
          <div class="sidebar-row info-row muted">
            <app-icon name="clock" [size]="16" />
            <span>Updated {{ polling.lastPollTime()!.toLocaleTimeString() }}</span>
          </div>
        }
      </div>
    </nav>
  `,
  styles: [`
    .sidebar-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.4);
      z-index: 999;
      opacity: 0;
      transition: opacity 0.3s ease;
      -webkit-tap-highlight-color: transparent;
    }

    .sidebar-backdrop.visible {
      opacity: 1;
    }

    .sidebar-panel {
      position: fixed;
      top: 0;
      left: 0;
      bottom: 0;
      width: 280px;
      max-width: 80vw;
      background: var(--bg-content);
      z-index: 1000;
      transform: translateX(-100%);
      transition: transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94);
      display: flex;
      flex-direction: column;
      box-shadow: var(--shadow-dropdown);
      overflow-y: auto;
      -webkit-overflow-scrolling: touch;
    }

    .sidebar-panel.open {
      transform: translateX(0);
    }

    .sidebar-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: var(--spacing-md) var(--spacing-lg);
      padding-top: calc(var(--spacing-md) + env(safe-area-inset-top, 0px));
      border-bottom: 1px solid var(--border-color);
    }

    .sidebar-logo {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      color: var(--tint-main);
      font-size: var(--font-size-lg);
      font-weight: var(--font-weight-bold);
    }

    .sidebar-logo span {
      color: var(--text-primary);
    }

    .close-btn {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 32px;
      height: 32px;
      border-radius: var(--radius-sm);
      color: var(--text-secondary);
      cursor: pointer;
      transition: all var(--transition-fast);
    }

    .close-btn:hover {
      background: var(--bg-hover);
      color: var(--text-primary);
    }

    .sidebar-nav {
      padding: var(--spacing-sm) 0;
    }

    .nav-item {
      display: flex;
      align-items: center;
      gap: var(--spacing-md);
      padding: 12px var(--spacing-lg);
      font-size: var(--font-size-base);
      font-weight: var(--font-weight-medium);
      color: var(--text-secondary);
      text-decoration: none;
      transition: all var(--transition-fast);
      -webkit-tap-highlight-color: transparent;
    }

    .nav-item:hover {
      background: var(--bg-hover);
      color: var(--text-primary);
    }

    .nav-item.active {
      color: var(--tint-main);
      background: color-mix(in srgb, var(--tint-main) 10%, transparent);
    }

    .sidebar-divider {
      height: 1px;
      background: var(--border-color);
      margin: var(--spacing-xs) var(--spacing-lg);
    }

    .sidebar-section {
      padding: var(--spacing-sm) 0;
    }

    .sidebar-row {
      display: flex;
      align-items: center;
      gap: var(--spacing-md);
      padding: 10px var(--spacing-lg);
      font-size: var(--font-size-sm);
      color: var(--text-secondary);
      width: 100%;
      cursor: pointer;
      transition: all var(--transition-fast);
      -webkit-tap-highlight-color: transparent;
      background: none;
      border: none;
      text-align: left;
    }

    .sidebar-row:hover {
      background: var(--bg-hover);
    }

    .info-row {
      cursor: default;
    }

    .info-row:hover {
      background: transparent;
    }

    .muted {
      color: var(--text-tertiary);
      font-size: var(--font-size-xs);
    }

    .connection-indicator {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--status-error);
      flex-shrink: 0;
    }

    .connection-indicator.connected {
      background: var(--status-active);
    }
  `]
})
export class SidebarComponent implements AfterViewInit, OnDestroy {
  isOpen = input.required<boolean>();
  closed = output<void>();

  protected theme = inject(ThemeService);
  protected config = inject(ConfigService);
  protected polling = inject(PollingService);
  private el = inject(ElementRef);

  private touchStartX = 0;
  private touchCurrentX = 0;
  private isSwiping = false;
  private panelEl: HTMLElement | null = null;

  private boundTouchStart = this.onTouchStart.bind(this);
  private boundTouchMove = this.onTouchMove.bind(this);
  private boundTouchEnd = this.onTouchEnd.bind(this);

  ngAfterViewInit(): void {
    this.panelEl = this.el.nativeElement.querySelector('.sidebar-panel');
    if (this.panelEl) {
      this.panelEl.addEventListener('touchstart', this.boundTouchStart, { passive: true });
      this.panelEl.addEventListener('touchmove', this.boundTouchMove, { passive: false });
      this.panelEl.addEventListener('touchend', this.boundTouchEnd, { passive: true });
    }
  }

  ngOnDestroy(): void {
    if (this.panelEl) {
      this.panelEl.removeEventListener('touchstart', this.boundTouchStart);
      this.panelEl.removeEventListener('touchmove', this.boundTouchMove);
      this.panelEl.removeEventListener('touchend', this.boundTouchEnd);
    }
  }

  close(): void {
    this.closed.emit();
  }

  private onTouchStart(e: TouchEvent): void {
    this.touchStartX = e.touches[0].clientX;
    this.touchCurrentX = this.touchStartX;
    this.isSwiping = false;
  }

  private onTouchMove(e: TouchEvent): void {
    this.touchCurrentX = e.touches[0].clientX;
    const dx = this.touchStartX - this.touchCurrentX;

    if (dx > 10) {
      this.isSwiping = true;
      e.preventDefault();
      const offset = Math.min(dx, 280);
      if (this.panelEl) {
        this.panelEl.style.transition = 'none';
        this.panelEl.style.transform = `translateX(-${offset}px)`;
      }
    }
  }

  private onTouchEnd(): void {
    if (this.panelEl) {
      this.panelEl.style.transition = '';
      this.panelEl.style.transform = '';
    }

    if (this.isSwiping) {
      const dx = this.touchStartX - this.touchCurrentX;
      if (dx > 80) {
        this.close();
      }
    }
    this.isSwiping = false;
  }
}
