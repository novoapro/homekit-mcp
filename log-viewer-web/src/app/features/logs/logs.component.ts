import { Component, inject, signal, computed, effect, OnInit, OnDestroy, HostListener } from '@angular/core';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { PollingService } from '../../core/services/polling.service';
import { ConfigService } from '../../core/services/config.service';
import { WebSocketService } from '../../core/services/websocket.service';
import { LogFilterStateService } from '../../core/services/log-filter-state.service';
import { MobileTopBarService } from '../../core/services/mobile-topbar.service';
import { StateChangeLog } from '../../core/models/state-change-log.model';
import { FilterBarComponent } from './components/filter-bar.component';
import { LogRowComponent } from './components/log-row.component';
import { EmptyStateComponent } from '../../shared/components/empty-state.component';
import { IconComponent } from '../../shared/components/icon.component';
import { PullToRefreshDirective } from '../../shared/directives/pull-to-refresh.directive';

interface LogGroup {
  date: string;
  label: string;
  logs: StateChangeLog[];
}

@Component({
  selector: 'app-logs',
  standalone: true,
  imports: [FilterBarComponent, LogRowComponent, EmptyStateComponent, IconComponent, PullToRefreshDirective],
  templateUrl: './logs.component.html',
  styleUrl: './logs.component.css',
})
export class LogsComponent implements OnInit, OnDestroy {
  protected polling = inject(PollingService);
  private config = inject(ConfigService);
  private router = inject(Router);
  private filterState = inject(LogFilterStateService);
  private wsService = inject(WebSocketService);
  private topBar = inject(MobileTopBarService);
  private wsSub?: Subscription;
  private wsReconnectSub?: Subscription;

  private topBarEffect = effect(() => {
    this.topBar.set('Activity Log', String(this.logCount()), this.polling.isLoading());
  });

  selectedCategories = signal<Set<string>>(new Set());
  selectedDevices = signal<Set<string>>(new Set());
  searchText = signal('');
  dateFrom = signal<string | null>(null);
  dateTo = signal<string | null>(null);

  private searchTimeout: any;

  readonly availableDevices = computed(() => {
    const devices = new Set<string>();
    for (const log of this.polling.logs()) {
      if (log.deviceName && log.deviceName !== 'REST API') {
        devices.add(log.deviceName);
      }
    }
    return Array.from(devices).sort();
  });

  readonly filteredLogs = computed(() => {
    let logs = this.polling.logs();
    const search = this.searchText().toLowerCase();

    // Client-side text search
    if (search) {
      logs = logs.filter(l =>
        l.deviceName.toLowerCase().includes(search) ||
        l.characteristicType.toLowerCase().includes(search) ||
        (l.serviceName && l.serviceName.toLowerCase().includes(search)) ||
        (l.errorDetails && l.errorDetails.toLowerCase().includes(search)) ||
        (l.requestBody && l.requestBody.toLowerCase().includes(search)) ||
        (l.responseBody && l.responseBody.toLowerCase().includes(search))
      );
    }

    // Client-side device filter (already filtered server-side, but for local multi-device)
    const devices = this.selectedDevices();
    if (devices.size > 0) {
      logs = logs.filter(l => devices.has(l.deviceName));
    }

    return logs;
  });

  readonly groupedLogs = computed<LogGroup[]>(() => {
    const logs = this.filteredLogs();
    const groups = new Map<string, StateChangeLog[]>();

    for (const log of logs) {
      const date = new Date(log.timestamp);
      const dayKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
      if (!groups.has(dayKey)) {
        groups.set(dayKey, []);
      }
      groups.get(dayKey)!.push(log);
    }

    const today = new Date();
    const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayKey = `${yesterday.getFullYear()}-${String(yesterday.getMonth() + 1).padStart(2, '0')}-${String(yesterday.getDate()).padStart(2, '0')}`;

    return Array.from(groups.entries())
      .sort((a, b) => b[0].localeCompare(a[0]))
      .map(([dateKey, logs]) => {
        let label: string;
        if (dateKey === todayKey) {
          label = 'Today';
        } else if (dateKey === yesterdayKey) {
          label = 'Yesterday';
        } else {
          const d = new Date(dateKey + 'T00:00:00');
          label = d.toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' });
        }
        return { date: dateKey, label, logs };
      });
  });

