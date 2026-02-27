import { Component, input, output, signal, computed, HostListener } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { LogCategory, CATEGORY_META } from '../../../core/models/state-change-log.model';
import { IconComponent } from '../../../shared/components/icon.component';
import { FilterSheetComponent } from './filter-sheet.component';

@Component({
  selector: 'app-filter-bar',
  standalone: true,
  imports: [FormsModule, IconComponent, FilterSheetComponent],
  templateUrl: './filter-bar.component.html',
  styleUrl: './filter-bar.component.css',
})
export class FilterBarComponent {
  availableDevices = input<string[]>([]);
  availableRooms = input<string[]>([]);
  selectedCategories = input<Set<string>>(new Set());
  selectedDevices = input<Set<string>>(new Set());
  selectedRooms = input<Set<string>>(new Set());
  searchText = input('');

  logCount = input(0);

  categoriesChange = output<Set<string>>();
  devicesChange = output<Set<string>>();
  roomsChange = output<Set<string>>();
  searchTextChange = output<string>();
  dateRangeChange = output<{ from: string | null; to: string | null }>();
  clearAll = output<void>();
  clearLogs = output<void>();

  showCategoryDropdown = signal(false);
  showDeviceDropdown = signal(false);
  showRoomDropdown = signal(false);
  sheetOpen = signal(false);
  dateFrom = signal<string>('');
  dateTo = signal<string>('');
  localSearch = '';

  readonly allCategories = Object.values(LogCategory);
  readonly categoryMeta = CATEGORY_META;

  readonly hasActiveFilters = computed(() => {
    return this.selectedCategories().size > 0 ||
      this.selectedDevices().size > 0 ||
      this.selectedRooms().size > 0 ||
      this.searchText() !== '' ||
      this.dateFrom() !== '' ||
      this.dateTo() !== '';
  });

  readonly activeFilterCount = computed(() => {
    let count = 0;
    count += this.selectedCategories().size;
    count += this.selectedDevices().size;
    count += this.selectedRooms().size;
    if (this.dateFrom() || this.dateTo()) count++;
    return count;
  });

  readonly categoryLabel = computed(() => {
    const count = this.selectedCategories().size;
    if (count === 0) return 'All Categories';
    if (count === 1) return CATEGORY_META[Array.from(this.selectedCategories())[0] as LogCategory]?.label || 'Category';
    return `${count} Categories`;
  });

  readonly deviceLabel = computed(() => {
    const count = this.selectedDevices().size;
    if (count === 0) return 'All Devices';
    if (count === 1) return Array.from(this.selectedDevices())[0];
    return `${count} Devices`;
  });

  readonly roomLabel = computed(() => {
    const count = this.selectedRooms().size;
    if (count === 0) return 'All Rooms';
    if (count === 1) return Array.from(this.selectedRooms())[0];
    return `${count} Rooms`;
  });

  constructor() {
    this.localSearch = '';
  }

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

  toggleRoom(room: string): void {
    const current = new Set(this.selectedRooms());
    if (current.has(room)) {
      current.delete(room);
    } else {
      current.add(room);
    }
    this.roomsChange.emit(current);
  }

  onSearchInput(value: string): void {
    this.searchTextChange.emit(value);
  }

  onDateChange(): void {
    this.dateRangeChange.emit({
      from: this.dateFrom() || null,
      to: this.dateTo() || null,
    });
  }

  onClearAll(): void {
    this.dateFrom.set('');
    this.dateTo.set('');
    this.localSearch = '';
    this.clearAll.emit();
  }

  openSheet(): void {
    this.sheetOpen.set(true);
  }

  closeSheet(): void {
    this.sheetOpen.set(false);
  }

  readonly isAnyDropdownOpen = computed(() => this.showCategoryDropdown() || this.showDeviceDropdown() || this.showRoomDropdown());

  @HostListener('document:click')
  onDocumentClick(): void {
    this.closeDropdowns();
  }

  closeDropdowns(): void {
    this.showCategoryDropdown.set(false);
    this.showDeviceDropdown.set(false);
    this.showRoomDropdown.set(false);
  }
}
