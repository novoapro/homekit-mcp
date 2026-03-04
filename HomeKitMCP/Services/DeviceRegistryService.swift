import Foundation
import Combine

// MARK: - Registry Models

/// A device (accessory) entry in the registry.
struct DeviceRegistryEntry: Codable {
    let stableId: String
    var homeKitId: String?
    var hardwareKey: String?
    var name: String
    var roomName: String?
    var categoryType: String
    var services: [ServiceRegistryEntry]
    var isResolved: Bool
}

/// A service entry nested within a device entry.
struct ServiceRegistryEntry: Codable {
    let stableServiceId: String
    var homeKitServiceId: String?
    var serviceType: String
    var serviceIndex: Int
    /// Optional user-assigned name. When set, overrides the HomeKit name in all output.
    var customName: String?
    var characteristics: [CharacteristicRegistryEntry]
}

/// A characteristic entry nested within a service entry.
struct CharacteristicRegistryEntry: Codable {
    let stableCharacteristicId: String
    var homeKitCharacteristicId: String?
    var characteristicType: String
    var enabled: Bool
    var observed: Bool
}

/// A scene (action set) entry in the registry.
struct SceneRegistryEntry: Codable {
    let stableId: String
    var homeKitId: String?
    var name: String
    var isResolved: Bool
}

/// Snapshot of the full registry for persistence.
struct RegistrySnapshot: Codable {
    var devices: [String: DeviceRegistryEntry]
    var scenes: [String: SceneRegistryEntry]
}

/// Result of importing a backup registry and consolidating with local HomeKit.
struct ConsolidationResult {
    let matchedDevices: Int
    let unmatchedDevices: Int
    let newDevices: Int
    let matchedScenes: Int
    let unmatchedScenes: Int
    let newScenes: Int
}

// MARK: - Device Registry Service

