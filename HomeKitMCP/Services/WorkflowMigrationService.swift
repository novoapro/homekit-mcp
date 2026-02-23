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

        let allDeviceRefs = collectDeviceReferences(from: workflow)

        for ref in allDeviceRefs {
            if knownDeviceIds.contains(ref.deviceId) { continue }
            if idMap[ref.deviceId] != nil { continue }

            if let match = findMatch(for: ref, in: devices, lookup: devicesByNameRoom) {
                idMap[ref.deviceId] = match.id
                remappedDevices += 1

                if let oldServiceId = ref.serviceId {
                    if let newServiceId = matchService(oldServiceId: oldServiceId, oldDeviceRef: ref, newDevice: match) {
                        if serviceIdMap[ref.deviceId] == nil {
                            serviceIdMap[ref.deviceId] = [:]
                        }
                        serviceIdMap[ref.deviceId]?[oldServiceId] = newServiceId
                        remappedServices += 1
                    }
                }
            } else {
                orphanedRefs.append(OrphanedReference(
                    referenceId: ref.deviceId,
                    referenceName: ref.contextName,
                    roomName: ref.contextRoom,
                    location: ref.location,
                    isScene: false
                ))
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
        /// Where in the workflow this reference appears (e.g. "trigger", "condition", "block").
        let location: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(deviceId)
        }

        static func == (lhs: DeviceRef, rhs: DeviceRef) -> Bool {
            lhs.deviceId == rhs.deviceId
        }
    }

    static func collectDeviceReferences(from workflow: Workflow) -> Set<DeviceRef> {
        var refs = Set<DeviceRef>()

        // Triggers
        for trigger in workflow.triggers {
            switch trigger {
            case let .deviceStateChange(t):
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: t.deviceName, contextRoom: t.roomName, location: "trigger"))
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
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: t.deviceName, contextRoom: t.roomName, location: "trigger"))
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
            refs.insert(DeviceRef(deviceId: c.deviceId, serviceId: c.serviceId, contextName: c.deviceName, contextRoom: c.roomName, location: "condition"))
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
                refs.insert(DeviceRef(deviceId: a.deviceId, serviceId: a.serviceId, contextName: a.deviceName, contextRoom: a.roomName, location: "block"))
            default:
                break
            }
        case let .flowControl(fc):
            switch fc {
            case let .waitForState(b):
                refs.insert(DeviceRef(deviceId: b.deviceId, serviceId: b.serviceId, contextName: b.deviceName, contextRoom: b.roomName, location: "block"))
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
    /// Uses service name / type matching within the device.
    private static func matchService(oldServiceId: String, oldDeviceRef: DeviceRef, newDevice: DeviceModel) -> String? {
        // If the new device has only one service, it's the match
        if newDevice.services.count == 1 {
            return newDevice.services[0].id
        }

        // Try matching by service position (assuming same order after restore)
        // This is a best-effort heuristic
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

// MARK: - Metadata Enrichment

extension WorkflowMigrationService {
    /// Fill in missing `deviceName`/`roomName` and `sceneName` metadata on references in a workflow.
    ///
    /// Without this metadata, cross-machine migration cannot resolve orphaned UUIDs.
    /// This method walks the workflow's JSON representation and fills any missing fields
    /// from the current device and scene lists.
    static func enrichMetadata(in workflow: Workflow, using devices: [DeviceModel], scenes: [SceneModel]) -> Workflow {
        guard !devices.isEmpty || !scenes.isEmpty else { return workflow }

        // Build deviceId → (name, room) lookup
        var deviceLookup: [String: (name: String, room: String?)] = [:]
        for device in devices {
            deviceLookup[device.id] = (device.name, device.roomName)
        }

        // Build sceneId → name lookup
        var sceneLookup: [String: String] = [:]
        for scene in scenes {
            sceneLookup[scene.id] = scene.name
        }

        // Encode to JSON dict
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(workflow),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return workflow
        }

        var changed = false
        enrichDict(&dict, deviceLookup: deviceLookup, sceneLookup: sceneLookup, changed: &changed)

        guard changed else { return workflow }

        // Decode back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let enrichedData = try? JSONSerialization.data(withJSONObject: dict),
              let enriched = try? decoder.decode(Workflow.self, from: enrichedData) else {
            return workflow
        }
        return enriched
    }

    /// Recursively walk a JSON dict tree, filling metadata wherever device/scene IDs are present.
    private static func enrichDict(_ dict: inout [String: Any], deviceLookup: [String: (name: String, room: String?)], sceneLookup: [String: String], changed: inout Bool) {
        // Enrich device metadata
        if let deviceId = dict["deviceId"] as? String,
           let info = deviceLookup[deviceId] {
            if dict["deviceName"] == nil || (dict["deviceName"] as? String)?.isEmpty == true {
                dict["deviceName"] = info.name
                changed = true
            }
            if dict["roomName"] == nil || (dict["roomName"] as? String)?.isEmpty == true {
                if let room = info.room {
                    dict["roomName"] = room
                    changed = true
                }
            }
        }

        // Enrich scene metadata
        if let sceneId = dict["sceneId"] as? String,
           let name = sceneLookup[sceneId] {
            if dict["sceneName"] == nil || (dict["sceneName"] as? String)?.isEmpty == true {
                dict["sceneName"] = name
                changed = true
            }
        }

        // Recurse into nested dicts and arrays
        for key in dict.keys {
            if var nested = dict[key] as? [String: Any] {
                enrichDict(&nested, deviceLookup: deviceLookup, sceneLookup: sceneLookup, changed: &changed)
                dict[key] = nested
            } else if var array = dict[key] as? [[String: Any]] {
                for i in array.indices {
                    enrichDict(&array[i], deviceLookup: deviceLookup, sceneLookup: sceneLookup, changed: &changed)
                }
                dict[key] = array
            } else if let mixedArray = dict[key] as? [Any] {
                var modified = false
                var newArray = mixedArray
                for i in newArray.indices {
                    if var nested = newArray[i] as? [String: Any] {
                        enrichDict(&nested, deviceLookup: deviceLookup, sceneLookup: sceneLookup, changed: &changed)
                        newArray[i] = nested
                        modified = true
                    }
                }
                if modified {
                    dict[key] = newArray
                }
            }
        }
    }
}

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
