import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { IconComponent } from './icon.component';
import { ThemeService } from '../../core/services/theme.service';
import { ConfigService } from '../../core/services/config.service';

@Component({
  selector: 'app-bottom-tab-bar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, IconComponent],
  template: `
    <nav class="bottom-tabs">
      <a routerLink="/logs" routerLinkActive="active" class="tab-item">
        <app-icon name="bolt-circle-fill" [size]="22" />
        <span class="tab-label">Logs</span>
      </a>
      <a routerLink="/workflows" routerLinkActive="active" class="tab-item">
        <app-icon name="play-circle-fill" [size]="22" />
        <span class="tab-label">Workflows</span>
      </a>
      <a routerLink="/settings" routerLinkActive="active" class="tab-item">
        <app-icon name="gear" [size]="22" />
        <span class="tab-label">Settings</span>
      </a>
    </nav>
  `,
  styles: [`
    :host {
      display: block;
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      z-index: 100;
    }

    .bottom-tabs {
      display: flex;
      align-items: stretch;
      background: var(--glass-bg);
      backdrop-filter: blur(var(--glass-blur));
      -webkit-backdrop-filter: blur(var(--glass-blur));
      border-top: 1px solid var(--glass-border);
      padding-bottom: env(safe-area-inset-bottom, 0px);
    }

    .tab-item {
      flex: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 2px;
      text-decoration: none;
      color: var(--text-tertiary);
      font-size: 10px;
      font-weight: var(--font-weight-medium);
      transition: color var(--duration-fast) ease-out;
      -webkit-tap-highlight-color: transparent;
      padding: 8px 0 6px;
      min-height: 50px;
    }

    .tab-item:hover {
      text-decoration: none;
    }

    .tab-item:active {
      animation: tapPress 200ms cubic-bezier(0.34, 1.56, 0.64, 1);
    }

    .tab-item.active {
      color: var(--tint-main);
    }

    .tab-label {
      font-size: 10px;
      letter-spacing: 0.02em;
    }

    /* Only show on mobile */
    @media (min-width: 769px) {
      :host { display: none; }
    }
  `]
})
export class BottomTabBarComponent {
  protected theme = inject(ThemeService);
  protected config = inject(ConfigService);
}
