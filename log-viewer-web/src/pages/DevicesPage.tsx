import { useState, useMemo, useCallback } from 'react';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { useRegisterRefresh } from '@/contexts/RefreshContext';
import { useDebounce } from '@/hooks/useDebounce';
import { Icon } from '@/components/Icon';
import { EmptyState } from '@/components/EmptyState';
import { DeviceCard } from '@/features/devices/DeviceCard';
import { SceneCard } from '@/features/devices/SceneCard';
import { DeviceFilterSheet } from '@/features/devices/DeviceFilterSheet';
import './DevicesPage.css';

type Tab = 'devices' | 'scenes';
type ReachabilityFilter = 'all' | 'reachable' | 'unreachable';

export function DevicesPage() {
  const registry = useDeviceRegistry();
  const { devices, scenes, isLoading } = registry;
  useSetTopBar('Devices', devices.length > 0 ? devices.length : null, isLoading);

  useRegisterRefresh(useCallback(async () => {
    registry.refresh();
  }, [registry]));

  const [activeTab, setActiveTab] = useState<Tab>('devices');
  const [searchText, setSearchText] = useState('');
  const [selectedRooms, setSelectedRooms] = useState<Set<string>>(new Set());
  const [selectedServiceTypes, setSelectedServiceTypes] = useState<Set<string>>(new Set());
  const [reachabilityFilter, setReachabilityFilter] = useState<ReachabilityFilter>('all');
  const [expandedDevices, setExpandedDevices] = useState<Set<string>>(new Set());
  const [sceneSearchText, setSceneSearchText] = useState('');
  const [filterSheetOpen, setFilterSheetOpen] = useState(false);

  const debouncedSearch = useDebounce(searchText, 300);
  const debouncedSceneSearch = useDebounce(sceneSearchText, 300);

  const availableRooms = useMemo(() => {
    const rooms = new Set<string>();
    for (const device of devices) {
      if (device.room) rooms.add(device.room);
    }
    return Array.from(rooms).sort();
  }, [devices]);

  const availableServiceTypes = useMemo(() => {
    const types = new Set<string>();
    for (const device of devices) {
      for (const svc of device.services) {
        types.add(svc.type);
      }
    }
    return Array.from(types).sort();
  }, [devices]);

  const filteredDevices = useMemo(() => {
    let result = devices;
    const search = debouncedSearch.toLowerCase();

    if (search) {
      result = result.filter(d =>
        d.name.toLowerCase().includes(search) ||
        (d.room && d.room.toLowerCase().includes(search)) ||
        d.services.some(s =>
          s.name.toLowerCase().includes(search) ||
          s.type.toLowerCase().includes(search)
        )
      );
    }

    if (selectedRooms.size > 0) {
      result = result.filter(d => d.room && selectedRooms.has(d.room));
    }

    if (selectedServiceTypes.size > 0) {
      result = result.filter(d =>
        d.services.some(s => selectedServiceTypes.has(s.type))
      );
    }

    if (reachabilityFilter !== 'all') {
      result = result.filter(d =>
        reachabilityFilter === 'reachable' ? d.isReachable : !d.isReachable
      );
    }

    return result;
  }, [devices, debouncedSearch, selectedRooms, selectedServiceTypes, reachabilityFilter]);

  const filteredScenes = useMemo(() => {
    if (!debouncedSceneSearch) return scenes;
    const search = debouncedSceneSearch.toLowerCase();
    return scenes.filter(s => s.name.toLowerCase().includes(search));
  }, [scenes, debouncedSceneSearch]);

  const activeFilterCount = selectedRooms.size + selectedServiceTypes.size +
    (reachabilityFilter !== 'all' ? 1 : 0);

  const hasActiveFilters = searchText.length > 0 || activeFilterCount > 0;

  const clearFilters = useCallback(() => {
    setSearchText('');
    setSelectedRooms(new Set());
    setSelectedServiceTypes(new Set());
    setReachabilityFilter('all');
  }, []);

  const clearSheetFilters = useCallback(() => {
    setSelectedRooms(new Set());
    setSelectedServiceTypes(new Set());
    setReachabilityFilter('all');
  }, []);

  const toggleDevice = useCallback((deviceId: string) => {
    setExpandedDevices(prev => {
      const next = new Set(prev);
      if (next.has(deviceId)) next.delete(deviceId);
      else next.add(deviceId);
      return next;
    });
  }, []);

  const expandAll = useCallback(() => {
    setExpandedDevices(new Set(filteredDevices.map(d => d.id)));
  }, [filteredDevices]);

  const collapseAll = useCallback(() => {
    setExpandedDevices(new Set());
  }, []);

  const allExpanded = filteredDevices.length > 0 && filteredDevices.every(d => expandedDevices.has(d.id));

  return (
    <div className="devices-page">
      {/* Tab bar */}
      <div className="devices-tab-bar">
        <button
          className={`devices-tab ${activeTab === 'devices' ? 'active' : ''}`}
          onClick={() => setActiveTab('devices')}
          type="button"
        >
          <Icon name="house" size={16} />
          Devices
          <span className="devices-tab-count">{devices.length}</span>
        </button>
        <button
          className={`devices-tab ${activeTab === 'scenes' ? 'active' : ''}`}
          onClick={() => setActiveTab('scenes')}
          type="button"
        >
          <Icon name="play-circle-fill" size={16} />
          Scenes
          <span className="devices-tab-count">{scenes.length}</span>
        </button>
      </div>

      {/* Devices tab */}
      {activeTab === 'devices' && (
        <>
          <div className="devices-toolbar">
            <div className="device-filter-search">
              <Icon name="magnifying-glass" size={16} className="device-filter-search-icon" />
              <input
                type="text"
                className="device-filter-search-input"
                placeholder="Search devices..."
                value={searchText}
                onChange={e => setSearchText(e.target.value)}
              />
              {searchText && (
                <button
                  className="device-filter-search-clear"
                  onClick={() => setSearchText('')}
                  type="button"
                  aria-label="Clear search"
                >
                  <Icon name="xmark" size={14} />
                </button>
              )}
            </div>
            <button
              className={`device-filter-trigger ${activeFilterCount > 0 ? 'has-filters' : ''}`}
              onClick={() => setFilterSheetOpen(true)}
              type="button"
            >
              <Icon name="filter" size={16} />
              {activeFilterCount > 0 && (
                <span className="device-filter-badge">{activeFilterCount}</span>
              )}
            </button>
          </div>

          {/* Active filter summary */}
          {activeFilterCount > 0 && (
            <div className="devices-active-filters">
              {Array.from(selectedRooms).map(room => (
                <span key={`room-${room}`} className="active-filter-tag">
                  <Icon name="map-pin" size={12} />
                  {room}
                  <button
                    onClick={() => {
                      const next = new Set(selectedRooms);
                      next.delete(room);
                      setSelectedRooms(next);
                    }}
                    type="button"
                    aria-label={`Remove ${room} filter`}
                  >
                    <Icon name="xmark" size={10} />
                  </button>
                </span>
              ))}
              {Array.from(selectedServiceTypes).map(type => (
                <span key={`type-${type}`} className="active-filter-tag">
                  <Icon name="slider-horizontal" size={12} />
                  {type}
                  <button
                    onClick={() => {
                      const next = new Set(selectedServiceTypes);
                      next.delete(type);
                      setSelectedServiceTypes(next);
                    }}
                    type="button"
                    aria-label={`Remove ${type} filter`}
                  >
                    <Icon name="xmark" size={10} />
                  </button>
                </span>
              ))}
              {reachabilityFilter !== 'all' && (
                <span className="active-filter-tag">
                  <Icon name={reachabilityFilter === 'reachable' ? 'wifi' : 'wifi-off'} size={12} />
                  {reachabilityFilter === 'reachable' ? 'Reachable' : 'Unreachable'}
                  <button
                    onClick={() => setReachabilityFilter('all')}
                    type="button"
                    aria-label="Remove reachability filter"
                  >
                    <Icon name="xmark" size={10} />
                  </button>
                </span>
              )}
              <button className="active-filter-clear" onClick={clearFilters} type="button">
                Clear all
              </button>
            </div>
          )}

          {filteredDevices.length > 1 && (
            <div className="devices-bulk-actions">
              <button
                className="devices-bulk-btn"
                onClick={allExpanded ? collapseAll : expandAll}
                type="button"
              >
                <Icon name={allExpanded ? 'chevron-up' : 'chevron-down'} size={14} />
                {allExpanded ? 'Collapse all' : 'Expand all'}
              </button>
            </div>
          )}

          <div className="devices-list">
            {isLoading && devices.length === 0 ? (
              <div className="skeleton-list">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div key={i} className="skeleton-card" />
                ))}
              </div>
            ) : filteredDevices.length === 0 ? (
              <EmptyState
                icon={hasActiveFilters ? 'magnifying-glass' : 'house'}
                title={hasActiveFilters ? 'No matching devices' : 'No devices'}
                message={
                  hasActiveFilters
                    ? 'Try adjusting your filters'
                    : 'No HomeKit devices found. Make sure the server is running and devices are configured.'
                }
              />
            ) : (
              filteredDevices.map(device => (
                <DeviceCard
                  key={device.id}
                  device={device}
                  isExpanded={expandedDevices.has(device.id)}
                  onToggle={() => toggleDevice(device.id)}
                />
              ))
            )}
          </div>

          <DeviceFilterSheet
            isOpen={filterSheetOpen}
            availableRooms={availableRooms}
            selectedRooms={selectedRooms}
            onRoomsChange={setSelectedRooms}
            availableServiceTypes={availableServiceTypes}
            selectedServiceTypes={selectedServiceTypes}
            onServiceTypesChange={setSelectedServiceTypes}
            reachabilityFilter={reachabilityFilter}
            onReachabilityChange={setReachabilityFilter}
            onClearAll={clearSheetFilters}
            onClose={() => setFilterSheetOpen(false)}
          />
        </>
      )}

      {/* Scenes tab */}
      {activeTab === 'scenes' && (
        <>
          <div className="devices-toolbar">
            <div className="device-filter-search">
              <Icon name="magnifying-glass" size={16} className="device-filter-search-icon" />
              <input
                type="text"
                className="device-filter-search-input"
                placeholder="Search scenes..."
                value={sceneSearchText}
                onChange={e => setSceneSearchText(e.target.value)}
              />
              {sceneSearchText && (
                <button
                  className="device-filter-search-clear"
                  onClick={() => setSceneSearchText('')}
                  type="button"
                  aria-label="Clear search"
                >
                  <Icon name="xmark" size={14} />
                </button>
              )}
            </div>
          </div>

          <div className="devices-list">
            {isLoading && scenes.length === 0 ? (
              <div className="skeleton-list">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="skeleton-card" />
                ))}
              </div>
            ) : filteredScenes.length === 0 ? (
              <EmptyState
                icon={sceneSearchText ? 'magnifying-glass' : 'play-circle-fill'}
                title={sceneSearchText ? 'No matching scenes' : 'No scenes'}
                message={
                  sceneSearchText
                    ? 'Try adjusting your search'
                    : 'No HomeKit scenes found.'
                }
              />
            ) : (
              filteredScenes.map(scene => (
                <SceneCard key={scene.id} scene={scene} />
              ))
            )}
          </div>
        </>
      )}
    </div>
  );
}
