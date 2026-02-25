import Foundation

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
    var characteristics: [CharacteristicRegistryEntry]
}

/// A characteristic entry nested within a service entry.
struct CharacteristicRegistryEntry: Codable {
    let stableCharacteristicId: String
    var homeKitCharacteristicId: String?
    var characteristicType: String
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
    // without awaiting the actor. Marked nonisolated(unsafe) because thread safety is
    // manually managed via syncLock.
    private let syncLock = NSLock()
    private nonisolated(unsafe) var _stableToHkDevice: [String: String] = [:]
    private nonisolated(unsafe) var _hkToStableDevice: [String: String] = [:]
    private nonisolated(unsafe) var _stableToHkService: [String: String] = [:]
    private nonisolated(unsafe) var _hkToStableService: [String: String] = [:]
    private nonisolated(unsafe) var _stableToHkChar: [String: String] = [:]
    private nonisolated(unsafe) var _hkToStableChar: [String: String] = [:]
    private nonisolated(unsafe) var _stableToHkScene: [String: String] = [:]
    private nonisolated(unsafe) var _hkToStableScene: [String: String] = [:]

    // MARK: - Persistence

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

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

                // Build service and characteristic remapping
                let orphanServicesByKey = Dictionary(
                    entry.services.map { ("\($0.serviceType):\($0.serviceIndex)", $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let resolvedServicesByKey = Dictionary(
                    resolved.services.map { ("\($0.serviceType):\($0.serviceIndex)", $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                for (key, orphanService) in orphanServicesByKey {
                    if let resolvedService = resolvedServicesByKey[key] {
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
        return _stableToHkDevice[stableId]
    }

    /// Resolves a HomeKit UUID → stable device ID. Call from any thread.
    nonisolated func readStableDeviceId(_ homeKitId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _hkToStableDevice[homeKitId]
    }

    /// Resolves a stable service ID → HomeKit service UUID. Call from any thread.
    nonisolated func readHomeKitServiceId(_ stableServiceId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _stableToHkService[stableServiceId]
    }

    /// Resolves a HomeKit service UUID → stable service ID. Call from any thread.
    nonisolated func readStableServiceId(_ homeKitServiceId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _hkToStableService[homeKitServiceId]
    }

    /// Resolves a stable characteristic ID → HomeKit characteristic UUID. Call from any thread.
    nonisolated func readHomeKitCharacteristicId(_ stableCharId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _stableToHkChar[stableCharId]
    }

    /// Resolves a HomeKit characteristic UUID → stable characteristic ID. Call from any thread.
    nonisolated func readStableCharacteristicId(_ homeKitCharId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _hkToStableChar[homeKitCharId]
    }

    /// Resolves a stable scene ID → HomeKit scene UUID. Call from any thread.
    nonisolated func readHomeKitSceneId(_ stableSceneId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _stableToHkScene[stableSceneId]
    }

    /// Resolves a HomeKit scene UUID → stable scene ID. Call from any thread.
    nonisolated func readStableSceneId(_ homeKitSceneId: String) -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }
        return _hkToStableScene[homeKitSceneId]
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

    /// Returns a DeviceModel with all IDs replaced by stable registry IDs.
    /// If a mapping is not found, the original ID is preserved.
    nonisolated func withStableIds(_ device: DeviceModel) -> DeviceModel {
        let stableDeviceId = readStableDeviceId(device.id) ?? device.id
        let stableServices = device.services.map { service in
            let stableServiceId = readStableServiceId(service.id) ?? service.id
            let stableChars = service.characteristics.map { char in
                CharacteristicModel(
                    id: readStableCharacteristicId(char.id) ?? char.id,
                    type: char.type,
                    value: char.value,
                    format: char.format,
                    units: char.units,
                    permissions: char.permissions,
                    minValue: char.minValue,
                    maxValue: char.maxValue,
                    stepValue: char.stepValue,
                    validValues: char.validValues
                )
            }
            return ServiceModel(id: stableServiceId, name: service.name, type: service.type, characteristics: stableChars)
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

    /// Returns workflow service references that point to a serviceId not present in the registry.
    /// Only checks resolved devices (unresolved devices are handled by existing orphan detection).
    func unresolvedServiceReferences(in workflows: [Workflow]) -> [(workflowName: String, deviceName: String, serviceId: String, location: String)] {
        var results: [(workflowName: String, deviceName: String, serviceId: String, location: String)] = []

        for workflow in workflows {
            let refs = WorkflowMigrationService.collectDeviceReferences(from: workflow)
            for ref in refs {
                guard let serviceId = ref.serviceId else { continue }
                guard let deviceEntry = devices[ref.deviceId] else { continue }
                guard deviceEntry.isResolved else { continue }

                let serviceExists = deviceEntry.services.contains { $0.stableServiceId == serviceId }
                if !serviceExists {
                    results.append((
                        workflowName: workflow.name,
                        deviceName: deviceEntry.name,
                        serviceId: serviceId,
                        location: ref.location
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
        // Build service+characteristic entries, preserving existing stable IDs where possible
        let existingServicesByTypeIndex: [String: ServiceRegistryEntry] = {
            guard let existing else { return [:] }
            return Dictionary(uniqueKeysWithValues: existing.services.map {
                ("\($0.serviceType):\($0.serviceIndex)", $0)
            })
        }()

        let services: [ServiceRegistryEntry] = device.services.enumerated().map { index, service in
            let typeIndexKey = "\(service.type):\(index)"
            let existingService = existingServicesByTypeIndex[typeIndexKey]

            // Build characteristic entries, preserving existing stable IDs
            let existingCharsByType: [String: CharacteristicRegistryEntry] = {
                guard let existingService else { return [:] }
                return Dictionary(uniqueKeysWithValues: existingService.characteristics.map {
                    ($0.characteristicType, $0)
                })
            }()

            let chars: [CharacteristicRegistryEntry] = service.characteristics.map { char in
                if let existingChar = existingCharsByType[char.type] {
                    return CharacteristicRegistryEntry(
                        stableCharacteristicId: existingChar.stableCharacteristicId,
                        homeKitCharacteristicId: char.id,
                        characteristicType: char.type
                    )
                } else {
                    return CharacteristicRegistryEntry(
                        stableCharacteristicId: UUID().uuidString,
                        homeKitCharacteristicId: char.id,
                        characteristicType: char.type
                    )
                }
            }

            return ServiceRegistryEntry(
                stableServiceId: existingService?.stableServiceId ?? UUID().uuidString,
                homeKitServiceId: service.id,
                serviceType: service.type,
                serviceIndex: index,
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

        // Update thread-safe nonisolated lookup dictionaries
        syncLock.lock()
        _stableToHkDevice.removeAll()
        _hkToStableDevice = hkDeviceIdToStableId.reduce(into: [:]) { $0[$1.value] = $1.key }
        _stableToHkService.removeAll()
        _hkToStableService = hkServiceIdToStableId.reduce(into: [:]) { $0[$1.value] = $1.key }
        _stableToHkChar.removeAll()
        _hkToStableChar = hkCharIdToStableId.reduce(into: [:]) { $0[$1.value] = $1.key }
        _stableToHkScene.removeAll()
        _hkToStableScene = hkSceneIdToStableId.reduce(into: [:]) { $0[$1.value] = $1.key }

        // Forward lookups: stableId → homeKitId
        for entry in devices.values {
            if let hkId = entry.homeKitId {
                _stableToHkDevice[entry.stableId] = hkId
            }
            for svc in entry.services {
                if let hkId = svc.homeKitServiceId {
                    _stableToHkService[svc.stableServiceId] = hkId
                }
                for char in svc.characteristics {
                    if let hkId = char.homeKitCharacteristicId {
                        _stableToHkChar[char.stableCharacteristicId] = hkId
                    }
                }
            }
        }
        for entry in scenes.values {
            if let hkId = entry.homeKitId {
                _stableToHkScene[entry.stableId] = hkId
            }
        }

        // Reverse lookups: homeKitId → stableId
        _hkToStableDevice = hkDeviceIdToStableId
        _hkToStableService = hkServiceIdToStableId
        _hkToStableChar = hkCharIdToStableId
        _hkToStableScene = hkSceneIdToStableId
        syncLock.unlock()
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