  readonly logCount = computed(() => this.filteredLogs().length);
  readonly hasMore = computed(() => this.polling.logs().length < this.polling.totalCount());

  ngOnInit(): void {
    const saved = this.filterState.restore();
    if (saved) {
      this.selectedCategories.set(saved.categories);
      this.selectedDevices.set(saved.devices);
      this.searchText.set(saved.searchText);
      this.dateFrom.set(saved.dateFrom);
      this.dateTo.set(saved.dateTo);
    }
    this.fetchWithFilters();
    if (this.config.pollingInterval() > 0) {
      this.polling.startPolling();
    }

    // Connect WebSocket for real-time log updates
    if (this.config.websocketEnabled()) {
      this.wsService.connect();
    }
    this.wsSub = this.wsService.logMessage$.subscribe(log => {
      this.polling.injectLog(log);
    });
    this.wsReconnectSub = this.wsService.reconnected$.subscribe(() => {
      this.fetchWithFilters();
    });
  }

  ngOnDestroy(): void {
    this.saveFilterState();
    this.polling.stopPolling();
    this.wsSub?.unsubscribe();
    this.wsReconnectSub?.unsubscribe();
  }

  @HostListener('document:click')
  onDocumentClick(): void {
    // Close any open filter dropdowns (handled by filter-bar)
  }

  onCategoriesChange(cats: Set<string>): void {
    this.selectedCategories.set(cats);
    this.fetchWithFilters();
  }

  onDevicesChange(devices: Set<string>): void {
    this.selectedDevices.set(devices);
  }

  onSearchTextChange(text: string): void {
    clearTimeout(this.searchTimeout);
    this.searchTimeout = setTimeout(() => {
      this.searchText.set(text);
    }, 300);
  }

  onDateRangeChange(range: { from: string | null; to: string | null }): void {
    this.dateFrom.set(range.from);
    this.dateTo.set(range.to);
    this.fetchWithFilters();
  }

  onClearAll(): void {
    this.selectedCategories.set(new Set());
    this.selectedDevices.set(new Set());
    this.searchText.set('');
    this.dateFrom.set(null);
    this.dateTo.set(null);
    this.fetchWithFilters();
  }

  onNavigateToWorkflow(event: { workflowId: string; logId: string }): void {
    this.router.navigate(['/workflows', event.workflowId, event.logId]);
  }

  onPullRefresh = (): void => {
    this.fetchWithFilters();
  };

  private saveFilterState(): void {
    this.filterState.save({
      categories: this.selectedCategories(),
      devices: this.selectedDevices(),
      searchText: this.searchText(),
      dateFrom: this.dateFrom(),
      dateTo: this.dateTo(),
    });
  }

  loadMore(): void {
    this.polling.loadMore(this.buildQueryParams());
  }

  private fetchWithFilters(): void {
    this.polling.loadFresh(this.buildQueryParams());
  }

  private buildQueryParams(): { categories?: string[]; device_name?: string; from?: string; to?: string } {
    const params: { categories?: string[]; device_name?: string; from?: string; to?: string } = {};
    const cats = this.selectedCategories();
    if (cats.size > 0) {
      params.categories = Array.from(cats);
    }
    if (this.dateFrom()) {
      params.from = this.dateFrom()!;
    }
    if (this.dateTo()) {
      params.to = this.dateTo()!;
    }
    return params;
  }

  trackByLogId(_index: number, log: StateChangeLog): string {
    return log.id;
  }

  trackByGroup(_index: number, group: LogGroup): string {
    return group.date;
  }
}
