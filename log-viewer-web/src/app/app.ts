import { Component, inject, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { IconComponent } from './shared/components/icon.component';
import { BottomTabBarComponent } from './shared/components/bottom-tab-bar.component';
import { SidebarComponent } from './shared/components/sidebar.component';
import { ThemeService } from './core/services/theme.service';
import { ConfigService } from './core/services/config.service';
import { PollingService } from './core/services/polling.service';
import { MobileTopBarService } from './core/services/mobile-topbar.service';
import { WebSocketService } from './core/services/websocket.service';
import { trigger, transition, style, animate, query } from '@angular/animations';

const routeAnimation = trigger('routeAnimation', [
  transition('* <=> *', [
    query(':enter', [
      style({ opacity: 0, transform: 'translateY(4px)' })
    ], { optional: true }),
    query(':leave', [
      animate('120ms ease-out', style({ opacity: 0 }))
    ], { optional: true }),
    query(':enter', [
      animate('200ms 40ms cubic-bezier(0, 0, 0.2, 1)', style({ opacity: 1, transform: 'translateY(0)' }))
    ], { optional: true }),
  ])
]);

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, IconComponent, BottomTabBarComponent, SidebarComponent],
  templateUrl: './app.html',
  styleUrl: './app.css',
  animations: [routeAnimation]
})
export class App {
  protected theme = inject(ThemeService);
  protected config = inject(ConfigService);
  protected polling = inject(PollingService);
  protected topBar = inject(MobileTopBarService);
  protected wsService = inject(WebSocketService);

  sidebarOpen = signal(false);
  sidebarCollapsed = signal(
    localStorage.getItem('hk-log-viewer:sidebar-collapsed') === 'true'
  );

  toggleSidebarCollapse(): void {
    const next = !this.sidebarCollapsed();
    this.sidebarCollapsed.set(next);
    localStorage.setItem('hk-log-viewer:sidebar-collapsed', String(next));
  }
}
