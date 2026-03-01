import { useState, useMemo, useRef, useEffect } from 'react';
import { Icon } from '@/components/Icon';
import { FilterSheet } from './FilterSheet';
import { LogCategory, CATEGORY_META } from '@/types/state-change-log';
import './FilterBar.css';

interface FilterBarProps {
  availableDevices: string[];
  availableRooms: string[];
  selectedCategories: Set<string>;
  selectedDevices: Set<string>;
  selectedRooms: Set<string>;
  searchText: string;
  logCount: number;
  onCategoriesChange: (cats: Set<string>) => void;
  onDevicesChange: (devices: Set<string>) => void;
  onRoomsChange: (rooms: Set<string>) => void;
  onSearchTextChange: (text: string) => void;
  onDateRangeChange: (range: { from: string | null; to: string | null }) => void;
  onClearAll: () => void;
  onClearLogs: () => void;
}

const allCategories = Object.values(LogCategory);

export function FilterBar({
  availableDevices,
  availableRooms,
  selectedCategories,
  selectedDevices,
  selectedRooms,
  searchText,
  logCount,
  onCategoriesChange,
  onDevicesChange,
  onRoomsChange,
  onSearchTextChange,
  onDateRangeChange,
  onClearAll,
  onClearLogs,
}: FilterBarProps) {
  const [showCategoryDropdown, setShowCategoryDropdown] = useState(false);
  const [showDeviceDropdown, setShowDeviceDropdown] = useState(false);
  const [showRoomDropdown, setShowRoomDropdown] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const barRef = useRef<HTMLDivElement>(null);

  const isAnyDropdownOpen = showCategoryDropdown || showDeviceDropdown || showRoomDropdown;

  const hasActiveFilters = useMemo(() => {
    return selectedCategories.size > 0 ||
      selectedDevices.size > 0 ||
      selectedRooms.size > 0 ||
      searchText !== '' ||
      dateFrom !== '' ||
      dateTo !== '';
  }, [selectedCategories, selectedDevices, selectedRooms, searchText, dateFrom, dateTo]);

  const activeFilterCount = useMemo(() => {
    let count = 0;
    count += selectedCategories.size;
    count += selectedDevices.size;
    count += selectedRooms.size;
    if (dateFrom || dateTo) count++;
    return count;
  }, [selectedCategories, selectedDevices, selectedRooms, dateFrom, dateTo]);

  const categoryLabel = useMemo(() => {
    const count = selectedCategories.size;
    if (count === 0) return 'All Categories';
    if (count === 1) {
      const first = Array.from(selectedCategories)[0] as LogCategory;
      return CATEGORY_META[first]?.label || 'Category';
    }
    return `${count} Categories`;
  }, [selectedCategories]);

  const deviceLabel = useMemo(() => {
    const count = selectedDevices.size;
    if (count === 0) return 'All Devices';
    if (count === 1) return Array.from(selectedDevices)[0];
    return `${count} Devices`;
  }, [selectedDevices]);

  const roomLabel = useMemo(() => {
    const count = selectedRooms.size;
    if (count === 0) return 'All Rooms';
    if (count === 1) return Array.from(selectedRooms)[0];
    return `${count} Rooms`;
  }, [selectedRooms]);

  function closeDropdowns() {
    setShowCategoryDropdown(false);
    setShowDeviceDropdown(false);
    setShowRoomDropdown(false);
  }

  function toggleCategory(cat: string) {
    const current = new Set(selectedCategories);
    if (current.has(cat)) current.delete(cat);
    else current.add(cat);
    onCategoriesChange(current);
  }

  function toggleDevice(device: string) {
    const current = new Set(selectedDevices);
    if (current.has(device)) current.delete(device);
    else current.add(device);
    onDevicesChange(current);
  }

  function toggleRoom(room: string) {
    const current = new Set(selectedRooms);
    if (current.has(room)) current.delete(room);
    else current.add(room);
    onRoomsChange(current);
  }

  function handleDateChange(from: string, to: string) {
    setDateFrom(from);
    setDateTo(to);
    onDateRangeChange({ from: from || null, to: to || null });
  }

  function handleClearAll() {
    setDateFrom('');
    setDateTo('');
    onClearAll();
  }

  // Close dropdowns on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (barRef.current && !barRef.current.contains(e.target as Node)) {
        closeDropdowns();
      }
    }
    document.addEventListener('click', handleClick);
    return () => document.removeEventListener('click', handleClick);
  }, []);

  return (
    <>
      {/* Backdrop */}
      {isAnyDropdownOpen && (
        <div className="dropdown-backdrop" onClick={closeDropdowns} />
      )}

      {/* Desktop inline filters */}
      <div className="filter-bar desktop-filters" ref={barRef} onClick={(e) => e.stopPropagation()}>
        {/* Category Filter */}
        <div className="filter-chip-wrapper">
          <button
            className={`filter-chip ${selectedCategories.size > 0 ? 'active' : ''}`}
            onClick={() => { setShowCategoryDropdown(!showCategoryDropdown); setShowDeviceDropdown(false); setShowRoomDropdown(false); }}
          >
            <Icon name="bolt-circle-fill" size={14} />
            <span>{categoryLabel}</span>
            <Icon name="chevron-down" size={12} />
          </button>
          {showCategoryDropdown && (
            <div className="dropdown animate-scale-in">
              {allCategories.map((cat) => (
                <button key={cat} className="dropdown-item" onClick={() => toggleCategory(cat)}>
                  <span className="check-space">
                    {selectedCategories.has(cat) && <Icon name="checkmark-circle-fill" size={16} />}
                  </span>
                  <Icon name={CATEGORY_META[cat].icon} size={16} style={{ color: CATEGORY_META[cat].color }} />
                  <span>{CATEGORY_META[cat].label}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Device Filter */}
        {availableDevices.length > 0 && (
          <div className="filter-chip-wrapper">
            <button
              className={`filter-chip ${selectedDevices.size > 0 ? 'active' : ''}`}
              onClick={() => { setShowDeviceDropdown(!showDeviceDropdown); setShowCategoryDropdown(false); setShowRoomDropdown(false); }}
            >
              <Icon name="house" size={14} />
              <span>{deviceLabel}</span>
              <Icon name="chevron-down" size={12} />
            </button>
            {showDeviceDropdown && (
              <div className="dropdown animate-scale-in">
                {availableDevices.map((device) => (
                  <button key={device} className="dropdown-item" onClick={() => toggleDevice(device)}>
                    <span className="check-space">
                      {selectedDevices.has(device) && <Icon name="checkmark-circle-fill" size={16} />}
                    </span>
                    <span>{device}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Room Filter */}
        {availableRooms.length > 0 && (
          <div className="filter-chip-wrapper">
            <button
              className={`filter-chip ${selectedRooms.size > 0 ? 'active' : ''}`}
              onClick={() => { setShowRoomDropdown(!showRoomDropdown); setShowCategoryDropdown(false); setShowDeviceDropdown(false); }}
            >
              <Icon name="map-pin" size={14} />
              <span>{roomLabel}</span>
              <Icon name="chevron-down" size={12} />
            </button>
            {showRoomDropdown && (
              <div className="dropdown animate-scale-in">
                {availableRooms.map((room) => (
                  <button key={room} className="dropdown-item" onClick={() => toggleRoom(room)}>
                    <span className="check-space">
                      {selectedRooms.has(room) && <Icon name="checkmark-circle-fill" size={16} />}
                    </span>
                    <span>{room}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Search */}
        <div className="search-input-wrapper">
          <Icon name="magnifying-glass" size={14} />
          <input
            type="text"
            className="search-input"
            placeholder="Search logs..."
            value={searchText}
            onChange={(e) => onSearchTextChange(e.target.value)}
          />
        </div>

        {/* Date Range */}
        <div className="date-range">
          <input
            type="date"
            className="date-input"
            value={dateFrom}
            onChange={(e) => handleDateChange(e.target.value, dateTo)}
            placeholder="From"
          />
          <span className="date-sep">-</span>
          <input
            type="date"
            className="date-input"
            value={dateTo}
            onChange={(e) => handleDateChange(dateFrom, e.target.value)}
            placeholder="To"
          />
        </div>

        {/* Clear Filters */}
        {hasActiveFilters && (
          <button className="clear-btn" onClick={handleClearAll}>
            <Icon name="xmark-circle-fill" size={16} />
            <span>Clear</span>
          </button>
        )}

        <div className="filter-spacer" />

        {/* Clear All Logs */}
        {logCount > 0 && (
          <button className="clear-logs-btn" onClick={onClearLogs}>
            <Icon name="trash" size={14} />
            <span>Clear Logs</span>
          </button>
        )}
      </div>

      {/* Mobile filter bar */}
      <div className="mobile-filter-bar">
        <div className="search-compact">
          <Icon name="magnifying-glass" size={14} />
          <input
            type="text"
            placeholder="Search..."
            value={searchText}
            onChange={(e) => onSearchTextChange(e.target.value)}
          />
        </div>
        <button
          className={`filter-trigger ${activeFilterCount > 0 ? 'has-filters' : ''}`}
          onClick={() => setSheetOpen(true)}
        >
          <Icon name="filter" size={16} />
          {activeFilterCount > 0 && (
            <span className="filter-badge">{activeFilterCount}</span>
          )}
        </button>
        {logCount > 0 && (
          <button className="clear-logs-trigger" onClick={onClearLogs}>
            <Icon name="trash" size={16} />
          </button>
        )}
      </div>

      <FilterSheet
        isOpen={sheetOpen}
        selectedCategories={selectedCategories}
        selectedDevices={selectedDevices}
        selectedRooms={selectedRooms}
        availableDevices={availableDevices}
        availableRooms={availableRooms}
        dateFrom={dateFrom}
        dateTo={dateTo}
        onCategoriesChange={onCategoriesChange}
        onDevicesChange={onDevicesChange}
        onRoomsChange={onRoomsChange}
        onDateRangeChange={(range) => {
          setDateFrom(range.from || '');
          setDateTo(range.to || '');
          onDateRangeChange(range);
        }}
        onClearAll={() => {
          setDateFrom('');
          setDateTo('');
          onClearAll();
        }}
        onClose={() => setSheetOpen(false)}
      />
    </>
  );
}
