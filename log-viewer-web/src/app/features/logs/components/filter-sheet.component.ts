import { Component, input, output, signal, computed } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { trigger, transition, style, animate } from '@angular/animations';
import { LogCategory, CATEGORY_META } from '../../../core/models/state-change-log.model';
import { IconComponent } from '../../../shared/components/icon.component';

@Component({
  selector: 'app-filter-sheet',
  standalone: true,
  imports: [FormsModule, IconComponent],
  template: `
    @if (isOpen()) {
      <div class="sheet-backdrop" (click)="onClose()" @fadeIn></div>
      <div class="sheet-panel" @sheetSlide>
        <div class="sheet-handle"></div>
        <div class="sheet-header">
          <h3>Filters</h3>
          <button class="close-btn" (click)="onClose()">
            <app-icon name="xmark" [size]="18" />
          </button>
        </div>

        <!-- Search -->
        <div class="sheet-section">
          <div class="search-field">
            <app-icon name="magnifying-glass" [size]="16" />
            <input
              type="text"
              placeholder="Search logs..."
              [ngModel]="searchText()"
              (ngModelChange)="searchTextChange.emit($event)"
            />
          </div>
        </div>

        <!-- Categories -->
        <div class="sheet-section">
          <label class="sheet-label">Category</label>
          <div class="chip-grid">
            @for (cat of allCategories; track cat) {
              <button
                class="chip"
                [class.selected]="selectedCategories().has(cat)"
                (click)="toggleCategory(cat)"
              >
                <app-icon [name]="categoryMeta[cat].icon" [size]="14" [style.color]="selectedCategories().has(cat) ? categoryMeta[cat].color : ''" />
                <span>{{ categoryMeta[cat].label }}</span>
              </button>
            }
          </div>
        </div>

        <!-- Devices -->
        @if (availableDevices().length > 0) {
          <div class="sheet-section">
            <label class="sheet-label">Device</label>
            <div class="chip-grid">
              @for (device of availableDevices(); track device) {
                <button
                  class="chip"
                  [class.selected]="selectedDevices().has(device)"
                  (click)="toggleDevice(device)"
                >
                  <span>{{ device }}</span>
                </button>
              }
            </div>
          </div>
        }

        <!-- Date Range -->
        <div class="sheet-section">
          <label class="sheet-label">Date Range</label>
          <div class="date-row">
            <input
              type="date"
              class="date-input"
              [ngModel]="localDateFrom()"
              (ngModelChange)="localDateFrom.set($event); emitDateRange()"
              placeholder="From"
            />
            <span class="date-sep">to</span>
            <input
              type="date"
              class="date-input"
              [ngModel]="localDateTo()"
              (ngModelChange)="localDateTo.set($event); emitDateRange()"
              placeholder="To"
            />
          </div>
        </div>

        <!-- Actions -->
        <div class="sheet-actions">
          @if (hasActiveFilters()) {
            <button class="btn-clear" (click)="onClearAll()">Clear All</button>
          }
          <button class="btn-apply" (click)="onClose()">Done</button>
        </div>
      </div>
    }
  `,
  styles: [`
    .sheet-backdrop {
      position: fixed;
      inset: 0;
      background: var(--bg-overlay);
      z-index: 500;
    }

    .sheet-panel {
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      max-height: 85vh;
      background: var(--bg-content);
      border-radius: var(--radius-xl) var(--radius-xl) 0 0;
      z-index: 501;
      padding: var(--spacing-sm) var(--spacing-md) var(--spacing-xl);
      padding-bottom: calc(var(--spacing-xl) + env(safe-area-inset-bottom, 0px));
      overflow-y: auto;
      -webkit-overflow-scrolling: touch;
    }

    .sheet-handle {
      width: 36px;
      height: 4px;
      border-radius: 2px;
      background: var(--bg-pill);
      margin: 0 auto var(--spacing-md);
    }

    .sheet-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: var(--spacing-md);
    }

    .sheet-header h3 {
      font-size: var(--font-size-xl);
      font-weight: var(--font-weight-bold);
      color: var(--text-primary);
      margin: 0;
    }

    .close-btn {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 32px;
      height: 32px;
      border-radius: var(--radius-full);
      background: var(--bg-detail);
      color: var(--text-secondary);
    }

    .sheet-section {
      margin-bottom: var(--spacing-lg);
    }

    .sheet-label {
      display: block;
      font-size: var(--font-size-xs);
      font-weight: var(--font-weight-bold);
      color: var(--text-tertiary);
      text-transform: uppercase;
      letter-spacing: 0.06em;
      margin-bottom: var(--spacing-sm);
    }

    .search-field {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: 12px 14px;
      background: var(--bg-detail);
      border-radius: var(--radius-md);
      color: var(--text-tertiary);
    }

    .search-field input {
      border: none;
      background: transparent;
      outline: none;
      font-size: var(--font-size-base);
      color: var(--text-primary);
      width: 100%;
    }

    .search-field input::placeholder {
      color: var(--text-tertiary);
    }

    .chip-grid {
      display: flex;
      flex-wrap: wrap;
      gap: var(--spacing-sm);
    }

    .chip {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 8px 14px;
      border-radius: var(--radius-full);
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-medium);
      background: var(--bg-chip-inactive);
      color: var(--text-secondary);
      border: 1px solid transparent;
      transition: all 150ms ease-out;
    }

    .chip.selected {
      background: color-mix(in srgb, var(--tint-main) 15%, transparent);
      color: var(--tint-main);
      border-color: color-mix(in srgb, var(--tint-main) 30%, transparent);
    }

    .date-row {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
    }

    .date-input {
      flex: 1;
      padding: 10px 12px;
      border: 1px solid var(--border-color);
      border-radius: var(--radius-md);
      background: var(--bg-detail);
      color: var(--text-primary);
      font-size: var(--font-size-sm);
    }

    .date-sep {
      color: var(--text-tertiary);
      font-size: var(--font-size-sm);
    }

    .sheet-actions {
      display: flex;
      gap: var(--spacing-sm);
      margin-top: var(--spacing-md);
    }

    .btn-clear {
      padding: 14px 20px;
      border-radius: var(--radius-md);
      font-size: var(--font-size-base);
      font-weight: var(--font-weight-medium);
      color: var(--status-error);
      background: color-mix(in srgb, var(--status-error) 10%, transparent);
    }

    .btn-apply {
      flex: 1;
      padding: 14px;
      border-radius: var(--radius-md);
      background: var(--tint-main);
      color: white;
      font-weight: var(--font-weight-semibold);
      font-size: var(--font-size-base);
    }
  `],
  animations: [
    trigger('fadeIn', [
      transition(':enter', [style({ opacity: 0 }), animate('200ms ease-out', style({ opacity: 1 }))]),
      transition(':leave', [animate('200ms ease-out', style({ opacity: 0 }))])
    ]),
    trigger('sheetSlide', [
      transition(':enter', [style({ transform: 'translateY(100%)' }), animate('350ms cubic-bezier(0.34, 1.56, 0.64, 1)', style({ transform: 'translateY(0)' }))]),
      transition(':leave', [animate('250ms ease-in', style({ transform: 'translateY(100%)' }))])
    ])
  ]
})
export class FilterSheetComponent {
  isOpen = input.required<boolean>();
  availableDevices = input<string[]>([]);
  selectedCategories = input<Set<string>>(new Set());
  selectedDevices = input<Set<string>>(new Set());
  searchText = input('');

