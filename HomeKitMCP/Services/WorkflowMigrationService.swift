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
    static func migrate(_ workflow: Workflow, using devices: [DeviceModel], scenes: [SceneModel] = [], registry: DeviceRegistryService? = nil) -> MigrationResult {
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
            if registry?.readHomeKitDeviceId(ref.deviceId) != nil { continue }
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
            if registry?.readHomeKitSceneId(ref.sceneId) != nil { continue }
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
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: nil, contextRoom: nil, contextServiceType: nil, location: "trigger"))
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

    private static func collectConditionRefs(_ condition: WorkflowCondition, into refs: inout Set<DeviceRef>) {
        switch condition {
        case let .deviceState(c):
            refs.insert(DeviceRef(deviceId: c.deviceId, serviceId: c.serviceId, contextName: nil, contextRoom: nil, contextServiceType: nil, location: "condition"))
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
        case let .action(action, _):
            switch action {
            case let .controlDevice(a):
                refs.insert(DeviceRef(deviceId: a.deviceId, serviceId: a.serviceId, contextName: nil, contextRoom: nil, contextServiceType: nil, location: "block"))
            default:
                break
            }
        case let .flowControl(fc, _):
            switch fc {
            case let .waitForState(b):
                collectConditionRefs(b.condition, into: &refs)
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
            refs.insert(SceneRef(sceneId: c.sceneId, sceneName: nil, location: "condition (sceneActive)"))
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
        case let .action(action, _):
            switch action {
            case let .runScene(a):
                refs.insert(SceneRef(sceneId: a.sceneId, sceneName: nil, location: "block (runScene)"))
            default:
                break
            }
        case let .flowControl(fc, _):
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
    static func applyRemapping(to workflow: Workflow, deviceIdMap: [String: String], serviceIdMap: [String: [String: String]], sceneIdMap: [String: String] = [:]) -> Workflow? {
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
    static func migrateAll(_ workflows: [Workflow], using devices: [DeviceModel], scenes: [SceneModel] = [], registry: DeviceRegistryService? = nil) -> BatchMigrationResult {
        var result: [Workflow] = []
        var totalRemappedDevices = 0
        var totalRemappedScenes = 0
        var allOrphans: [String: [OrphanedReference]] = [:]

        for workflow in workflows {
            let migration = migrate(workflow, using: devices, scenes: scenes, registry: registry)
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

// MARK: - Deep Validation & Auto-Repair

extension WorkflowMigrationService {

    /// Result of validating a single workflow reference against the registry.
    struct ValidationIssue {
        let workflowId: UUID
        let workflowName: String
        let location: String
        let issueType: IssueType
        let detail: String

        enum IssueType {
            case unresolvedDevice(stableId: String)
            case unresolvedService(stableId: String, deviceStableId: String)
            case serviceRemapped(oldServiceId: String, newServiceId: String)
            case characteristicTypeNormalized(displayName: String, uuid: String)
        }
    }

    /// Result of validating and repairing all workflow references.
    struct ValidationResult {
        let updatedWorkflows: [Workflow]
        let autoFixed: [ValidationIssue]
        let unresolvable: [ValidationIssue]
    }

    /// Validates ALL workflow references (deviceId, serviceId, characteristicType)
    /// against the device registry. Auto-repairs where possible:
    /// - Remaps serviceId by matching serviceType within a resolved device
    /// - Normalizes characteristicType from display names to HomeKit UUIDs
    static func validateAndRepairReferences(
        _ workflows: [Workflow],
        registry: DeviceRegistryService
    ) async -> ValidationResult {
        var autoFixed: [ValidationIssue] = []
        var unresolvable: [ValidationIssue] = []
        var serviceRemapTable: [String: String] = [:]
        var charTypeRemapTable: [String: String] = [:]

        var processedServiceIds = Set<String>()

        for workflow in workflows {
            let deviceRefs = collectDeviceReferences(from: workflow)

            for ref in deviceRefs {
                // 1. Check device resolution
                guard let deviceEntry = await registry.deviceEntry(for: ref.deviceId) else {
                    unresolvable.append(ValidationIssue(
                        workflowId: workflow.id,
                        workflowName: workflow.name,
                        location: ref.location,
                        issueType: .unresolvedDevice(stableId: ref.deviceId),
                        detail: "Device '\(ref.contextName ?? ref.deviceId)' not found in registry"
                    ))
                    continue
                }

                guard deviceEntry.isResolved else { continue }

                // 2. Check service resolution
                guard let serviceId = ref.serviceId else { continue }
                guard !processedServiceIds.contains(serviceId) else { continue }
                processedServiceIds.insert(serviceId)

                let serviceExists = deviceEntry.services.contains { $0.stableServiceId == serviceId }
                if serviceExists { continue }

                // Service ID not found — try to remap by service type
                if let serviceType = ref.contextServiceType {
                    let matchingServices = deviceEntry.services.filter { $0.serviceType == serviceType }
                    if matchingServices.count == 1 {
                        let newServiceId = matchingServices[0].stableServiceId
                        serviceRemapTable[serviceId] = newServiceId
                        autoFixed.append(ValidationIssue(
                            workflowId: workflow.id,
                            workflowName: workflow.name,
                            location: ref.location,
                            issueType: .serviceRemapped(oldServiceId: serviceId, newServiceId: newServiceId),
                            detail: "Service remapped by type '\(serviceType)' on device '\(deviceEntry.name)'"
                        ))
                    } else if matchingServices.isEmpty {
                        unresolvable.append(ValidationIssue(
                            workflowId: workflow.id,
                            workflowName: workflow.name,
                            location: ref.location,
                            issueType: .unresolvedService(stableId: serviceId, deviceStableId: ref.deviceId),
                            detail: "Service '\(serviceId)' not found in device '\(deviceEntry.name)'; no service of type '\(serviceType)' exists"
                        ))
                    } else {
                        let newServiceId = matchingServices[0].stableServiceId
                        serviceRemapTable[serviceId] = newServiceId
                        autoFixed.append(ValidationIssue(
                            workflowId: workflow.id,
                            workflowName: workflow.name,
                            location: ref.location,
                            issueType: .serviceRemapped(oldServiceId: serviceId, newServiceId: newServiceId),
                            detail: "Service remapped by type '\(serviceType)' on device '\(deviceEntry.name)' (first of \(matchingServices.count))"
                        ))
                    }
                } else if deviceEntry.services.count == 1 {
                    let newServiceId = deviceEntry.services[0].stableServiceId
                    serviceRemapTable[serviceId] = newServiceId
                    autoFixed.append(ValidationIssue(
                        workflowId: workflow.id,
                        workflowName: workflow.name,
                        location: ref.location,
                        issueType: .serviceRemapped(oldServiceId: serviceId, newServiceId: newServiceId),
                        detail: "Service remapped (single-service device '\(deviceEntry.name)')"
                    ))
                } else {
                    unresolvable.append(ValidationIssue(
                        workflowId: workflow.id,
                        workflowName: workflow.name,
                        location: ref.location,
                        issueType: .unresolvedService(stableId: serviceId, deviceStableId: ref.deviceId),
                        detail: "Service '\(serviceId)' not found in device '\(deviceEntry.name)' (\(deviceEntry.services.count) services, no type context)"
                    ))
                }
            }
        }

        // 3. Normalize characteristicType display names → HomeKit UUIDs
        let charTypes = collectAllCharacteristicTypes(from: workflows)
        for charType in charTypes {
            if looksLikeUUID(charType) { continue }
            if charTypeRemapTable[charType] != nil { continue }
            if let uuid = CharacteristicTypes.characteristicType(forName: charType) {
                charTypeRemapTable[charType] = uuid
                autoFixed.append(ValidationIssue(
                    workflowId: UUID(),
                    workflowName: "(all)",
                    location: "characteristicType",
                    issueType: .characteristicTypeNormalized(displayName: charType, uuid: uuid),
                    detail: "'\(charType)' → '\(CharacteristicTypes.displayName(for: uuid))' (\(uuid))"
                ))
            }
        }

        // 4. Apply remapping if anything needs fixing
        if serviceRemapTable.isEmpty && charTypeRemapTable.isEmpty {
            return ValidationResult(
                updatedWorkflows: workflows,
                autoFixed: autoFixed,
                unresolvable: unresolvable
            )
        }

        var result: [Workflow] = []
        for workflow in workflows {
            result.append(applyValidationRemapping(
                to: workflow,
                serviceIdMap: serviceRemapTable,
                charTypeMap: charTypeRemapTable
            ) ?? workflow)
        }

        let totalServiceRemaps = serviceRemapTable.count
        let totalCharNormalizations = charTypeRemapTable.count
        if totalServiceRemaps > 0 || totalCharNormalizations > 0 {
            AppLogger.registry.info("Validation repair: remapped \(totalServiceRemaps) service(s), normalized \(totalCharNormalizations) characteristic type(s)")
        }

        return ValidationResult(
            updatedWorkflows: result,
            autoFixed: autoFixed,
            unresolvable: unresolvable
        )
    }

    // MARK: - Characteristic Type Collection

    /// Collects ALL characteristicType strings from all workflow triggers, conditions, and blocks.
    static func collectAllCharacteristicTypes(from workflows: [Workflow]) -> Set<String> {
        var types = Set<String>()
        for workflow in workflows {
            for trigger in workflow.triggers {
                collectTriggerCharTypes(trigger, into: &types)
            }
            if let conditions = workflow.conditions {
                for condition in conditions {
                    collectConditionCharTypes(condition, into: &types)
                }
            }
            for block in workflow.blocks {
                collectBlockCharTypes(block, into: &types)
            }
        }
        return types
    }

    private static func collectTriggerCharTypes(_ trigger: WorkflowTrigger, into types: inout Set<String>) {
        switch trigger {
        case .deviceStateChange(let t):
            types.insert(t.characteristicId)
        default: break
        }
    }

    private static func collectConditionCharTypes(_ condition: WorkflowCondition, into types: inout Set<String>) {
        switch condition {
        case .deviceState(let c):
            types.insert(c.characteristicId)
        case .and(let conditions):
            for c in conditions { collectConditionCharTypes(c, into: &types) }
        case .or(let conditions):
            for c in conditions { collectConditionCharTypes(c, into: &types) }
        case .not(let c):
            collectConditionCharTypes(c, into: &types)
        default: break
        }
    }

    private static func collectBlockCharTypes(_ block: WorkflowBlock, into types: inout Set<String>) {
        switch block {
        case .action(let action, _):
            switch action {
            case .controlDevice(let a): types.insert(a.characteristicId)
            default: break
            }
        case .flowControl(let fc, _):
            switch fc {
            case .waitForState(let b):
                collectConditionCharTypes(b.condition, into: &types)
            case .conditional(let b):
                collectConditionCharTypes(b.condition, into: &types)
                for nested in b.thenBlocks { collectBlockCharTypes(nested, into: &types) }
                for nested in (b.elseBlocks ?? []) { collectBlockCharTypes(nested, into: &types) }
            case .repeat(let b):
                for nested in b.blocks { collectBlockCharTypes(nested, into: &types) }
            case .repeatWhile(let b):
                collectConditionCharTypes(b.condition, into: &types)
                for nested in b.blocks { collectBlockCharTypes(nested, into: &types) }
            case .group(let b):
                for nested in b.blocks { collectBlockCharTypes(nested, into: &types) }
            default: break
            }
        }
    }

    // MARK: - Helpers

    /// Checks whether a string looks like a HomeKit UUID (36-char format with dashes, or a known HM type).
    static func looksLikeUUID(_ string: String) -> Bool {
        if string.count >= 36 && string.contains("-") { return true }
        if CharacteristicTypes.isSupported(string) { return true }
        return false
    }

    /// Apply service ID and characteristicType remapping via JSON replacement.
    private static func applyValidationRemapping(
        to workflow: Workflow,
        serviceIdMap: [String: String],
        charTypeMap: [String: String]
    ) -> Workflow? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(workflow),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        for (oldId, newId) in serviceIdMap {
            jsonString = jsonString.replacingOccurrences(of: "\"\(oldId)\"", with: "\"\(newId)\"")
        }

        for (displayName, uuid) in charTypeMap {
            jsonString = jsonString.replacingOccurrences(of: "\"\(displayName)\"", with: "\"\(uuid)\"")
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

// MARK: - Characteristic ID Migration (characteristicType → stable characteristicId)
// TODO: Remove this extension once all existing workflows have been migrated.

extension WorkflowMigrationService {

    /// A characteristic reference: deviceId + the characteristicId value currently stored.
    private struct CharRef: Hashable {
        let deviceId: String
        let characteristicId: String
    }

    /// One-time migration: replaces legacy HomeKit characteristic type strings stored in
    /// `characteristicId` with the actual stable characteristic ID from the device registry.
    ///
    /// For each (deviceId, characteristicId) pair in triggers/conditions/blocks:
    /// 1. If `characteristicId` already resolves as a stable ID in the registry → skip.
    /// 2. Otherwise, treat it as a HomeKit characteristic type and look up the stable ID via
    ///    `readStableCharacteristicId(forDeviceStableId:characteristicType:)`.
    /// 3. If found, add to a remap table and apply via JSON string replacement.
    static func migrateCharacteristicIds(_ workflows: [Workflow], registry: DeviceRegistryService) -> (workflows: [Workflow], migratedCount: Int) {
        var charIdMap: [String: String] = [:]

        // Collect all unique (deviceId, characteristicId) pairs
        var refs = Set<CharRef>()
        for workflow in workflows {
            for trigger in workflow.triggers {
                collectTriggerCharRefs(trigger, into: &refs)
            }
            if let conditions = workflow.conditions {
                for condition in conditions {
                    collectConditionCharRefs(condition, into: &refs)
                }
            }
            for block in workflow.blocks {
                collectBlockCharRefs(block, into: &refs)
            }
        }

        for ref in refs {
            guard charIdMap[ref.characteristicId] == nil else { continue }

            // Already a stable ID — nothing to do
            if registry.readCharacteristicType(forStableId: ref.characteristicId) != nil {
                continue
            }

            // Treat as legacy characteristic type string, resolve to stable ID
            if let stableId = registry.readStableCharacteristicId(
                forDeviceStableId: ref.deviceId,
                characteristicType: ref.characteristicId
            ) {
                charIdMap[ref.characteristicId] = stableId
            }
        }

        if charIdMap.isEmpty {
            return (workflows, 0)
        }

        // Apply via JSON string replacement
        var result: [Workflow] = []
        for workflow in workflows {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            guard let jsonData = try? encoder.encode(workflow),
                  var jsonString = String(data: jsonData, encoding: .utf8) else {
                result.append(workflow)
                continue
            }

            for (oldValue, newValue) in charIdMap {
                jsonString = jsonString.replacingOccurrences(of: "\"\(oldValue)\"", with: "\"\(newValue)\"")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let updatedData = jsonString.data(using: .utf8),
               let updatedWorkflow = try? decoder.decode(Workflow.self, from: updatedData) {
                result.append(updatedWorkflow)
            } else {
                result.append(workflow)
            }
        }

        AppLogger.registry.info("Characteristic ID migration: remapped \(charIdMap.count) characteristic type(s) to stable IDs")
        return (result, charIdMap.count)
    }

    // MARK: - Char Ref Collectors

    private static func collectTriggerCharRefs(_ trigger: WorkflowTrigger, into refs: inout Set<CharRef>) {
        switch trigger {
        case .deviceStateChange(let t):
            refs.insert(CharRef(deviceId: t.deviceId, characteristicId: t.characteristicId))
        default: break
        }
    }

    private static func collectConditionCharRefs(_ condition: WorkflowCondition, into refs: inout Set<CharRef>) {
        switch condition {
        case .deviceState(let c):
            refs.insert(CharRef(deviceId: c.deviceId, characteristicId: c.characteristicId))
        case .and(let conditions):
            for c in conditions { collectConditionCharRefs(c, into: &refs) }
        case .or(let conditions):
            for c in conditions { collectConditionCharRefs(c, into: &refs) }
        case .not(let c):
            collectConditionCharRefs(c, into: &refs)
        default: break
        }
    }

    private static func collectBlockCharRefs(_ block: WorkflowBlock, into refs: inout Set<CharRef>) {
        switch block {
        case .action(let action, _):
            switch action {
            case .controlDevice(let a):
                refs.insert(CharRef(deviceId: a.deviceId, characteristicId: a.characteristicId))
            default: break
            }
        case .flowControl(let fc, _):
            switch fc {
            case .waitForState(let b):
                collectConditionCharRefs(b.condition, into: &refs)
            case .conditional(let b):
                collectConditionCharRefs(b.condition, into: &refs)
                for nested in b.thenBlocks { collectBlockCharRefs(nested, into: &refs) }
                for nested in (b.elseBlocks ?? []) { collectBlockCharRefs(nested, into: &refs) }
            case .repeat(let b):
                for nested in b.blocks { collectBlockCharRefs(nested, into: &refs) }
            case .repeatWhile(let b):
                collectConditionCharRefs(b.condition, into: &refs)
                for nested in b.blocks { collectBlockCharRefs(nested, into: &refs) }
            case .group(let b):
                for nested in b.blocks { collectBlockCharRefs(nested, into: &refs) }
            default: break
            }
        }
    }
}
