import { Injectable, inject, signal, DestroyRef } from '@angular/core';
import { Subscription, timer, switchMap, tap, EMPTY } from 'rxjs';
import { ApiService } from './api.service';
import { ConfigService } from './config.service';
import { StateChangeLog } from '../models/state-change-log.model';

@Injectable({ providedIn: 'root' })
export class PollingService {
  private api = inject(ApiService);
  private config = inject(ConfigService);
  private destroyRef = inject(DestroyRef);
  private pollSub?: Subscription;

  readonly isPolling = signal(false);
  readonly lastPollTime = signal<Date | null>(null);
  readonly logs = signal<StateChangeLog[]>([]);
  readonly totalCount = signal(0);
  readonly isLoading = signal(false);
  readonly error = signal<string | null>(null);

  private latestTimestamp: string | null = null;
  private isDocumentVisible = true;
  private activeParams: { categories?: string[]; device_name?: string; from?: string; to?: string } = {};

  constructor() {
    // Pause polling when tab hidden
    document.addEventListener('visibilitychange', () => {
      this.isDocumentVisible = document.visibilityState === 'visible';
    });

    this.destroyRef.onDestroy(() => this.stopPolling());
  }

  startPolling(): void {
    this.stopPolling();
    const interval = this.config.pollingInterval();
    if (interval <= 0) return;

    this.isPolling.set(true);
    this.pollSub = timer(0, interval * 1000).pipe(
      switchMap(() => {
        if (!this.isDocumentVisible) return EMPTY;
        return this.fetchLogs();
      })
    ).subscribe();
  }

  stopPolling(): void {
    this.pollSub?.unsubscribe();
    this.pollSub = undefined;
    this.isPolling.set(false);
  }

  refresh(): void {
    this.fetchLogs().subscribe();
  }

  /** Full reset + fetch (used when filters change) */
  loadFresh(params: { categories?: string[]; device_name?: string; from?: string; to?: string } = {}): void {
    this.activeParams = params;
    this.latestTimestamp = null;
    this.logs.set([]);
    this.totalCount.set(0);

    this.isLoading.set(true);
    this.error.set(null);

    this.api.getLogs({ ...params, limit: 200 }).pipe(
      tap({
        next: (res) => {
          this.logs.set(res.logs);
          this.totalCount.set(res.total);
          this.updateLatestTimestamp(res.logs);
          this.lastPollTime.set(new Date());
          this.isLoading.set(false);
        },
        error: (err) => {
          this.error.set(err?.message || 'Failed to fetch logs');
          this.isLoading.set(false);
        }
      })
    ).subscribe();
  }

  loadMore(params: { categories?: string[]; device_name?: string; from?: string; to?: string } = {}): void {
    const current = this.logs();
    this.isLoading.set(true);

    this.api.getLogs({ ...params, offset: current.length, limit: 50 }).pipe(
      tap({
        next: (res) => {
          this.logs.set([...current, ...res.logs]);
          this.totalCount.set(res.total);
          this.isLoading.set(false);
        },
        error: (err) => {
          this.error.set(err?.message || 'Failed to load more logs');
          this.isLoading.set(false);
        }
      })
    ).subscribe();
  }

  /** Merge a single log entry pushed via WebSocket into the current log list. */
  injectLog(log: StateChangeLog): void {
    const current = this.logs();
    if (current.some(l => l.id === log.id)) return;
    this.logs.set([log, ...current]);
    this.totalCount.update(c => c + 1);
    this.updateLatestTimestamp([log]);
  }

  private fetchLogs() {
    return this.api.getLogs({
      ...this.activeParams,
      ...(this.latestTimestamp ? { from: this.latestTimestamp } : {}),
      limit: 200
    }).pipe(
      tap({
        next: (res) => {
          if (this.latestTimestamp && res.logs.length > 0) {
            // Merge new logs, deduplicate by id
            const existingIds = new Set(this.logs().map(l => l.id));
            const newLogs = res.logs.filter(l => !existingIds.has(l.id));
            if (newLogs.length > 0) {
              this.logs.set([...newLogs, ...this.logs()]);
            }
          } else if (!this.latestTimestamp) {
            this.logs.set(res.logs);
          }
          this.totalCount.set(Math.max(this.totalCount(), res.total));
          this.updateLatestTimestamp(res.logs);
          this.lastPollTime.set(new Date());
          this.error.set(null);
        },
        error: (err) => {
          this.error.set(err?.message || 'Polling failed');
        }
      })
    );
  }

  private updateLatestTimestamp(logs: StateChangeLog[]): void {
    if (logs.length > 0) {
      // Logs come newest first, so first entry is the latest
      this.latestTimestamp = logs[0].timestamp;
    }
  }
}
