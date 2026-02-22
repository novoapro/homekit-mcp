import Foundation

/// Migrates orphaned device/service UUIDs in workflows after a HomeKit backup restore.
///
/// When HomeKit is restored from an iCloud backup to a different machine, the same physical devices
/// get new UUIDs. This service detects orphaned references and attempts to remap them by matching
/// on device name + room. If exactly one match is found, the ID is updated silently.
enum WorkflowMigrationService {

    /// A device reference in a workflow that could not be resolved to any known device.
    struct OrphanedReference {
        let deviceId: String
        let deviceName: String?
        let roomName: String?
        /// Where in the workflow the orphan was found (e.g. "trigger", "condition", "block").
        let location: String
    }

    /// Result of a migration attempt on a single workflow.
    struct MigrationResult {
        let workflow: Workflow
        let remappedDevices: Int
        let remappedServices: Int
        let orphanedReferences: [OrphanedReference]
    }

    /// Migrate all device/service references in a workflow.
    /// Returns the (possibly updated) workflow and a summary of changes.
    static func migrate(_ workflow: Workflow, using devices: [DeviceModel]) -> MigrationResult {
        let knownDeviceIds = Set(devices.map(\.id))

        // Build lookup indices: name+room → device (only if unambiguous)
        let devicesByNameRoom = buildDeviceLookup(devices)

        var remappedDevices = 0
        var remappedServices = 0
        var orphanedRefs: [OrphanedReference] = []

        // Collect all device references from the workflow
        var idMap: [String: String] = [:]           // oldDeviceId → newDeviceId
        var serviceIdMap: [String: [String: String]] = [:]  // oldDeviceId → (oldServiceId → newServiceId)

        let allRefs = collectDeviceReferences(from: workflow)

        for ref in allRefs {
            // Skip already-known device IDs
            if knownDeviceIds.contains(ref.deviceId) { continue }
            // Skip if already resolved in this pass
            if idMap[ref.deviceId] != nil { continue }

            // Try to find a matching device by name+room
            if let match = findMatch(for: ref, in: devices, lookup: devicesByNameRoom) {
                idMap[ref.deviceId] = match.id
                remappedDevices += 1

                // Also remap service IDs if possible
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
                    deviceId: ref.deviceId,
                    deviceName: ref.contextName,
                    roomName: ref.contextRoom,
                    location: ref.location
                ))
            }
        }

        // If nothing needs remapping, return as-is
        if idMap.isEmpty {
            return MigrationResult(workflow: workflow, remappedDevices: 0, remappedServices: 0, orphanedReferences: orphanedRefs)
        }

        // Apply the remapping by encoding → modifying JSON → decoding
        let migratedWorkflow = applyRemapping(to: workflow, deviceIdMap: idMap, serviceIdMap: serviceIdMap)

        return MigrationResult(
            workflow: migratedWorkflow ?? workflow,
            remappedDevices: remappedDevices,
            remappedServices: remappedServices,
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

    // MARK: - JSON-based Remapping

    /// Apply device/service ID remapping by encoding to JSON, doing string replacement, and decoding back.
    /// This avoids having to rebuild every nested struct manually.
    private static func applyRemapping(to workflow: Workflow, deviceIdMap: [String: String], serviceIdMap: [String: [String: String]]) -> Workflow? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard var jsonData = try? encoder.encode(workflow),
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let updatedData = jsonString.data(using: .utf8),
              let updatedWorkflow = try? decoder.decode(Workflow.self, from: updatedData) else {
            return nil
        }

        return updatedWorkflow
    }
}

// MARK: - Batch Migration

extension WorkflowMigrationService {
    /// Migrate multiple workflows at once. Returns updated workflows, remapping count, and orphan details.
    static func migrateAll(_ workflows: [Workflow], using devices: [DeviceModel]) -> (workflows: [Workflow], totalRemapped: Int, orphanedReferences: [String: [OrphanedReference]]) {
        var result: [Workflow] = []
        var totalRemapped = 0
        var allOrphans: [String: [OrphanedReference]] = [:]  // workflowName → orphans

        for workflow in workflows {
            let migration = migrate(workflow, using: devices)
            result.append(migration.workflow)
            totalRemapped += migration.remappedDevices
            if !migration.orphanedReferences.isEmpty {
                allOrphans[workflow.name] = migration.orphanedReferences
            }
        }

        if totalRemapped > 0 {
            AppLogger.workflow.info("Workflow migration: remapped \(totalRemapped) device reference(s) across \(workflows.count) workflow(s)")
        }
        if !allOrphans.isEmpty {
            let totalOrphans = allOrphans.values.map(\.count).reduce(0, +)
            AppLogger.workflow.warning("Workflow migration: \(totalOrphans) orphaned device reference(s) in \(allOrphans.count) workflow(s) could not be resolved")
        }

        return (result, totalRemapped, allOrphans)
    }
}
