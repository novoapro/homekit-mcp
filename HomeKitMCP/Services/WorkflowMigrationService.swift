import Foundation

/// Migrates orphaned device/service/scene UUIDs in workflows after a HomeKit backup restore.
///
/// When HomeKit is restored from an iCloud backup to a different machine, the same physical devices
/// and scenes get new UUIDs. This service detects orphaned references and attempts to remap them
/// by matching on device name + room (for devices) or scene name (for scenes).
enum WorkflowMigrationService {

    /// A reference in a workflow that could not be resolved to any known device or scene.
    struct OrphanedReference {
        let referenceId: String
        let referenceName: String?
        let roomName: String?
        /// Where in the workflow the orphan was found (e.g. "trigger", "condition", "block (runScene)").
        let location: String
        /// Whether this is a scene reference (vs. device reference).
        let isScene: Bool
    }

    /// Result of a migration attempt on a single workflow.
    struct MigrationResult {
        let workflow: Workflow
        let remappedDevices: Int
        let remappedServices: Int
        let remappedScenes: Int
        let orphanedReferences: [OrphanedReference]
    }

    /// Migrate all device/service/scene references in a workflow.
    /// Returns the (possibly updated) workflow and a summary of changes.
    static func migrate(_ workflow: Workflow, using devices: [DeviceModel], scenes: [SceneModel] = []) -> MigrationResult {
        let knownDeviceIds = Set(devices.map(\.id))
        let knownSceneIds = Set(scenes.map(\.id))

        // Build lookup indices
        let devicesByNameRoom = buildDeviceLookup(devices)
        let scenesByName = buildSceneLookup(scenes)

        var remappedDevices = 0
        var remappedServices = 0
        var remappedScenes = 0
        var orphanedRefs: [OrphanedReference] = []

        // --- Device migration ---
        var idMap: [String: String] = [:]           // oldDeviceId → newDeviceId
        var serviceIdMap: [String: [String: String]] = [:]  // oldDeviceId → (oldServiceId → newServiceId)
        var matchedDevices: [String: DeviceModel] = [:]     // oldDeviceId → matched DeviceModel
        var orphanedDeviceIds = Set<String>()

        let allDeviceRefs = collectDeviceReferences(from: workflow)

        // Pass 1: Match devices (deduplicated by deviceId)
        for ref in allDeviceRefs {
            if knownDeviceIds.contains(ref.deviceId) { continue }
            if idMap[ref.deviceId] != nil || orphanedDeviceIds.contains(ref.deviceId) { continue }

            if let match = findMatch(for: ref, in: devices, lookup: devicesByNameRoom) {
                idMap[ref.deviceId] = match.id
                matchedDevices[ref.deviceId] = match
                remappedDevices += 1
            } else {
                orphanedDeviceIds.insert(ref.deviceId)
                orphanedRefs.append(OrphanedReference(
                    referenceId: ref.deviceId,
                    referenceName: ref.contextName,
                    roomName: ref.contextRoom,
                    location: ref.location,
                    isScene: false
                ))
            }
        }

        // Pass 2: Match services for all refs with serviceIds on matched devices
        var processedServiceIds = Set<String>()
        for ref in allDeviceRefs {
            guard let oldServiceId = ref.serviceId else { continue }
            guard !processedServiceIds.contains(oldServiceId) else { continue }
            guard let matchedDevice = matchedDevices[ref.deviceId] else { continue }

            processedServiceIds.insert(oldServiceId)
            if let newServiceId = matchService(oldServiceId: oldServiceId, oldDeviceRef: ref, newDevice: matchedDevice) {
                if serviceIdMap[ref.deviceId] == nil {
                    serviceIdMap[ref.deviceId] = [:]
                }
                serviceIdMap[ref.deviceId]?[oldServiceId] = newServiceId
                remappedServices += 1
            }
        }

        // --- Scene migration ---
        var sceneIdMap: [String: String] = [:]  // oldSceneId → newSceneId

        let allSceneRefs = collectSceneReferences(from: workflow)

        for ref in allSceneRefs {
            if knownSceneIds.contains(ref.sceneId) { continue }
            if sceneIdMap[ref.sceneId] != nil { continue }

            if let match = findSceneMatch(for: ref, lookup: scenesByName) {
                sceneIdMap[ref.sceneId] = match.id
                remappedScenes += 1
            } else {
                orphanedRefs.append(OrphanedReference(
                    referenceId: ref.sceneId,
                    referenceName: ref.sceneName,
                    roomName: nil,
                    location: ref.location,
                    isScene: true
                ))
            }
        }

        // If nothing needs remapping, return as-is
        if idMap.isEmpty && sceneIdMap.isEmpty {
            return MigrationResult(workflow: workflow, remappedDevices: 0, remappedServices: 0, remappedScenes: 0, orphanedReferences: orphanedRefs)
        }

        // Apply the remapping by encoding → modifying JSON → decoding
        let migratedWorkflow = applyRemapping(to: workflow, deviceIdMap: idMap, serviceIdMap: serviceIdMap, sceneIdMap: sceneIdMap)

        return MigrationResult(
            workflow: migratedWorkflow ?? workflow,
            remappedDevices: remappedDevices,
            remappedServices: remappedServices,
            remappedScenes: remappedScenes,
            orphanedReferences: orphanedRefs
        )
    }