/// Maintains a stable identity registry that maps app-generated stable IDs to HomeKit's device-local UUIDs.
///
/// The registry covers: devices, services, characteristics, and scenes.
/// Workflows reference stable IDs (which never change). The registry maps those to
/// HomeKit UUIDs (which can differ per device or after backup restore).
/// If HomeKit UUIDs change, update the registry once — all workflows automatically work.
actor DeviceRegistryService {

    // MARK: - State

    private var devices: [String: DeviceRegistryEntry] = [:]
    private var scenes: [String: SceneRegistryEntry] = [:]

    // Reverse lookups (built from devices/scenes)
    private var hkDeviceIdToStableId: [String: String] = [:]
    private var hkServiceIdToStableId: [String: String] = [:]
    private var hkCharIdToStableId: [String: String] = [:]
    private var hkSceneIdToStableId: [String: String] = [:]
    private var hardwareKeyToStableId: [String: String] = [:]
    private var nameKeyToStableId: [String: String] = [:]
    private var sceneNameToStableId: [String: String] = [:]

    // Thread-safe nonisolated lookups (NSLock-protected, updated after every sync).
    // These allow synchronous callers (e.g., HomeKitManager on MainActor) to resolve IDs
    // without awaiting the actor.
    //
    // SAFETY: All access to `_lookups` MUST be guarded by `syncLock`. The struct is
    // consolidated into a single `nonisolated(unsafe)` field to minimize the surface area
    // for accidental unprotected access.
    private let syncLock = NSLock()

    /// Consolidated lookup tables for bidirectional stable ↔ HomeKit ID resolution.
    private struct LookupTables {
        var stableToHkDevice: [String: String] = [:]
        var hkToStableDevice: [String: String] = [:]
        var stableToHkService: [String: String] = [:]
        var hkToStableService: [String: String] = [:]
        var stableToHkChar: [String: String] = [:]
        var hkToStableChar: [String: String] = [:]
        var stableToHkScene: [String: String] = [:]
        var hkToStableScene: [String: String] = [:]
        /// stable char ID → characteristic type string
        var stableCharToType: [String: String] = [:]
        /// "deviceStableId:charType" → stable char ID
        var deviceCharTypeToStableId: [String: String] = [:]
        /// stable char ID → enabled setting
        var stableCharEnabled: [String: Bool] = [:]
        /// stable char ID → observed setting
        var stableCharObserved: [String: Bool] = [:]
        /// stable service ID → custom name (only populated when set)
        var serviceCustomName: [String: String] = [:]
    }
    private nonisolated(unsafe) var _lookups = LookupTables()

    // MARK: - Persistence

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    // Subject broadcast when device or scene registry is synchronized
    nonisolated let registrySyncSubject = PassthroughSubject<Void, Never>()

    // MARK: - Init

    init() {
        let appDir = FileManager.appSupportDirectory
        self.fileURL = appDir.appendingPathComponent("device-registry.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.iso8601.decode(RegistrySnapshot.self, from: data) {
            self.devices = saved.devices
            self.scenes = saved.scenes
            rebuildReverseLookups()
        }
    }

    /// Testable initializer that accepts a custom file URL for persistence.
    init(fileURL: URL) {
        self.fileURL = fileURL

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.iso8601.decode(RegistrySnapshot.self, from: data) {
            self.devices = saved.devices
            self.scenes = saved.scenes
            rebuildReverseLookups()
        }
    }

    // MARK: - Sync Devices with HomeKit

    /// Synchronizes the device registry with the current HomeKit device list.
    /// Called after HomeKitManager rebuilds its device cache.
    func syncDevices(_ deviceModels: [DeviceModel]) {
        var matchedStableIds = Set<String>()

        // Detect ambiguous hardware keys
        var hwKeyCount: [String: Int] = [:]
        for device in deviceModels {
            if let key = device.hardwareKey {
                hwKeyCount[key, default: 0] += 1
            }
        }
        let ambiguousHwKeys = Set(hwKeyCount.filter { $0.value > 1 }.keys)

        for device in deviceModels {
            let stableId: String

            if let existing = hkDeviceIdToStableId[device.id] {
                // Case 1: HomeKit UUID already known
                stableId = existing
            } else if let hwKey = device.hardwareKey,
                      !ambiguousHwKeys.contains(hwKey),
                      let existing = hardwareKeyToStableId[hwKey] {
                // Case 2: UUID changed but hardware key matches
                AppLogger.registry.info("Device '\(device.name)' re-mapped via hardware key")
                stableId = existing
            } else if let existing = nameKeyToStableId[deviceNameKey(device)] {
                // Case 3: Fallback to name+room+category
                AppLogger.registry.info("Device '\(device.name)' re-mapped via name+room")
                stableId = existing
            } else {
                // Case 4: New device
                stableId = UUID().uuidString
                AppLogger.registry.info("New device registered: '\(device.name)' → \(stableId)")
            }

            matchedStableIds.insert(stableId)
            devices[stableId] = buildDeviceEntry(stableId: stableId, from: device, existing: devices[stableId])
        }

        // Mark unmatched entries as unresolved
        for (stableId, entry) in devices where !matchedStableIds.contains(stableId) {
            if entry.isResolved {
                var updated = entry
                updated.homeKitId = nil
                updated.isResolved = false
                for i in updated.services.indices {
                    updated.services[i].homeKitServiceId = nil
                    for j in updated.services[i].characteristics.indices {
                        updated.services[i].characteristics[j].homeKitCharacteristicId = nil
                    }
                }
                devices[stableId] = updated
                AppLogger.registry.warning("Device '\(entry.name)' is now unresolved")
            }
        }

        rebuildReverseLookups()
        debouncedSave()
        registrySyncSubject.send()
    }

    // MARK: - Sync Scenes with HomeKit

    /// Synchronizes the scene registry with the current HomeKit scene list.
    func syncScenes(_ sceneModels: [SceneModel]) {
        var matchedStableIds = Set<String>()

        for scene in sceneModels {
            let stableId: String

            if let existing = hkSceneIdToStableId[scene.id] {
                stableId = existing
            } else if let existing = sceneNameToStableId[scene.name.lowercased()] {
                // Scenes have no hardware key — match by name
                AppLogger.registry.info("Scene '\(scene.name)' re-mapped via name")
                stableId = existing
            } else {
                stableId = UUID().uuidString
                AppLogger.registry.info("New scene registered: '\(scene.name)' → \(stableId)")
            }

            matchedStableIds.insert(stableId)
            scenes[stableId] = SceneRegistryEntry(
                stableId: stableId,
                homeKitId: scene.id,
                name: scene.name,
                isResolved: true
            )
        }

        // Mark unmatched scenes as unresolved
        for (stableId, entry) in scenes where !matchedStableIds.contains(stableId) {
            if entry.isResolved {
                var updated = entry
                updated.homeKitId = nil
                updated.isResolved = false
                scenes[stableId] = updated
                AppLogger.registry.warning("Scene '\(entry.name)' is now unresolved")
            }
        }

        rebuildReverseLookups()
        debouncedSave()
        registrySyncSubject.send()
    }

    // MARK: - Orphan Deduplication

    struct DeduplicationResult {
        let deviceIdRemapping: [String: String]
        let serviceIdRemapping: [String: String]
        let characteristicIdRemapping: [String: String]
        let sceneIdRemapping: [String: String]
        let removedDeviceCount: Int
        let removedSceneCount: Int

        var hasChanges: Bool { removedDeviceCount > 0 || removedSceneCount > 0 }
    }

    /// Removes orphaned entries that are stale duplicates of a resolved entry (same hardware key or name+room+category).
    /// Returns a remapping table so callers can update workflow references from the removed stableId to the resolved one.
    func deduplicateOrphanedEntries() -> DeduplicationResult {
        var deviceIdRemapping: [String: String] = [:]
        var serviceIdRemapping: [String: String] = [:]
        var charIdRemapping: [String: String] = [:]
        var sceneIdRemapping: [String: String] = [:]
        var deviceIdsToRemove: [String] = []
        var sceneIdsToRemove: [String] = []

        // Build lookup from resolved device entries
        var resolvedByHwKey: [String: DeviceRegistryEntry] = [:]
        var resolvedByNameKey: [String: DeviceRegistryEntry] = [:]
        for entry in devices.values where entry.isResolved {
            if let hwKey = entry.hardwareKey {
                resolvedByHwKey[hwKey] = entry
            }
            resolvedByNameKey[deviceNameKey(entry)] = entry
        }

        // Find orphaned entries that duplicate a resolved entry
        for entry in devices.values where !entry.isResolved {
            var resolvedMatch: DeviceRegistryEntry?

            if let hwKey = entry.hardwareKey, let resolved = resolvedByHwKey[hwKey] {
                resolvedMatch = resolved
            }
            if resolvedMatch == nil {
                let nk = deviceNameKey(entry)
                if let resolved = resolvedByNameKey[nk] {
                    resolvedMatch = resolved
                }
            }

            if let resolved = resolvedMatch {
                deviceIdRemapping[entry.stableId] = resolved.stableId
                deviceIdsToRemove.append(entry.stableId)

                // Build service and characteristic remapping (match by type, prefer same index)
                var resolvedServicesByType: [String: [ServiceRegistryEntry]] = [:]
                for svc in resolved.services {
                    resolvedServicesByType[svc.serviceType, default: []].append(svc)
                }
                var consumedResolvedServiceIds = Set<String>()

                for orphanService in entry.services {
                    let candidates = resolvedServicesByType[orphanService.serviceType] ?? []
                    let unconsumed = candidates.filter { !consumedResolvedServiceIds.contains($0.stableServiceId) }
                    let resolvedService = unconsumed.first(where: { $0.serviceIndex == orphanService.serviceIndex }) ?? unconsumed.first

                    if let resolvedService {
                        consumedResolvedServiceIds.insert(resolvedService.stableServiceId)
                        serviceIdRemapping[orphanService.stableServiceId] = resolvedService.stableServiceId
                        let orphanCharsByType = Dictionary(
                            orphanService.characteristics.map { ($0.characteristicType, $0) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        let resolvedCharsByType = Dictionary(
                            resolvedService.characteristics.map { ($0.characteristicType, $0) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        for (charType, orphanChar) in orphanCharsByType {
                            if let resolvedChar = resolvedCharsByType[charType] {
                                charIdRemapping[orphanChar.stableCharacteristicId] = resolvedChar.stableCharacteristicId
                            }
                        }
                    }
                }

                AppLogger.registry.info("Dedup: removing orphaned duplicate '\(entry.name)' (\(entry.stableId)) → resolved \(resolved.stableId)")
            }
        }

        // Scene deduplication
        var resolvedScenesByName: [String: SceneRegistryEntry] = [:]
        for entry in scenes.values where entry.isResolved {
            resolvedScenesByName[entry.name.lowercased()] = entry
        }
        for entry in scenes.values where !entry.isResolved {
            if let resolved = resolvedScenesByName[entry.name.lowercased()] {
                sceneIdRemapping[entry.stableId] = resolved.stableId
                sceneIdsToRemove.append(entry.stableId)
                AppLogger.registry.info("Dedup: removing orphaned duplicate scene '\(entry.name)' (\(entry.stableId)) → resolved \(resolved.stableId)")
            }
        }

        // Apply removals
        for id in deviceIdsToRemove { devices.removeValue(forKey: id) }
        for id in sceneIdsToRemove { scenes.removeValue(forKey: id) }

        if !deviceIdsToRemove.isEmpty || !sceneIdsToRemove.isEmpty {
            rebuildReverseLookups()
            debouncedSave()
            AppLogger.registry.info("Dedup complete: removed \(deviceIdsToRemove.count) device(s), \(sceneIdsToRemove.count) scene(s)")
        }

        return DeduplicationResult(
            deviceIdRemapping: deviceIdRemapping,
            serviceIdRemapping: serviceIdRemapping,
            characteristicIdRemapping: charIdRemapping,
            sceneIdRemapping: sceneIdRemapping,
            removedDeviceCount: deviceIdsToRemove.count,
            removedSceneCount: sceneIdsToRemove.count
        )
    }

    // MARK: - Nonisolated Sync Lookups (thread-safe, for synchronous callers)

    /// Resolves a stable device ID → HomeKit UUID. Call from any thread.
    nonisolated func readHomeKitDeviceId(_ stableId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableToHkDevice[stableId]
    }

    /// Resolves a HomeKit UUID → stable device ID. Call from any thread.
    nonisolated func readStableDeviceId(_ homeKitId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.hkToStableDevice[homeKitId]
    }

    /// Resolves a stable service ID → HomeKit service UUID. Call from any thread.
    nonisolated func readHomeKitServiceId(_ stableServiceId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableToHkService[stableServiceId]
    }

    /// Resolves a HomeKit service UUID → stable service ID. Call from any thread.
    nonisolated func readStableServiceId(_ homeKitServiceId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.hkToStableService[homeKitServiceId]
    }

    /// Resolves a stable characteristic ID → HomeKit characteristic UUID. Call from any thread.
    nonisolated func readHomeKitCharacteristicId(_ stableCharId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableToHkChar[stableCharId]
    }

    /// Resolves a HomeKit characteristic UUID → stable characteristic ID. Call from any thread.
    nonisolated func readStableCharacteristicId(_ homeKitCharId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.hkToStableChar[homeKitCharId]
    }

    /// Resolves a stable characteristic ID → its HomeKit characteristic type string. Call from any thread.
    nonisolated func readCharacteristicType(forStableId stableCharId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableCharToType[stableCharId]
    }

    /// Finds the stable characteristic ID for a given device (by stable ID) and characteristic type. Call from any thread.
    nonisolated func readStableCharacteristicId(forDeviceStableId deviceStableId: String, characteristicType: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.deviceCharTypeToStableId["\(deviceStableId):\(characteristicType)"]
    }

    /// Resolves a stable scene ID → HomeKit scene UUID. Call from any thread.
    nonisolated func readHomeKitSceneId(_ stableSceneId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableToHkScene[stableSceneId]
    }

    /// Resolves a HomeKit scene UUID → stable scene ID. Call from any thread.
    nonisolated func readStableSceneId(_ homeKitSceneId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.hkToStableScene[homeKitSceneId]
    }

    /// Reads the `enabled` setting for a characteristic by stable ID. Call from any thread.
    /// Returns `true` (default) if the characteristic is not found.
    nonisolated func readEnabled(forStableCharId id: String) -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableCharEnabled[id] ?? true
    }

    /// Reads the `observed` setting for a characteristic by stable ID. Call from any thread.
    /// Returns `false` (default) if the characteristic is not found.
    nonisolated func readObserved(forStableCharId id: String) -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.stableCharObserved[id] ?? false
    }

    /// Reads enabled/observed for a characteristic by its HomeKit UUID. Call from any thread.
    /// Returns (enabled: true, observed: false) if the characteristic is not found.
    nonisolated func readCharacteristicSettings(forHomeKitCharId hkCharId: String) -> (enabled: Bool, observed: Bool) {
        syncLock.lock()
        defer { syncLock.unlock() }
        guard let stableId = _lookups.hkToStableChar[hkCharId] else { return (enabled: true, observed: false) }
        return (
            enabled: _lookups.stableCharEnabled[stableId] ?? true,
            observed: _lookups.stableCharObserved[stableId] ?? false
        )
    }

    /// Reads the custom name for a service by its stable ID. Returns nil if no custom name is set.
    nonisolated func readServiceCustomName(forStableServiceId id: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _lookups.serviceCustomName[id]
    }

    // MARK: - Characteristic Settings (actor-isolated mutators)

    /// Sets the `enabled` flag for a characteristic. When disabling, also clears `observed`.
    func setCharacteristicEnabled(stableCharId: String, enabled: Bool) {
        guard let (deviceId, svcIdx, charIdx) = findCharacteristicLocation(stableCharId: stableCharId) else { return }
        devices[deviceId]!.services[svcIdx].characteristics[charIdx].enabled = enabled
        if !enabled {
            devices[deviceId]!.services[svcIdx].characteristics[charIdx].observed = false
        }
        rebuildReverseLookups()
        debouncedSave()
        registrySyncSubject.send()
    }

    /// Sets the `observed` flag for a characteristic. Only allows `true` if `enabled` is also `true`.
    func setCharacteristicObserved(stableCharId: String, observed: Bool) {
        guard let (deviceId, svcIdx, charIdx) = findCharacteristicLocation(stableCharId: stableCharId) else { return }
        let char = devices[deviceId]!.services[svcIdx].characteristics[charIdx]
        if observed && !char.enabled { return } // Cannot observe a disabled characteristic
        devices[deviceId]!.services[svcIdx].characteristics[charIdx].observed = observed
        rebuildReverseLookups()
        debouncedSave()
        registrySyncSubject.send()
    }

    /// Sets `enabled` for all characteristics of a device.
    func setAllEnabled(deviceStableId: String, enabled: Bool) {
        guard var entry = devices[deviceStableId] else { return }
        for i in entry.services.indices {
            for j in entry.services[i].characteristics.indices {
                entry.services[i].characteristics[j].enabled = enabled
                if !enabled {
                    entry.services[i].characteristics[j].observed = false
                }
            }
        }
        devices[deviceStableId] = entry
        rebuildReverseLookups()
        debouncedSave()
        registrySyncSubject.send()
    }

    /// Sets `observed` for all notifiable characteristics of a device.
    /// Only characteristics whose type is in `notifiableCharTypes` will be affected.
    func setAllObserved(deviceStableId: String, observed: Bool, notifiableCharTypes: Set<String>) {
        guard var entry = devices[deviceStableId] else { return }
        for i in entry.services.indices {
            for j in entry.services[i].characteristics.indices {
                let char = entry.services[i].characteristics[j]
                if notifiableCharTypes.contains(char.characteristicType) && char.enabled {
                    entry.services[i].characteristics[j].observed = observed
                }
            }
        }
        devices[deviceStableId] = entry
        rebuildReverseLookups()
        debouncedSave()
        registrySyncSubject.send()
    }

    /// Returns the settings for a single characteristic.
    func getCharacteristicSettings(stableCharId: String) -> (enabled: Bool, observed: Bool)? {
        guard let (deviceId, svcIdx, charIdx) = findCharacteristicLocation(stableCharId: stableCharId) else { return nil }
        let char = devices[deviceId]!.services[svcIdx].characteristics[charIdx]
        return (enabled: char.enabled, observed: char.observed)
    }

    /// Returns all characteristic settings keyed by stable characteristic ID.
    func getAllCharacteristicSettings() -> [String: (enabled: Bool, observed: Bool)] {
        var result: [String: (enabled: Bool, observed: Bool)] = [:]
        for entry in devices.values {
            for service in entry.services {
                for char in service.characteristics {
                    result[char.stableCharacteristicId] = (enabled: char.enabled, observed: char.observed)
                }
            }
        }
        return result
    }

    /// Sets `enabled` for all characteristics matching the given HomeKit characteristic types.
    /// When disabling, also clears `observed`.
    func setBulkEnabled(forCharacteristicTypes charTypes: Set<String>, enabled: Bool) {
        var changed = false
        for (deviceId, entry) in devices {
            for svcIdx in entry.services.indices {
                for charIdx in entry.services[svcIdx].characteristics.indices {
                    let char = devices[deviceId]!.services[svcIdx].characteristics[charIdx]
                    if charTypes.contains(char.characteristicType) && char.enabled != enabled {
                        devices[deviceId]!.services[svcIdx].characteristics[charIdx].enabled = enabled
                        if !enabled {
                            devices[deviceId]!.services[svcIdx].characteristics[charIdx].observed = false
                        }
                        changed = true
                    }
                }
            }
        }
        if changed {
            rebuildReverseLookups()
            debouncedSave()
            registrySyncSubject.send()
        }
    }

    /// Sets `observed` for all characteristics matching the given HomeKit characteristic types.
    /// Only affects characteristics that are enabled and notifiable.
    func setBulkObserved(forCharacteristicTypes charTypes: Set<String>, observed: Bool, notifiableHomeKitCharIds: Set<String>) {
        var changed = false
        for (deviceId, entry) in devices {
            for svcIdx in entry.services.indices {
                for charIdx in entry.services[svcIdx].characteristics.indices {
                    let char = devices[deviceId]!.services[svcIdx].characteristics[charIdx]
                    guard charTypes.contains(char.characteristicType) else { continue }
                    guard char.enabled else { continue }
                    if let hkId = char.homeKitCharacteristicId, !notifiableHomeKitCharIds.contains(hkId) { continue }
                    if char.observed != observed {
                        devices[deviceId]!.services[svcIdx].characteristics[charIdx].observed = observed
                        changed = true
                    }
                }
            }
        }
        if changed {
            rebuildReverseLookups()
            debouncedSave()
            registrySyncSubject.send()
        }
    }

    // MARK: - Service Name Customization

    /// Sets or clears the custom name for a service. Pass nil or empty string to clear.
    func setServiceCustomName(stableServiceId: String, customName: String?) {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        for (deviceId, entry) in devices {
            for (svcIdx, service) in entry.services.enumerated() {
                if service.stableServiceId == stableServiceId {
                    devices[deviceId]!.services[svcIdx].customName = name
                    rebuildReverseLookups()
                    debouncedSave()
                    registrySyncSubject.send()
                    return
                }
            }
        }
    }

    /// Finds the location (deviceStableId, serviceIndex, characteristicIndex) of a characteristic by its stable ID.
    private func findCharacteristicLocation(stableCharId: String) -> (String, Int, Int)? {
        for (deviceId, entry) in devices {
            for (svcIdx, service) in entry.services.enumerated() {
                for (charIdx, char) in service.characteristics.enumerated() {
                    if char.stableCharacteristicId == stableCharId {
                        return (deviceId, svcIdx, charIdx)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Actor-Isolated Resolution (async)

    func resolveDeviceHomeKitId(_ stableId: String) -> String? {
        devices[stableId]?.homeKitId
    }

    func resolveServiceHomeKitId(_ stableServiceId: String) -> String? {
        for entry in devices.values {
            if let svc = entry.services.first(where: { $0.stableServiceId == stableServiceId }) {
                return svc.homeKitServiceId
            }
        }
        return nil
    }

    func resolveCharacteristicHomeKitId(_ stableCharId: String) -> String? {
        for entry in devices.values {
            for svc in entry.services {
                if let char = svc.characteristics.first(where: { $0.stableCharacteristicId == stableCharId }) {
                    return char.homeKitCharacteristicId
                }
            }
        }
        return nil
    }

    func resolveSceneHomeKitId(_ stableId: String) -> String? {
        scenes[stableId]?.homeKitId
    }

    func stableDeviceId(forHomeKitId hkId: String) -> String? {
        hkDeviceIdToStableId[hkId]
    }

    func stableServiceId(forHomeKitId hkId: String) -> String? {
        hkServiceIdToStableId[hkId]
    }

    func stableCharacteristicId(forHomeKitId hkId: String) -> String? {
        hkCharIdToStableId[hkId]
    }

    func stableSceneId(forHomeKitId hkId: String) -> String? {
        hkSceneIdToStableId[hkId]
    }

    // MARK: - Model Transformation (nonisolated, for MCP output)

    /// Filters devices to only include enabled characteristics, transforms to stable IDs,
    /// and bakes in effective permissions. This is the canonical way to get devices for any
    /// consumer (REST API, MCP tools, workflow editor, AI service).
    nonisolated func stableDevices(_ devices: [DeviceModel]) -> [DeviceModel] {
        var result: [DeviceModel] = []
        for device in devices {
            var filteredServices: [ServiceModel] = []
            for service in device.services {
                let filteredChars = service.characteristics.filter { char in
                    let settings = readCharacteristicSettings(forHomeKitCharId: char.id)
                    return settings.enabled
                }
                if !filteredChars.isEmpty {
                    filteredServices.append(ServiceModel(
                        id: service.id,
                        name: service.name,
                        type: service.type,
                        characteristics: filteredChars
                    ))
                }
            }
            if !filteredServices.isEmpty {
                result.append(DeviceModel(
                    id: device.id,
                    name: device.name,
                    roomName: device.roomName,
                    categoryType: device.categoryType,
                    services: filteredServices,
                    isReachable: device.isReachable,
                    manufacturer: device.manufacturer,
                    model: device.model,
                    serialNumber: device.serialNumber,
                    firmwareRevision: device.firmwareRevision
                ))
            }
        }
        return result.map { withStableIds($0) }
    }

    /// Returns a DeviceModel with all IDs replaced by stable registry IDs.
    /// If a mapping is not found, the original ID is preserved.
    nonisolated func withStableIds(_ device: DeviceModel) -> DeviceModel {
        let stableDeviceId = readStableDeviceId(device.id) ?? device.id
        let stableServices = device.services.map { service in
            let stableServiceId = readStableServiceId(service.id) ?? service.id
            let stableChars = service.characteristics.map { char in
                let stableCharId = readStableCharacteristicId(char.id) ?? char.id
                // Bake in effective permissions: strip notify, re-add only if observed
                let isObserved = readObserved(forStableCharId: stableCharId)
                var effectivePermissions = char.permissions.filter { $0 != "notify" }
                if isObserved {
                    effectivePermissions.append("notify")
                }
                // Convert temperature values if user prefers Fahrenheit
                let needsConversion = TemperatureConversion.isFahrenheit
                    && TemperatureConversion.isTemperatureCharacteristic(char.type)

                var convertedValue = char.value
                var convertedMin = char.minValue
                var convertedMax = char.maxValue
                var convertedStep = char.stepValue
                if needsConversion {
                    if let v = char.value?.value as? Double {
                        convertedValue = AnyCodable(TemperatureConversion.celsiusToFahrenheit(v))
                    } else if let v = char.value?.value as? Int {
                        convertedValue = AnyCodable(TemperatureConversion.celsiusToFahrenheit(Double(v)))
                    }
                    convertedMin = char.minValue.map { TemperatureConversion.celsiusToFahrenheit($0) }
                    convertedMax = char.maxValue.map { TemperatureConversion.celsiusToFahrenheit($0) }
                    convertedStep = char.stepValue.map { TemperatureConversion.convertStepFromCelsius($0) }
                }

                return CharacteristicModel(
                    id: stableCharId,
                    type: char.type,
                    value: convertedValue,
                    format: char.format,
                    units: needsConversion ? "fahrenheit" : char.units,
                    permissions: effectivePermissions,
                    minValue: convertedMin,
                    maxValue: convertedMax,
                    stepValue: convertedStep,
                    validValues: char.validValues
                )
            }
            let effectiveName: String
            if let customName = readServiceCustomName(forStableServiceId: stableServiceId) {
                effectiveName = customName
            } else if UserDefaults.standard.bool(forKey: "useServiceTypeAsName") {
                effectiveName = ServiceTypes.displayName(for: service.type)
            } else {
                effectiveName = service.name
            }
            return ServiceModel(id: stableServiceId, name: effectiveName, type: service.type, characteristics: stableChars)
        }
        return DeviceModel(
            id: stableDeviceId,
            name: device.name,
            roomName: device.roomName,
            categoryType: device.categoryType,
            services: stableServices,
            isReachable: device.isReachable,
            manufacturer: device.manufacturer,
            model: device.model,
            serialNumber: device.serialNumber,
            firmwareRevision: device.firmwareRevision
        )
    }

    /// Transforms scenes to use stable registry IDs. Canonical method for any consumer.
    nonisolated func stableScenes(_ scenes: [SceneModel]) -> [SceneModel] {
        scenes.map { withStableIds($0) }
    }

    /// Returns a SceneModel with its ID replaced by the stable registry ID.
    nonisolated func withStableIds(_ scene: SceneModel) -> SceneModel {
        let stableSceneId = readStableSceneId(scene.id) ?? scene.id
        return SceneModel(
            id: stableSceneId,
            name: scene.name,
            type: scene.type,
            isExecuting: scene.isExecuting,
            actions: scene.actions
        )
    }

    // MARK: - Query

    func allDeviceEntries() -> [DeviceRegistryEntry] { Array(devices.values) }
    func allSceneEntries() -> [SceneRegistryEntry] { Array(scenes.values) }
    func deviceEntry(for stableId: String) -> DeviceRegistryEntry? { devices[stableId] }
    func sceneEntry(for stableId: String) -> SceneRegistryEntry? { scenes[stableId] }

    func unresolvedDevices() -> [DeviceRegistryEntry] { devices.values.filter { !$0.isResolved } }
    func unresolvedScenes() -> [SceneRegistryEntry] { scenes.values.filter { !$0.isResolved } }

    /// An orphaned service reference found in a workflow.
    struct UnresolvedServiceRef: Identifiable {
        var id: String { "\(deviceStableId)-\(serviceId)-\(workflowName)-\(location)" }
        let workflowName: String
        let deviceStableId: String
        let deviceName: String
        let serviceId: String
        let location: String
        let availableServices: [ServiceRegistryEntry]
    }

    /// Returns workflow service references that point to a serviceId not present in the registry.
    /// Only checks resolved devices (unresolved devices are handled by existing orphan detection).
    func unresolvedServiceReferences(in workflows: [Workflow]) -> [UnresolvedServiceRef] {
        var results: [UnresolvedServiceRef] = []
        var seen = Set<String>()

        for workflow in workflows {
            let refs = WorkflowMigrationService.collectDeviceReferences(from: workflow)
            for ref in refs {
                guard let serviceId = ref.serviceId else { continue }
                guard let deviceEntry = devices[ref.deviceId] else { continue }
                guard deviceEntry.isResolved else { continue }

                let serviceExists = deviceEntry.services.contains { $0.stableServiceId == serviceId }
                if !serviceExists {
                    let dedupeKey = "\(ref.deviceId)-\(serviceId)"
                    guard !seen.contains(dedupeKey) else { continue }
                    seen.insert(dedupeKey)

                    results.append(UnresolvedServiceRef(
                        workflowName: workflow.name,
                        deviceStableId: ref.deviceId,
                        deviceName: deviceEntry.name,
                        serviceId: serviceId,
                        location: ref.location,
                        availableServices: deviceEntry.services
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Manual Remap & Remove

    /// Re-maps an orphaned registry entry to a different HomeKit device.
    /// Preserves the stable ID so all workflow references remain valid.
    func remapDevice(stableId: String, to device: DeviceModel) {
        guard devices[stableId] != nil else { return }
        devices[stableId] = buildDeviceEntry(stableId: stableId, from: device, existing: devices[stableId])
        rebuildReverseLookups()
        debouncedSave()
        AppLogger.registry.info("Manually remapped device '\(device.name)' → stableId \(stableId)")
    }

    /// Removes a device entry entirely from the registry.
    func removeDevice(stableId: String) {
        guard let entry = devices.removeValue(forKey: stableId) else { return }
        rebuildReverseLookups()
        debouncedSave()
        AppLogger.registry.info("Removed device '\(entry.name)' (stableId \(stableId)) from registry")
    }

    /// Re-maps an orphaned scene entry to a different HomeKit scene.
    func remapScene(stableId: String, to scene: SceneModel) {
        guard scenes[stableId] != nil else { return }
        scenes[stableId] = SceneRegistryEntry(
            stableId: stableId,
            homeKitId: scene.id,
            name: scene.name,
            isResolved: true
        )
        rebuildReverseLookups()
        debouncedSave()
        AppLogger.registry.info("Manually remapped scene '\(scene.name)' → stableId \(stableId)")
    }

    /// Removes a scene entry entirely from the registry.
    func removeScene(stableId: String) {
        guard let entry = scenes.removeValue(forKey: stableId) else { return }
        rebuildReverseLookups()
        debouncedSave()
        AppLogger.registry.info("Removed scene '\(entry.name)' (stableId \(stableId)) from registry")
    }

    /// Remaps an orphaned service stable ID to an existing service on the same device.
    /// The target service adopts the orphaned stable ID so workflow references continue to resolve.
    func remapService(
        deviceStableId: String,
        orphanedServiceId: String,
        targetServiceId: String
    ) {
        guard var entry = devices[deviceStableId] else { return }
        guard let targetIndex = entry.services.firstIndex(where: { $0.stableServiceId == targetServiceId }) else { return }

        let old = entry.services[targetIndex]
        entry.services[targetIndex] = ServiceRegistryEntry(
            stableServiceId: orphanedServiceId,
            homeKitServiceId: old.homeKitServiceId,
            serviceType: old.serviceType,
            serviceIndex: old.serviceIndex,
            customName: old.customName,
            characteristics: old.characteristics
        )

        devices[deviceStableId] = entry
        rebuildReverseLookups()
        debouncedSave()
        AppLogger.registry.info("Remapped orphaned service '\(orphanedServiceId)' → service '\(old.serviceType)' on device '\(entry.name)'")
    }

    // MARK: - Workflow Reconciliation

    /// Reconciles foreign stable IDs in workflows against the local registry.
    ///
    /// When workflows arrive from another device (CloudKit sync) or from a backup,
    /// they may contain stable IDs that don't exist in this device's registry.
    /// This method creates local registry entries for those foreign IDs by:
    /// 1. Matching by name against current HomeKit devices/scenes
    /// 2. Creating resolved entries for matches (foreign stableId → local HomeKit UUID)
    /// 3. Creating unresolved entries for non-matches (shows in orphan UI)
    ///
    /// Returns the number of new entries created.
    @discardableResult
    func reconcileWorkflowReferences(
        _ workflows: [Workflow],
        currentDevices: [DeviceModel],
        currentScenes: [SceneModel]
    ) -> Int {
        var created = 0

        // Build lookup tables for name-based matching
        let devicesByName = buildNameRoomLookup(currentDevices)
        let scenesByName = buildSceneNameLookup(currentScenes)

        // Collect all device and scene references from workflows
        for workflow in workflows {
            let deviceRefs = WorkflowMigrationService.collectDeviceReferences(from: workflow)
            let sceneRefs = WorkflowMigrationService.collectSceneReferences(from: workflow)

            for ref in deviceRefs {
                let id = ref.deviceId
                guard !id.isEmpty, devices[id] == nil else { continue }
                // Also skip if this ID is a known HomeKit UUID (already has a stable entry)
                guard hkDeviceIdToStableId[id] == nil else { continue }

                // Try to match by name+room, then name-only
                if let match = findDeviceMatch(name: ref.contextName, room: ref.contextRoom, in: currentDevices, lookup: devicesByName) {
                    devices[id] = buildDeviceEntry(stableId: id, from: match, existing: nil)
                    AppLogger.registry.info("Reconciled device '\(match.name)' → foreign stableId \(id)")
                } else {
                    // Create unresolved entry with available metadata
                    devices[id] = DeviceRegistryEntry(
                        stableId: id,
                        homeKitId: nil,
                        hardwareKey: nil,
                        name: ref.contextName ?? "Unknown Device",
                        roomName: ref.contextRoom,
                        categoryType: "other",
                        services: [],
                        isResolved: false
                    )
                    AppLogger.registry.warning("Unresolved foreign device reference: '\(ref.contextName ?? id)'")
                }
                created += 1
            }

            for ref in sceneRefs {
                let id = ref.sceneId
                guard !id.isEmpty, scenes[id] == nil else { continue }
                guard hkSceneIdToStableId[id] == nil else { continue }

                if let name = ref.sceneName, let match = scenesByName[name.lowercased()] {
                    scenes[id] = SceneRegistryEntry(
                        stableId: id,
                        homeKitId: match.id,
                        name: match.name,
                        isResolved: true
                    )
                    AppLogger.registry.info("Reconciled scene '\(match.name)' → foreign stableId \(id)")
                } else {
                    scenes[id] = SceneRegistryEntry(
                        stableId: id,
                        homeKitId: nil,
                        name: ref.sceneName ?? "Unknown Scene",
                        isResolved: false
                    )
                    AppLogger.registry.warning("Unresolved foreign scene reference: '\(ref.sceneName ?? id)'")
                }
                created += 1
            }
        }

        if created > 0 {
            rebuildReverseLookups()
            debouncedSave()
            AppLogger.registry.info("Reconciliation: created \(created) registry entries from workflow references")
        }

        return created
    }

    /// Match a device reference by name+room against current HomeKit devices.
    private func findDeviceMatch(name: String?, room: String?, in devices: [DeviceModel], lookup: [String: DeviceModel]) -> DeviceModel? {
        guard let name else { return nil }
        // Try name+room first
        if let room {
            let key = "\(name.lowercased())\0\(room.lowercased())"
            if let match = lookup[key] { return match }
        }
        // Fall back to name-only (unique match only)
        let nameMatches = devices.filter { $0.name.lowercased() == name.lowercased() }
        return nameMatches.count == 1 ? nameMatches[0] : nil
    }

    /// Build name+room → DeviceModel lookup (unique matches only).
    private func buildNameRoomLookup(_ models: [DeviceModel]) -> [String: DeviceModel] {
        var groups: [String: [DeviceModel]] = [:]
        for device in models {
            let key = "\(device.name.lowercased())\0\((device.roomName ?? "").lowercased())"
            groups[key, default: []].append(device)
        }
        return groups.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    /// Build sceneName → SceneModel lookup (unique matches only).
    private func buildSceneNameLookup(_ models: [SceneModel]) -> [String: SceneModel] {
        var groups: [String: [SceneModel]] = [:]
        for scene in models {
            groups[scene.name.lowercased(), default: []].append(scene)
        }
        return groups.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    /// Returns the full registry snapshot (for backup/export).
    func snapshot() -> RegistrySnapshot {
        RegistrySnapshot(devices: devices, scenes: scenes)
    }

    /// Replaces the entire registry from a snapshot (for restore/import).
    func restore(from snapshot: RegistrySnapshot) {
        devices = snapshot.devices
        scenes = snapshot.scenes
        rebuildReverseLookups()
        saveNow()
    }

    // MARK: - Backup Import & Consolidation

    /// Imports a backup registry and consolidates it with the current HomeKit state.
    ///
    /// 1. Replaces the current registry with the backup snapshot
    /// 2. Clears all HomeKit UUIDs (they're from the source machine)
    /// 3. Matches each backup entry against local HomeKit devices by:
    ///    - Hardware key (manufacturer:model:serial) — unambiguous only
    ///    - Name + room + category — unique matches only
    /// 4. Updates HomeKit UUIDs for matched entries
    /// 5. Marks unmatched entries as `isResolved = false`
    /// 6. Adds local HomeKit devices not in the backup as new entries
    /// 7. Same for scenes (matched by name)
    func importAndConsolidate(
        _ backupSnapshot: RegistrySnapshot,
        currentDevices: [DeviceModel],
        currentScenes: [SceneModel]
    ) -> ConsolidationResult {
        // Step 1: Replace registry with backup
        devices = backupSnapshot.devices
        scenes = backupSnapshot.scenes

        // Step 2: Clear HomeKit UUIDs (they're from the source machine)
        for (stableId, var entry) in devices {
            entry.homeKitId = nil
            entry.isResolved = false
            for i in entry.services.indices {
                entry.services[i].homeKitServiceId = nil
                for j in entry.services[i].characteristics.indices {
                    entry.services[i].characteristics[j].homeKitCharacteristicId = nil
                }
            }
            devices[stableId] = entry
        }
        for (stableId, var entry) in scenes {
            entry.homeKitId = nil
            entry.isResolved = false
            scenes[stableId] = entry
        }

        // Step 3-4: Match backup device entries against local HomeKit devices
        var matchedDeviceCount = 0
        var matchedLocalDeviceIds = Set<String>()

        // Detect ambiguous hardware keys among LOCAL devices
        var hwKeyCount: [String: Int] = [:]
        for device in currentDevices {
            if let key = device.hardwareKey { hwKeyCount[key, default: 0] += 1 }
        }
        let ambiguousHwKeys = Set(hwKeyCount.filter { $0.value > 1 }.keys)

        // Build local lookup indices
        var localByHwKey: [String: DeviceModel] = [:]
        for device in currentDevices {
            if let key = device.hardwareKey, !ambiguousHwKeys.contains(key) {
                localByHwKey[key] = device
            }
        }

        var localNameKeyCounts: [String: Int] = [:]
        for device in currentDevices {
            localNameKeyCounts[deviceNameKey(device), default: 0] += 1
        }
        var localByNameKey: [String: DeviceModel] = [:]
        for device in currentDevices {
            let nk = deviceNameKey(device)
            if localNameKeyCounts[nk] == 1 { localByNameKey[nk] = device }
        }

        for (stableId, entry) in devices {
            var matched: DeviceModel?

            // Priority 1: Hardware key (unambiguous)
            if let hwKey = entry.hardwareKey, let local = localByHwKey[hwKey] {
                matched = local
                AppLogger.registry.info("Consolidation: '\(entry.name)' matched via hardware key")
            }

            // Priority 2: Name + room + category
            if matched == nil {
                let nk = deviceNameKey(entry)
                if let local = localByNameKey[nk] {
                    matched = local
                    AppLogger.registry.info("Consolidation: '\(entry.name)' matched via name+room")
                }
            }

            if let match = matched {
                devices[stableId] = buildDeviceEntry(stableId: stableId, from: match, existing: entry)
                matchedLocalDeviceIds.insert(match.id)
                matchedDeviceCount += 1
            }
            // Unmatched entries remain with isResolved=false from step 2
        }

        let unmatchedDeviceCount = devices.values.filter { !$0.isResolved }.count

        // Step 6: Add local HomeKit devices NOT in the backup
        var newDeviceCount = 0
        for device in currentDevices where !matchedLocalDeviceIds.contains(device.id) {
            let newStableId = UUID().uuidString
            devices[newStableId] = buildDeviceEntry(stableId: newStableId, from: device, existing: nil)
            newDeviceCount += 1
            AppLogger.registry.info("Consolidation: new local device '\(device.name)' → \(newStableId)")
        }

        // Step 7: Scenes — match by name
        var matchedSceneCount = 0
        var matchedLocalSceneIds = Set<String>()

        var sceneNameCounts: [String: Int] = [:]
        for scene in currentScenes {
            sceneNameCounts[scene.name.lowercased(), default: 0] += 1
        }
        var localScenesByName: [String: SceneModel] = [:]
        for scene in currentScenes {
            if sceneNameCounts[scene.name.lowercased()] == 1 {
                localScenesByName[scene.name.lowercased()] = scene
            }
        }

        for (stableId, entry) in scenes {
            if let local = localScenesByName[entry.name.lowercased()] {
                scenes[stableId] = SceneRegistryEntry(
                    stableId: stableId,
                    homeKitId: local.id,
                    name: local.name,
                    isResolved: true
                )
                matchedLocalSceneIds.insert(local.id)
                matchedSceneCount += 1
                AppLogger.registry.info("Consolidation: scene '\(entry.name)' matched")
            }
        }

        let unmatchedSceneCount = scenes.values.filter { !$0.isResolved }.count

        var newSceneCount = 0
        for scene in currentScenes where !matchedLocalSceneIds.contains(scene.id) {
            let newStableId = UUID().uuidString
            scenes[newStableId] = SceneRegistryEntry(
                stableId: newStableId,
                homeKitId: scene.id,
                name: scene.name,
                isResolved: true
            )
            newSceneCount += 1
            AppLogger.registry.info("Consolidation: new local scene '\(scene.name)' → \(newStableId)")
        }

        // Step 8: Rebuild and persist
        rebuildReverseLookups()
        saveNow()

        let result = ConsolidationResult(
            matchedDevices: matchedDeviceCount,
            unmatchedDevices: unmatchedDeviceCount,
            newDevices: newDeviceCount,
            matchedScenes: matchedSceneCount,
            unmatchedScenes: unmatchedSceneCount,
            newScenes: newSceneCount
        )
        AppLogger.registry.info("Consolidation complete: \(result.matchedDevices) devices matched, \(result.unmatchedDevices) unresolved, \(result.newDevices) new; \(result.matchedScenes) scenes matched, \(result.unmatchedScenes) unresolved, \(result.newScenes) new")
        return result
    }

    // MARK: - Workflow Dependency Tracking

    /// Finds all workflows that reference a given device stable ID.
    /// Returns tuples of (workflowName, locations) where locations describe where in the workflow the reference appears.
    nonisolated func findWorkflowsReferencing(
        deviceStableId: String,
        in workflows: [Workflow]
    ) -> [(workflowName: String, locations: [String])] {
        var results: [(workflowName: String, locations: [String])] = []
        for workflow in workflows {
            let refs = WorkflowMigrationService.collectDeviceReferences(from: workflow)
            let matchingLocations = refs.filter { $0.deviceId == deviceStableId }.map(\.location)
            if !matchingLocations.isEmpty {
                results.append((workflowName: workflow.name, locations: matchingLocations))
            }
        }
        return results
    }

    /// Finds all workflows that reference a given scene stable ID.
    nonisolated func findWorkflowsReferencing(
        sceneStableId: String,
        in workflows: [Workflow]
    ) -> [(workflowName: String, locations: [String])] {
        var results: [(workflowName: String, locations: [String])] = []
        for workflow in workflows {
            let refs = WorkflowMigrationService.collectSceneReferences(from: workflow)
            let matchingLocations = refs.filter { $0.sceneId == sceneStableId }.map(\.location)
            if !matchingLocations.isEmpty {
                results.append((workflowName: workflow.name, locations: matchingLocations))
            }
        }
        return results
    }

    // MARK: - Private Helpers

    private func buildDeviceEntry(stableId: String, from device: DeviceModel, existing: DeviceRegistryEntry?) -> DeviceRegistryEntry {
        // Group existing services by type (supports multiple services of same type)
        var existingServicesByType: [String: [ServiceRegistryEntry]] = [:]
        if let existing {
            for service in existing.services {
                existingServicesByType[service.serviceType, default: []].append(service)
            }
        }
        // Track consumed services to prevent double-assignment
        var consumedServiceIds = Set<String>()

        let services: [ServiceRegistryEntry] = device.services.enumerated().map { index, service in
            let candidates = existingServicesByType[service.type] ?? []
            let unconsumed = candidates.filter { !consumedServiceIds.contains($0.stableServiceId) }

            // Prefer exact index match, then fall back to first unused of same type
            let matchedService: ServiceRegistryEntry?
            if let exactIndex = unconsumed.first(where: { $0.serviceIndex == index }) {
                matchedService = exactIndex
            } else {
                matchedService = unconsumed.first
            }

            if let matched = matchedService {
                consumedServiceIds.insert(matched.stableServiceId)
            }

            // Build characteristic entries, preserving existing stable IDs by type
            let existingCharsByType: [String: CharacteristicRegistryEntry] = {
                guard let matched = matchedService else { return [:] }
                return Dictionary(uniqueKeysWithValues: matched.characteristics.map {
                    ($0.characteristicType, $0)
                })
            }()

            let chars: [CharacteristicRegistryEntry] = service.characteristics.map { char in
                if let existingChar = existingCharsByType[char.type] {
                    return CharacteristicRegistryEntry(
                        stableCharacteristicId: existingChar.stableCharacteristicId,
                        homeKitCharacteristicId: char.id,
                        characteristicType: char.type,
                        enabled: existingChar.enabled,
                        observed: existingChar.observed
                    )
                } else {
                    return CharacteristicRegistryEntry(
                        stableCharacteristicId: UUID().uuidString,
                        homeKitCharacteristicId: char.id,
                        characteristicType: char.type,
                        enabled: true,
                        observed: false
                    )
                }
            }

            return ServiceRegistryEntry(
                stableServiceId: matchedService?.stableServiceId ?? UUID().uuidString,
                homeKitServiceId: service.id,
                serviceType: service.type,
                serviceIndex: index,
                customName: matchedService?.customName,
                characteristics: chars
            )
        }

        return DeviceRegistryEntry(
            stableId: stableId,
            homeKitId: device.id,
            hardwareKey: device.hardwareKey ?? existing?.hardwareKey,
            name: device.name,
            roomName: device.roomName,
            categoryType: device.categoryType,
            services: services,
            isResolved: true
        )
    }

    private func deviceNameKey(_ device: DeviceModel) -> String {
        "\(device.name.lowercased())\0\(device.roomName?.lowercased() ?? "")\0\(device.categoryType)"
    }

    private func deviceNameKey(_ entry: DeviceRegistryEntry) -> String {
        "\(entry.name.lowercased())\0\(entry.roomName?.lowercased() ?? "")\0\(entry.categoryType)"
    }

    private func rebuildReverseLookups() {
        hkDeviceIdToStableId.removeAll()
        hkServiceIdToStableId.removeAll()
        hkCharIdToStableId.removeAll()
        hkSceneIdToStableId.removeAll()
        hardwareKeyToStableId.removeAll()
        nameKeyToStableId.removeAll()
        sceneNameToStableId.removeAll()

        // Track ambiguous hardware keys and name keys
        var hwKeyCounts: [String: Int] = [:]
        var nameKeyCounts: [String: Int] = [:]
        for entry in devices.values {
            if let hwKey = entry.hardwareKey { hwKeyCounts[hwKey, default: 0] += 1 }
            nameKeyCounts[deviceNameKey(entry), default: 0] += 1
        }

        for entry in devices.values {
            if let hkId = entry.homeKitId {
                hkDeviceIdToStableId[hkId] = entry.stableId
            }
            if let hwKey = entry.hardwareKey, hwKeyCounts[hwKey] == 1 {
                hardwareKeyToStableId[hwKey] = entry.stableId
            }
            let nk = deviceNameKey(entry)
            if nameKeyCounts[nk] == 1 {
                nameKeyToStableId[nk] = entry.stableId
            }

            for service in entry.services {
                if let hkId = service.homeKitServiceId {
                    hkServiceIdToStableId[hkId] = service.stableServiceId
                }
                for char in service.characteristics {
                    if let hkId = char.homeKitCharacteristicId {
                        hkCharIdToStableId[hkId] = char.stableCharacteristicId
                    }
                }
            }
        }

        // Scene lookups
        var sceneNameCounts: [String: Int] = [:]
        for entry in scenes.values {
            sceneNameCounts[entry.name.lowercased(), default: 0] += 1
        }
        for entry in scenes.values {
            if let hkId = entry.homeKitId {
                hkSceneIdToStableId[hkId] = entry.stableId
            }
            let key = entry.name.lowercased()
            if sceneNameCounts[key] == 1 {
                sceneNameToStableId[key] = entry.stableId
            }
        }

        // Build new lookup tables on the actor, then swap atomically under the lock.
        var newLookups = LookupTables()

        // Reverse lookups: homeKitId → stableId
        newLookups.hkToStableDevice = hkDeviceIdToStableId
        newLookups.hkToStableService = hkServiceIdToStableId
        newLookups.hkToStableChar = hkCharIdToStableId
        newLookups.hkToStableScene = hkSceneIdToStableId

        // Forward lookups: stableId → homeKitId
        for entry in devices.values {
            if let hkId = entry.homeKitId {
                newLookups.stableToHkDevice[entry.stableId] = hkId
            }
            for svc in entry.services {
                if let hkId = svc.homeKitServiceId {
                    newLookups.stableToHkService[svc.stableServiceId] = hkId
                }
                if let name = svc.customName {
                    newLookups.serviceCustomName[svc.stableServiceId] = name
                }
                for char in svc.characteristics {
                    if let hkId = char.homeKitCharacteristicId {
                        newLookups.stableToHkChar[char.stableCharacteristicId] = hkId
                    }
                    newLookups.stableCharToType[char.stableCharacteristicId] = char.characteristicType
                    newLookups.deviceCharTypeToStableId["\(entry.stableId):\(char.characteristicType)"] = char.stableCharacteristicId
                    newLookups.stableCharEnabled[char.stableCharacteristicId] = char.enabled
                    newLookups.stableCharObserved[char.stableCharacteristicId] = char.observed
                }
            }
        }
        for entry in scenes.values {
            if let hkId = entry.homeKitId {
                newLookups.stableToHkScene[entry.stableId] = hkId
            }
        }

        // Atomic swap under lock
        syncLock.lock()
        _lookups = newLookups
        syncLock.unlock()
    }

    // MARK: - Migration

    /// Migrates per-characteristic settings from the old DeviceConfigurationService format.
    /// Keys in the input map are composite "deviceHKId:serviceHKId:charHKId" strings.
    /// Maps: externalAccessEnabled → enabled, webhookEnabled → observed.
    func migrateFromDeviceConfig(_ configs: [String: (enabled: Bool, observed: Bool)]) {
        var migrated = 0
        for (key, config) in configs {
            let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            let charHKId = parts[2]
            // Find the characteristic in the registry by HomeKit ID
            guard let stableCharId = hkCharIdToStableId[charHKId],
                  let (deviceId, svcIdx, charIdx) = findCharacteristicLocation(stableCharId: stableCharId) else { continue }
            devices[deviceId]!.services[svcIdx].characteristics[charIdx].enabled = config.enabled
            devices[deviceId]!.services[svcIdx].characteristics[charIdx].observed = config.observed
            migrated += 1
        }
        if migrated > 0 {
            rebuildReverseLookups()
            saveNow()
            AppLogger.registry.info("Migrated \(migrated) characteristic settings from device-config.json into registry")
        }
    }

    /// Resets all characteristic settings by disabling everything (enabled: false, observed: false).
    func resetAllSettings() {
        for (deviceId, device) in devices {
            for svcIdx in device.services.indices {
                for charIdx in devices[deviceId]!.services[svcIdx].characteristics.indices {
                    devices[deviceId]!.services[svcIdx].characteristics[charIdx].enabled = false
                    devices[deviceId]!.services[svcIdx].characteristics[charIdx].observed = false
                }
            }
        }
        rebuildReverseLookups()
        saveNow()
        registrySyncSubject.send()
        AppLogger.registry.info("Reset all characteristic settings — all disabled")
    }

    /// Clears the entire device and scene registry. After calling this,
    /// trigger a HomeKit re-sync to re-import all devices with new stable IDs.
    func clearRegistry() {
        devices.removeAll()
        scenes.removeAll()
        rebuildReverseLookups()
        saveNow()
        registrySyncSubject.send()
        AppLogger.registry.info("Cleared entire device registry — next sync will re-import all devices")
    }

    // MARK: - Persistence

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            let snapshot = RegistrySnapshot(devices: devices, scenes: scenes)
            let data = try JSONEncoder.iso8601Pretty.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            AppLogger.registry.error("Failed to save device registry: \(error)")
        }
    }
}
