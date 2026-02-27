import { Injectable } from '@angular/core';

export interface LogFilterState {
  categories: Set<string>;
  devices: Set<string>;
  rooms: Set<string>;
  searchText: string;
  dateFrom: string | null;
  dateTo: string | null;
}

@Injectable({ providedIn: 'root' })
export class LogFilterStateService {
  private state: LogFilterState | null = null;

  save(state: LogFilterState): void {
    this.state = { ...state, categories: new Set(state.categories), devices: new Set(state.devices), rooms: new Set(state.rooms) };
  }

  restore(): LogFilterState | null {
    return this.state;
  }

  clear(): void {
    this.state = null;
  }
}
