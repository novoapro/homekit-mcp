import { Injectable, signal } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class MobileTopBarService {
  readonly title = signal('');
  readonly badge = signal<string | null>(null);
  readonly showLoading = signal(false);

  set(title: string, badge: string | null = null, showLoading = false): void {
    this.title.set(title);
    this.badge.set(badge);
    this.showLoading.set(showLoading);
  }

  clear(): void {
    this.title.set('');
    this.badge.set(null);
    this.showLoading.set(false);
  }
}