  closed = output<void>();
  categoriesChange = output<Set<string>>();
  devicesChange = output<Set<string>>();
  searchTextChange = output<string>();
  dateRangeChange = output<{ from: string | null; to: string | null }>();
  clearAll = output<void>();

  localDateFrom = signal('');
  localDateTo = signal('');

  readonly allCategories = Object.values(LogCategory);
  readonly categoryMeta = CATEGORY_META;

  readonly hasActiveFilters = computed(() => {
    return this.selectedCategories().size > 0 ||
      this.selectedDevices().size > 0 ||
      this.searchText() !== '' ||
      this.localDateFrom() !== '' ||
      this.localDateTo() !== '';
  });

  toggleCategory(cat: string): void {
    const current = new Set(this.selectedCategories());
    if (current.has(cat)) {
      current.delete(cat);
    } else {
      current.add(cat);
    }
    this.categoriesChange.emit(current);
  }

  toggleDevice(device: string): void {
    const current = new Set(this.selectedDevices());
    if (current.has(device)) {
      current.delete(device);
    } else {
      current.add(device);
    }
    this.devicesChange.emit(current);
  }

  emitDateRange(): void {
    this.dateRangeChange.emit({
      from: this.localDateFrom() || null,
      to: this.localDateTo() || null,
    });
  }

  onClearAll(): void {
    this.localDateFrom.set('');
    this.localDateTo.set('');
    this.clearAll.emit();
  }

  onClose(): void {
    this.closed.emit();
  }
}