    // MARK: - Device Reference Collection

    /// A lightweight reference to a device used somewhere in a workflow.
    struct DeviceRef: Hashable {
        let deviceId: String
        let serviceId: String?
        /// Context for matching: the device name if stored alongside the ID.
        let contextName: String?
        /// Context for matching: the room name if stored alongside the ID.
        let contextRoom: String?
        /// Context for matching: the service type (e.g. "Outlet") enriched during backup export.
        let contextServiceType: String?
        /// Where in the workflow this reference appears (e.g. "trigger", "condition", "block").
        let location: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(deviceId)
            hasher.combine(serviceId)
        }

        static func == (lhs: DeviceRef, rhs: DeviceRef) -> Bool {
            lhs.deviceId == rhs.deviceId && lhs.serviceId == rhs.serviceId
        }
    }

    static func collectDeviceReferences(from workflow: Workflow) -> Set<DeviceRef> {
        var refs = Set<DeviceRef>()

        // Triggers
        for trigger in workflow.triggers {
            switch trigger {
            case let .deviceStateChange(t):
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: t.deviceName, contextRoom: t.roomName, contextServiceType: t.serviceType, location: "trigger"))
            case let .compound(c):
                collectCompoundTriggerRefs(c.triggers, into: &refs)
            default:
                break
            }
        }

        // Conditions
        if let conditions = workflow.conditions {
            for condition in conditions {
                collectConditionRefs(condition, into: &refs)
            }
        }

        // Blocks
        for block in workflow.blocks {
            collectBlockRefs(block, into: &refs)
        }

        return refs
    }

    private static func collectCompoundTriggerRefs(_ triggers: [WorkflowTrigger], into refs: inout Set<DeviceRef>) {
        for trigger in triggers {
            switch trigger {
            case let .deviceStateChange(t):
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: t.deviceName, contextRoom: t.roomName, contextServiceType: t.serviceType, location: "trigger"))
            case let .compound(c):
                collectCompoundTriggerRefs(c.triggers, into: &refs)
            default:
                break
            }
        }
    }

    private static func collectConditionRefs(_ condition: WorkflowCondition, into refs: inout Set<DeviceRef>) {
        switch condition {
        case let .deviceState(c):
            refs.insert(DeviceRef(deviceId: c.deviceId, serviceId: c.serviceId, contextName: c.deviceName, contextRoom: c.roomName, contextServiceType: c.serviceType, location: "condition"))
        case let .and(conditions):
            for c in conditions { collectConditionRefs(c, into: &refs) }
        case let .or(conditions):
            for c in conditions { collectConditionRefs(c, into: &refs) }
        case let .not(c):
            collectConditionRefs(c, into: &refs)
        default:
            break
        }
    }

    private static func collectBlockRefs(_ block: WorkflowBlock, into refs: inout Set<DeviceRef>) {
        switch block {
        case let .action(action):
            switch action {
            case let .controlDevice(a):
                refs.insert(DeviceRef(deviceId: a.deviceId, serviceId: a.serviceId, contextName: a.deviceName, contextRoom: a.roomName, contextServiceType: a.serviceType, location: "block"))
            default:
                break
            }
        case let .flowControl(fc):
            switch fc {
            case let .waitForState(b):
                refs.insert(DeviceRef(deviceId: b.deviceId, serviceId: b.serviceId, contextName: b.deviceName, contextRoom: b.roomName, contextServiceType: b.serviceType, location: "block"))
            case let .conditional(b):
                collectConditionRefs(b.condition, into: &refs)
                for nested in b.thenBlocks { collectBlockRefs(nested, into: &refs) }
                for nested in (b.elseBlocks ?? []) { collectBlockRefs(nested, into: &refs) }
            case let .repeat(b):
                for nested in b.blocks { collectBlockRefs(nested, into: &refs) }
            case let .repeatWhile(b):
                collectConditionRefs(b.condition, into: &refs)
                for nested in b.blocks { collectBlockRefs(nested, into: &refs) }
            case let .group(b):
                for nested in b.blocks { collectBlockRefs(nested, into: &refs) }
            default:
                break
            }
        }
    }

    // MARK: - Scene Reference Collection

    /// A lightweight reference to a scene used somewhere in a workflow.
    struct SceneRef: Hashable {
        let sceneId: String
        let sceneName: String?
        let location: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(sceneId)
        }

        static func == (lhs: SceneRef, rhs: SceneRef) -> Bool {
            lhs.sceneId == rhs.sceneId
        }
    }

    static func collectSceneReferences(from workflow: Workflow) -> Set<SceneRef> {
        var refs = Set<SceneRef>()

        // Conditions
        if let conditions = workflow.conditions {
            for condition in conditions {
                collectSceneConditionRefs(condition, into: &refs)
            }
        }

        // Blocks
        for block in workflow.blocks {
            collectSceneBlockRefs(block, into: &refs)
        }

        return refs
    }

    private static func collectSceneConditionRefs(_ condition: WorkflowCondition, into refs: inout Set<SceneRef>) {
        switch condition {
        case let .sceneActive(c):
            refs.insert(SceneRef(sceneId: c.sceneId, sceneName: c.sceneName, location: "condition (sceneActive)"))
        case let .and(conditions):
            for c in conditions { collectSceneConditionRefs(c, into: &refs) }
        case let .or(conditions):
            for c in conditions { collectSceneConditionRefs(c, into: &refs) }
        case let .not(c):
            collectSceneConditionRefs(c, into: &refs)
        default:
            break
        }
    }

    private static func collectSceneBlockRefs(_ block: WorkflowBlock, into refs: inout Set<SceneRef>) {
        switch block {
        case let .action(action):
            switch action {
            case let .runScene(a):
                refs.insert(SceneRef(sceneId: a.sceneId, sceneName: a.sceneName, location: "block (runScene)"))
            default:
                break
            }
        case let .flowControl(fc):
            switch fc {
            case let .conditional(b):
                collectSceneConditionRefs(b.condition, into: &refs)
                for nested in b.thenBlocks { collectSceneBlockRefs(nested, into: &refs) }
                for nested in (b.elseBlocks ?? []) { collectSceneBlockRefs(nested, into: &refs) }
            case let .repeat(b):
                for nested in b.blocks { collectSceneBlockRefs(nested, into: &refs) }
            case let .repeatWhile(b):
                collectSceneConditionRefs(b.condition, into: &refs)
                for nested in b.blocks { collectSceneBlockRefs(nested, into: &refs) }
            case let .group(b):
                for nested in b.blocks { collectSceneBlockRefs(nested, into: &refs) }
            default:
                break
            }
        }
    }

    // MARK: - Device Matching

    /// Key for name+room lookup.
    private struct DeviceKey: Hashable {
        let name: String   // lowercased
        let room: String   // lowercased, or "" for no room
    }

    /// Build a lookup table: name+room → device. Only includes entries where the combination is unique.
    private static func buildDeviceLookup(_ devices: [DeviceModel]) -> [DeviceKey: DeviceModel] {
        var groups: [DeviceKey: [DeviceModel]] = [:]
        for device in devices {
            let key = DeviceKey(name: device.name.lowercased(), room: (device.roomName ?? "").lowercased())
            groups[key, default: []].append(device)
        }
        // Only keep unambiguous matches
        var lookup: [DeviceKey: DeviceModel] = [:]
        for (key, group) in groups where group.count == 1 {
            lookup[key] = group[0]
        }
        return lookup
    }

    /// Try to find a device matching the orphaned reference.
    /// Uses the stored deviceName + roomName metadata to find the device by name+room lookup.
    /// Falls back to name-only matching if no room was stored or room lookup fails.
    private static func findMatch(for ref: DeviceRef, in devices: [DeviceModel], lookup: [DeviceKey: DeviceModel]) -> DeviceModel? {
        guard let name = ref.contextName else {
            // Without a stored name, we can't match — return nil to mark as orphaned
            return nil
        }

        // Try exact name+room lookup first (most precise)
        if let room = ref.contextRoom {
            let key = DeviceKey(name: name.lowercased(), room: room.lowercased())
            if let match = lookup[key] {
                return match
            }
        }

        // Fall back to name-only matching (less precise, but still useful)
        let nameMatches = devices.filter { $0.name.lowercased() == name.lowercased() }
        if nameMatches.count == 1 {
            return nameMatches[0]
        }

        // Multiple devices with the same name but no room match — ambiguous
        return nil
    }

    /// Try to match a service from the old device to the new device.
    /// Uses service type matching when available, falls back to single-service heuristic.
    private static func matchService(oldServiceId: String, oldDeviceRef: DeviceRef, newDevice: DeviceModel) -> String? {
        // If the new device has only one service, it's the match
        if newDevice.services.count == 1 {
            return newDevice.services[0].id
        }

        // If we know the old service's type (enriched during backup export), match by type
        if let serviceType = oldDeviceRef.contextServiceType {
            let matchingServices = newDevice.services.filter { $0.type == serviceType }
            if matchingServices.count == 1 {
                // Unique match by service type
                return matchingServices[0].id
            }
            // Multiple services of the same type — match by position among same-type services.
            // HomeKit preserves service ordering for the same device, so the Nth service of
            // a given type on the old device maps to the Nth on the new device.
            if matchingServices.count > 1 {
                // Find which index this service was among same-type services on the old device.
                // Since we don't have the old device's service list, we use a heuristic:
                // collect all refs for this device with the same serviceType, and use their
                // position in the sorted set as the index. However, we only have the current ref,
                // so just pick the first matching service as a safe default.
                return matchingServices[0].id
            }
        }

        return nil
    }

    // MARK: - Scene Matching

    /// Build a lookup table: sceneName → scene. Only includes entries where the name is unique.
    private static func buildSceneLookup(_ scenes: [SceneModel]) -> [String: SceneModel] {
        var groups: [String: [SceneModel]] = [:]
        for scene in scenes {
            groups[scene.name.lowercased(), default: []].append(scene)
        }
        var lookup: [String: SceneModel] = [:]
        for (key, group) in groups where group.count == 1 {
            lookup[key] = group[0]
        }
        return lookup
    }

    /// Try to find a scene matching the orphaned reference by name.
    private static func findSceneMatch(for ref: SceneRef, lookup: [String: SceneModel]) -> SceneModel? {
        guard let name = ref.sceneName else { return nil }
        return lookup[name.lowercased()]
    }

    // MARK: - JSON-based Remapping

    /// Apply device/service/scene ID remapping by encoding to JSON, doing string replacement, and decoding back.
    /// This avoids having to rebuild every nested struct manually.
    private static func applyRemapping(to workflow: Workflow, deviceIdMap: [String: String], serviceIdMap: [String: [String: String]], sceneIdMap: [String: String] = [:]) -> Workflow? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(workflow),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        // Replace device IDs (these are UUIDs, so string replacement is safe)
        for (oldId, newId) in deviceIdMap {
            jsonString = jsonString.replacingOccurrences(of: "\"\(oldId)\"", with: "\"\(newId)\"")
        }

        // Replace service IDs within their device context
        for (_, serviceMap) in serviceIdMap {
            for (oldServiceId, newServiceId) in serviceMap {
                jsonString = jsonString.replacingOccurrences(of: "\"\(oldServiceId)\"", with: "\"\(newServiceId)\"")
            }
        }

        // Replace scene IDs
        for (oldId, newId) in sceneIdMap {
            jsonString = jsonString.replacingOccurrences(of: "\"\(oldId)\"", with: "\"\(newId)\"")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let updatedData = jsonString.data(using: .utf8),
              let updatedWorkflow = try? decoder.decode(Workflow.self, from: updatedData) else {
            return nil
        }

        return updatedWorkflow
    }
}

