import { Component, inject } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { IconComponent } from './shared/components/icon.component';
import { BottomTabBarComponent } from './shared/components/bottom-tab-bar.component';
import { ThemeService } from './core/services/theme.service';
import { ConfigService } from './core/services/config.service';
import { PollingService } from './core/services/polling.service';
import { trigger, transition, style, animate, query } from '@angular/animations';

const routeAnimation = trigger('routeAnimation', [
  transition('* <=> *', [
    query(':enter', [
      style({ opacity: 0, transform: 'translateY(6px)' })
    ], { optional: true }),
    query(':leave', [
      animate('150ms ease-out', style({ opacity: 0 }))
    ], { optional: true }),
    query(':enter', [
      animate('250ms 50ms cubic-bezier(0, 0, 0.2, 1)', style({ opacity: 1, transform: 'translateY(0)' }))
    ], { optional: true }),
  ])
]);

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, IconComponent, BottomTabBarComponent],
  templateUrl: './app.html',
  styleUrl: './app.css',
  animations: [routeAnimation]
})
export class App {
  protected theme = inject(ThemeService);
  protected config = inject(ConfigService);
  protected polling = inject(PollingService);

  onRefresh(): void {
    this.polling.refresh();
  }
}
