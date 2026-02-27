import { Component, inject, signal, computed, effect, OnInit, OnDestroy, HostListener } from '@angular/core';
import { Subscription } from 'rxjs';
import { PollingService } from '../../core/services/polling.service';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { WebSocketService } from '../../core/services/websocket.service';
import { LogFilterStateService } from '../../core/services/log-filter-state.service';
import { MobileTopBarService } from '../../core/services/mobile-topbar.service';
import { StateChangeLog, LogCategory } from '../../core/models/state-change-log.model';
import { WorkflowExecutionLog } from '../../core/models/workflow-log.model';
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
  private api = inject(ApiService);
  private config = inject(ConfigService);
  private filterState = inject(LogFilterStateService);
  private wsService = inject(WebSocketService);
  private topBar = inject(MobileTopBarService);
  private wsSub?: Subscription;
  private wsWorkflowSub?: Subscription;
  private wsClearedSub?: Subscription;
  private wsReconnectSub?: Subscription;

  private topBarEffect = effect(() => {
    this.topBar.set('Activity Log', String(this.logCount()), this.polling.isLoading());
  });

  selectedCategories = signal<Set<string>>(new Set());
  selectedDevices = signal<Set<string>>(new Set());
  selectedRooms = signal<Set<string>>(new Set());
  searchText = signal('');
  dateFrom = signal<string | null>(null);
  dateTo = signal<string | null>(null);

  private searchTimeout: ReturnType<typeof setTimeout> | undefined;

  readonly availableDevices = computed(() => {
    const devices = new Set<string>();
    for (const log of this.polling.logs()) {
      if (log.deviceName && log.deviceName !== 'REST API') {
        devices.add(log.deviceName);
      }
    }
    return Array.from(devices).sort();
  });

  readonly availableRooms = computed(() => {
    const rooms = new Set<string>();
    for (const log of this.polling.logs()) {
      if (log.roomName) {
        rooms.add(log.roomName);
      }
    }
    return Array.from(rooms).sort();
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

    // Client-side category filter — ensures WebSocket-injected logs respect the active filter
    const cats = this.selectedCategories();
    if (cats.size > 0) {
      logs = logs.filter(l => cats.has(l.category));
    }

    // Client-side date range filter — ensures WebSocket-injected logs respect the active filter
    const from = this.dateFrom();
    const to = this.dateTo();
    if (from) {
      const fromMs = new Date(from).getTime();
      logs = logs.filter(l => new Date(l.timestamp).getTime() >= fromMs);
    }
    if (to) {
      const toMs = new Date(to).getTime();
      logs = logs.filter(l => new Date(l.timestamp).getTime() <= toMs);
    }

    // Client-side device filter (already filtered server-side, but for local multi-device)
    const devices = this.selectedDevices();
    if (devices.size > 0) {
      logs = logs.filter(l => devices.has(l.deviceName));
    }

    // Room filter — only applies to logs that have a roomName
    const rooms = this.selectedRooms();
    if (rooms.size > 0) {
      logs = logs.filter(l => l.roomName && rooms.has(l.roomName));
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
      this.selectedRooms.set(saved.rooms ?? new Set());
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
    // Workflow logs: inject new entries or update in-progress ones in the main list
    this.wsWorkflowSub = this.wsService.workflowLogMessage$.subscribe(({ type, data }) => {
      const entry = this.workflowExecToStateChangeLog(data);
      if (type === 'new') {
        this.polling.injectLog(entry);
      } else {
        this.polling.updateLog(entry);
      }
    });
    this.wsClearedSub = this.wsService.logsCleared$.subscribe(() => {
      this.polling.clearAll();
    });
    this.wsReconnectSub = this.wsService.reconnected$.subscribe(() => {
      this.fetchWithFilters();
    });
  }

  ngOnDestroy(): void {
    this.saveFilterState();
    this.polling.stopPolling();
    this.wsSub?.unsubscribe();
    this.wsWorkflowSub?.unsubscribe();
    this.wsClearedSub?.unsubscribe();
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

  onRoomsChange(rooms: Set<string>): void {
    this.selectedRooms.set(rooms);
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
    this.selectedRooms.set(new Set());
    this.searchText.set('');
    this.dateFrom.set(null);
    this.dateTo.set(null);
    this.fetchWithFilters();
  }

  onClearLogs(): void {
    if (!confirm('Are you sure you want to clear all logs? This will permanently delete all activity logs and workflow execution history on the server.')) {
      return;
    }
    this.api.clearLogs().subscribe({
      next: () => {
        // Server will broadcast logs_cleared via WebSocket, but clear locally immediately for responsiveness
        this.polling.clearAll();
      },
      error: (err) => {
        this.polling.error.set(err?.message || 'Failed to clear logs');
      },
    });
  }

  onPullRefresh = (): void => {
    this.fetchWithFilters();
  };

  private saveFilterState(): void {
    this.filterState.save({
      categories: this.selectedCategories(),
      devices: this.selectedDevices(),
      rooms: this.selectedRooms(),
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

  /** Convert a WorkflowExecutionLog to a StateChangeLog for the main log list. */
  private workflowExecToStateChangeLog(e: WorkflowExecutionLog): StateChangeLog {
    const isError = e.status === 'failure' || e.status === 'cancelled';
    return {
      id: e.id,
      timestamp: e.triggeredAt,
      deviceId: e.workflowId,
      deviceName: e.workflowName,
      characteristicType: isError ? 'workflow-error' : 'workflow-execution',
      category: isError ? LogCategory.WorkflowError : LogCategory.WorkflowExecution,
      newValue: e.status,
      workflowExecution: e,
    };
  }
}