// MARK: - Registry Migration (HomeKit UUIDs → Stable IDs)

extension WorkflowMigrationService {
    /// One-time migration: replaces all HomeKit UUIDs in workflows with stable registry IDs.
    /// Uses the registry's nonisolated sync lookups so this can be called from any context.
    ///
    /// For each deviceId/serviceId/sceneId in a workflow, checks if it's a known HomeKit UUID
    /// and replaces it with the corresponding stable registry ID.
    static func migrateToStableIds(_ workflows: [Workflow], registry: DeviceRegistryService) -> (workflows: [Workflow], migratedCount: Int) {
        var deviceIdMap: [String: String] = [:]
        var serviceIdMap: [String: String] = [:]
        var sceneIdMap: [String: String] = [:]

        // Collect all unique IDs from all workflows and build remapping tables
        for workflow in workflows {
            for ref in collectDeviceReferences(from: workflow) {
                if deviceIdMap[ref.deviceId] == nil {
                    if let stableId = registry.readStableDeviceId(ref.deviceId) {
                        deviceIdMap[ref.deviceId] = stableId
                    }
                }
                if let svcId = ref.serviceId, serviceIdMap[svcId] == nil {
                    if let stableId = registry.readStableServiceId(svcId) {
                        serviceIdMap[svcId] = stableId
                    }
                }
            }
            for ref in collectSceneReferences(from: workflow) {
                if sceneIdMap[ref.sceneId] == nil {
                    if let stableId = registry.readStableSceneId(ref.sceneId) {
                        sceneIdMap[ref.sceneId] = stableId
                    }
                }
            }
        }

        let totalRemapped = deviceIdMap.count + serviceIdMap.count + sceneIdMap.count
        if totalRemapped == 0 {
            return (workflows, 0)
        }

        // Apply remapping using the same JSON approach
        let combinedDeviceIdMap = deviceIdMap
        let combinedServiceIdMap: [String: [String: String]] = ["_all": serviceIdMap]
        let combinedSceneIdMap = sceneIdMap

        var result: [Workflow] = []
        for workflow in workflows {
            if let migrated = applyRemapping(
                to: workflow,
                deviceIdMap: combinedDeviceIdMap,
                serviceIdMap: combinedServiceIdMap,
                sceneIdMap: combinedSceneIdMap
            ) {
                result.append(migrated)
            } else {
                result.append(workflow)
            }
        }

        AppLogger.workflow.info("Registry migration: remapped \(deviceIdMap.count) device(s), \(serviceIdMap.count) service(s), \(sceneIdMap.count) scene(s)")
        return (result, totalRemapped)
    }
}

