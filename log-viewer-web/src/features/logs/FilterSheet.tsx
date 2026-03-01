import { useState, useEffect, useCallback } from 'react';
import { Icon } from '@/components/Icon';
import { LogCategory, CATEGORY_META } from '@/types/state-change-log';

interface FilterSheetProps {
  isOpen: boolean;
  selectedCategories: Set<string>;
  selectedDevices: Set<string>;
  selectedRooms: Set<string>;
  availableDevices: string[];
  availableRooms: string[];
  dateFrom: string;
  dateTo: string;
  onCategoriesChange: (cats: Set<string>) => void;
  onDevicesChange: (devices: Set<string>) => void;
  onRoomsChange: (rooms: Set<string>) => void;
  onDateRangeChange: (range: { from: string | null; to: string | null }) => void;
  onClearAll: () => void;
  onClose: () => void;
}

const allCategories = Object.values(LogCategory);

export function FilterSheet({
  isOpen,
  selectedCategories,
  selectedDevices,
  selectedRooms,
  availableDevices,
  availableRooms,
  dateFrom,
  dateTo,
  onCategoriesChange,
  onDevicesChange,
  onRoomsChange,
  onDateRangeChange,
  onClearAll,
  onClose,
}: FilterSheetProps) {
  const [localDateFrom, setLocalDateFrom] = useState(dateFrom);
  const [localDateTo, setLocalDateTo] = useState(dateTo);

  useEffect(() => {
    setLocalDateFrom(dateFrom);
    setLocalDateTo(dateTo);
  }, [dateFrom, dateTo]);

  const toggleCategory = useCallback((cat: string) => {
    const next = new Set(selectedCategories);
    if (next.has(cat)) next.delete(cat);
    else next.add(cat);
    onCategoriesChange(next);
  }, [selectedCategories, onCategoriesChange]);

  const toggleDevice = useCallback((device: string) => {
    const next = new Set(selectedDevices);
    if (next.has(device)) next.delete(device);
    else next.add(device);
    onDevicesChange(next);
  }, [selectedDevices, onDevicesChange]);

  const toggleRoom = useCallback((room: string) => {
    const next = new Set(selectedRooms);
    if (next.has(room)) next.delete(room);
    else next.add(room);
    onRoomsChange(next);
  }, [selectedRooms, onRoomsChange]);

  const handleDateFromChange = useCallback((val: string) => {
    setLocalDateFrom(val);
    onDateRangeChange({ from: val || null, to: localDateTo || null });
  }, [localDateTo, onDateRangeChange]);

  const handleDateToChange = useCallback((val: string) => {
    setLocalDateTo(val);
    onDateRangeChange({ from: localDateFrom || null, to: val || null });
  }, [localDateFrom, onDateRangeChange]);

  const handleClearAll = useCallback(() => {
    setLocalDateFrom('');
    setLocalDateTo('');
    onClearAll();
  }, [onClearAll]);

  if (!isOpen) return null;

  return (
    <>
      <div className="fs-backdrop" onClick={onClose} />
      <div className="fs-panel">
        <div className="fs-handle" />

        <div className="fs-header">
          <h3 className="fs-title">Filters</h3>
          <button className="fs-close" onClick={onClose} aria-label="Close filters">
            <Icon name="xmark" size={16} />
          </button>
        </div>

        <div className="fs-body">
          {/* Categories */}
          <div className="fs-section">
            <div className="fs-section-label">Category</div>
            <div className="fs-chip-grid">
              {allCategories.map((cat) => {
                const meta = CATEGORY_META[cat];
                const isSelected = selectedCategories.has(cat);
                return (
                  <button
                    key={cat}
                    className={`fs-chip ${isSelected ? 'selected' : ''}`}
                    onClick={() => toggleCategory(cat)}
                  >
                    <Icon
                      name={meta.icon}
                      size={14}
                      style={{ color: isSelected ? meta.color : undefined }}
                    />
                    <span>{meta.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Devices */}
          {availableDevices.length > 0 && (
            <div className="fs-section">
              <div className="fs-section-label">Device</div>
              <div className="fs-chip-grid">
                {availableDevices.map((device) => (
                  <button
                    key={device}
                    className={`fs-chip ${selectedDevices.has(device) ? 'selected' : ''}`}
                    onClick={() => toggleDevice(device)}
                  >
                    <span>{device}</span>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Rooms */}
          {availableRooms.length > 0 && (
            <div className="fs-section">
              <div className="fs-section-label">Room</div>
              <div className="fs-chip-grid">
                {availableRooms.map((room) => (
                  <button
                    key={room}
                    className={`fs-chip ${selectedRooms.has(room) ? 'selected' : ''}`}
                    onClick={() => toggleRoom(room)}
                  >
                    <span>{room}</span>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Date Range */}
          <div className="fs-section">
            <div className="fs-section-label">Date Range</div>
            <div className="fs-date-row">
              <input
                type="date"
                className="fs-date-input"
                value={localDateFrom}
                onChange={(e) => handleDateFromChange(e.target.value)}
              />
              <span className="fs-date-sep">to</span>
              <input
                type="date"
                className="fs-date-input"
                value={localDateTo}
                onChange={(e) => handleDateToChange(e.target.value)}
              />
            </div>
          </div>
        </div>

        <div className="fs-actions">
          <button className="fs-clear-btn" onClick={handleClearAll}>Clear All</button>
          <button className="fs-done-btn" onClick={onClose}>Done</button>
        </div>
      </div>
    </>
  );
}
