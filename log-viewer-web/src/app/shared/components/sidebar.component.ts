import { Component, input, output, inject, ElementRef, AfterViewInit, OnDestroy } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { IconComponent } from './icon.component';
import { ThemeService } from '../../core/services/theme.service';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, IconComponent],
  template: `
    <!-- Mobile backdrop -->
    @if (isOpen()) {
      <div class="sidebar-backdrop" (click)="close()"></div>
    }

    <!-- Sidebar -->
    <nav class="sidebar" [class.collapsed]="collapsed()" [class.mobile-open]="isOpen()">
      <!-- Logo -->
      <div class="sidebar-logo">
        <img src="logo.svg" alt="HomeKit MCP Dashboard" class="logo-img" />
        <span class="logo-text">HomeKit MCP<br>Dashboard</span>
      </div>

      <!-- Mobile close -->
      <button class="close-btn mobile-only" (click)="close()">
        <app-icon name="xmark" [size]="18" />
      </button>

      <!-- Navigation -->
      <div class="sidebar-nav">
        <a routerLink="/logs" routerLinkActive="active" class="nav-item" (click)="onNavClick()">
          <app-icon name="bolt-circle-fill" [size]="20" />
          <span class="nav-label">Logs</span>
        </a>
        <a routerLink="/workflows" routerLinkActive="active" class="nav-item" (click)="onNavClick()">
          <app-icon name="play-circle-fill" [size]="20" />
          <span class="nav-label">Workflows</span>
        </a>
      </div>

      <!-- Spacer -->
      <div class="sidebar-spacer"></div>

      <!-- Footer -->
      <div class="sidebar-footer">
        <div class="sidebar-divider"></div>

        <!-- Theme toggle -->
        <button class="nav-item footer-item" (click)="theme.toggle()">
          <app-icon [name]="theme.isDarkMode() ? 'sun' : 'moon'" [size]="20" />
          <span class="nav-label">{{ theme.isDarkMode() ? 'Light Mode' : 'Dark Mode' }}</span>
        </button>

        <!-- Settings -->
        <a routerLink="/settings" routerLinkActive="active" class="nav-item footer-item" (click)="onNavClick()">
          <app-icon name="gear" [size]="20" />
          <span class="nav-label">Settings</span>
        </a>

        <!-- Collapse toggle (desktop only) -->
        <button class="nav-item footer-item collapse-toggle desktop-only" (click)="toggleCollapse()">
          <app-icon name="sidebar-left" [size]="18" />
          <span class="nav-label">Collapse</span>
        </button>
      </div>
    </nav>
  `,
  styles: [`
    /* ======== Desktop: Persistent sidebar ======== */
    .sidebar {
      position: fixed;
      top: 0;
      left: 0;
      bottom: 0;
      width: var(--sidebar-width);
      background: var(--bg-content);
      border-right: none;
      box-shadow: var(--shadow-sidebar);
      display: flex;
      flex-direction: column;
      z-index: 200;
      transition: width var(--sidebar-transition);
      overflow: hidden;
    }

    .sidebar.collapsed {
      width: var(--sidebar-collapsed-width);
    }

    /* Logo */
    .sidebar-logo {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: var(--spacing-md) var(--spacing-md);
      height: 56px;
      flex-shrink: 0;
      overflow: hidden;
    }

    .logo-img {
      width: 28px;
      height: 28px;
      border-radius: 6px;
      flex-shrink: 0;
    }

    .logo-text {
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-black);
      letter-spacing: -0.02em;
      line-height: 1.2;
      color: var(--text-primary);
      overflow: hidden;
      transition: opacity 150ms ease;
    }

    .sidebar.collapsed .logo-text {
      opacity: 0;
      width: 0;
    }

    /* Close button (mobile only) */
    .close-btn {
      position: absolute;
      top: var(--spacing-md);
      right: var(--spacing-md);
      display: none;
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

    /* Navigation */
    .sidebar-nav {
      padding: var(--spacing-xs) var(--spacing-sm);
      flex-shrink: 0;
    }

    .nav-item {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 10px 14px;
      border-radius: var(--radius-md);
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-medium);
      color: var(--text-secondary);
      text-decoration: none;
      transition: all 150ms ease;
      white-space: nowrap;
      overflow: hidden;
      position: relative;
      cursor: pointer;
      margin-bottom: 2px;
      width: 100%;
      background: none;
      border: none;
      text-align: left;
      -webkit-tap-highlight-color: transparent;
    }

    .nav-item:hover {
      background: var(--bg-hover);
      color: var(--text-primary);
      text-decoration: none;
    }

    .nav-item.active {
      background: color-mix(in srgb, var(--tint-main) 10%, transparent);
      color: var(--tint-main);
    }

    .nav-item.active::before {
      content: '';
      position: absolute;
      left: 0;
      top: 6px;
      bottom: 6px;
      width: 3px;
      border-radius: 0 2px 2px 0;
      background: var(--tint-main);
    }

    .nav-label {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      transition: opacity 150ms ease;
    }

    .sidebar.collapsed .nav-label {
      opacity: 0;
      width: 0;
    }

    /* Spacer */
    .sidebar-spacer {
      flex: 1;
    }

    /* Footer */
    .sidebar-footer {
      padding: var(--spacing-xs) var(--spacing-sm);
      padding-bottom: var(--spacing-md);
      flex-shrink: 0;
    }

    .sidebar-divider {
      height: 1px;
      background: var(--border-color);
      margin: var(--spacing-xs) var(--spacing-sm) var(--spacing-sm);
    }

    .footer-item {
      font-size: var(--font-size-xs);
    }

    /* Collapsed state */
    .sidebar.collapsed .nav-item {
      justify-content: center;
      padding: 10px;
    }

    .sidebar.collapsed .sidebar-logo {
      justify-content: center;
      padding: var(--spacing-md) 0;
    }

    .sidebar.collapsed .sidebar-divider {
      margin: var(--spacing-xs) 8px var(--spacing-sm);
    }

    .sidebar.collapsed .collapse-toggle {
      justify-content: center;
    }

    /* Desktop / Mobile visibility */
    .desktop-only {
      display: flex;
    }

    .mobile-only {
      display: none;
    }

    /* ======== Mobile: Overlay sidebar ======== */
    @media (max-width: 768px) {
      .sidebar {
        transform: translateX(-100%);
        width: 280px;
        max-width: 80vw;
        box-shadow: var(--shadow-dropdown);
        z-index: 1000;
        transition: transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94);
        padding-top: env(safe-area-inset-top, 0px);
      }

      .sidebar.mobile-open {
        transform: translateX(0);
      }

      .sidebar.collapsed {
        width: 280px;
      }

      .sidebar.collapsed .nav-label {
        opacity: 1;
        width: auto;
      }

      .sidebar.collapsed .logo-text {
        opacity: 1;
        width: auto;
      }

      .sidebar.collapsed .nav-item {
        justify-content: flex-start;
        padding: 10px 12px;
      }

      .sidebar.collapsed .sidebar-logo {
        justify-content: flex-start;
        padding: var(--spacing-md);
      }

      .desktop-only {
        display: none;
      }

      .mobile-only {
        display: flex;
      }
    }

    /* Backdrop */
    .sidebar-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.4);
      z-index: 999;
      -webkit-tap-highlight-color: transparent;
      animation: fadeIn 200ms ease forwards;
    }

    @keyframes fadeIn {
      from { opacity: 0; }
      to { opacity: 1; }
    }

    @media (min-width: 769px) {
      .sidebar-backdrop {
        display: none;
      }
    }
  `]
})
export class SidebarComponent implements AfterViewInit, OnDestroy {
  isOpen = input.required<boolean>();
  collapsed = input<boolean>(false);
  closed = output<void>();
  collapseToggled = output<void>();

  protected theme = inject(ThemeService);
  private el = inject(ElementRef);

  private touchStartX = 0;
  private touchCurrentX = 0;
  private isSwiping = false;
  private panelEl: HTMLElement | null = null;

  private boundTouchStart = this.onTouchStart.bind(this);
  private boundTouchMove = this.onTouchMove.bind(this);
  private boundTouchEnd = this.onTouchEnd.bind(this);

  ngAfterViewInit(): void {
    this.panelEl = this.el.nativeElement.querySelector('.sidebar');
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

  toggleCollapse(): void {
    this.collapseToggled.emit();
  }

  onNavClick(): void {
    if (window.innerWidth <= 768) {
      this.close();
    }
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