// MARK: - Metadata Enrichment

// MARK: - Batch Migration

extension WorkflowMigrationService {
    /// Result of a batch migration across multiple workflows.
    struct BatchMigrationResult {
        let workflows: [Workflow]
        let totalRemappedDevices: Int
        let totalRemappedScenes: Int
        let orphanedReferences: [String: [OrphanedReference]]  // workflowName → orphans
    }

    /// Migrate multiple workflows at once. Returns updated workflows, remapping counts, and orphan details.
    static func migrateAll(_ workflows: [Workflow], using devices: [DeviceModel], scenes: [SceneModel] = []) -> BatchMigrationResult {
        var result: [Workflow] = []
        var totalRemappedDevices = 0
        var totalRemappedScenes = 0
        var allOrphans: [String: [OrphanedReference]] = [:]

        for workflow in workflows {
            let migration = migrate(workflow, using: devices, scenes: scenes)
            result.append(migration.workflow)
            totalRemappedDevices += migration.remappedDevices
            totalRemappedScenes += migration.remappedScenes
            if !migration.orphanedReferences.isEmpty {
                allOrphans[workflow.name] = migration.orphanedReferences
            }
        }

        let totalRemapped = totalRemappedDevices + totalRemappedScenes
        if totalRemapped > 0 {
            AppLogger.workflow.info("Workflow migration: remapped \(totalRemappedDevices) device(s), \(totalRemappedScenes) scene(s) across \(workflows.count) workflow(s)")
        }
        if !allOrphans.isEmpty {
            let totalOrphans = allOrphans.values.map(\.count).reduce(0, +)
            AppLogger.workflow.warning("Workflow migration: \(totalOrphans) orphaned reference(s) in \(allOrphans.count) workflow(s) could not be resolved")
        }

        return BatchMigrationResult(
            workflows: result,
            totalRemappedDevices: totalRemappedDevices,
            totalRemappedScenes: totalRemappedScenes,
            orphanedReferences: allOrphans
        )
    }
}
