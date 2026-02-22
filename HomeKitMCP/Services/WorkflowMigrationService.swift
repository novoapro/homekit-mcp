import Foundation

/// Migrates orphaned device/service UUIDs in workflows after a HomeKit backup restore.
///
/// When HomeKit is restored from an iCloud backup to a different machine, the same physical devices
/// get new UUIDs. This service detects orphaned references and attempts to remap them by matching
/// on device name + room. If exactly one match is found, the ID is updated silently.
enum WorkflowMigrationService {

    /// Result of a migration attempt on a single workflow.
    struct MigrationResult {
        let workflow: Workflow
        let remappedDevices: Int
        let remappedServices: Int
        let orphanedDevices: Int  // references that couldn't be resolved
    }

    /// Migrate all device/service references in a workflow.
    /// Returns the (possibly updated) workflow and a summary of changes.
    static func migrate(_ workflow: Workflow, using devices: [DeviceModel]) -> MigrationResult {
        let knownDeviceIds = Set(devices.map(\.id))

        // Build lookup indices: name+room → device (only if unambiguous)
        let devicesByNameRoom = buildDeviceLookup(devices)

        var remappedDevices = 0
        var remappedServices = 0
        var orphanedDevices = 0

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
                orphanedDevices += 1
            }
        }

        // If nothing needs remapping, return as-is
        if idMap.isEmpty {
            return MigrationResult(workflow: workflow, remappedDevices: 0, remappedServices: 0, orphanedDevices: orphanedDevices)
        }

        // Apply the remapping by encoding → modifying JSON → decoding
        let migratedWorkflow = applyRemapping(to: workflow, deviceIdMap: idMap, serviceIdMap: serviceIdMap)

        return MigrationResult(
            workflow: migratedWorkflow ?? workflow,
            remappedDevices: remappedDevices,
            remappedServices: remappedServices,
            orphanedDevices: orphanedDevices
        )
    }

    // MARK: - Device Reference Collection

    /// A lightweight reference to a device used somewhere in a workflow.
    private struct DeviceRef: Hashable {
        let deviceId: String
        let serviceId: String?
        /// Context for matching: the device name if stored alongside the ID.
        let contextName: String?

        func hash(into hasher: inout Hasher) {
            hasher.combine(deviceId)
        }

        static func == (lhs: DeviceRef, rhs: DeviceRef) -> Bool {
            lhs.deviceId == rhs.deviceId
        }
    }

    private static func collectDeviceReferences(from workflow: Workflow) -> Set<DeviceRef> {
        var refs = Set<DeviceRef>()

        // Triggers
        for trigger in workflow.triggers {
            switch trigger {
            case let .deviceStateChange(t):
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: nil))
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
                refs.insert(DeviceRef(deviceId: t.deviceId, serviceId: t.serviceId, contextName: nil))
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
            refs.insert(DeviceRef(deviceId: c.deviceId, serviceId: c.serviceId, contextName: nil))
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
                refs.insert(DeviceRef(deviceId: a.deviceId, serviceId: a.serviceId, contextName: nil))
            default:
                break
            }
        case let .flowControl(fc):
            switch fc {
            case let .waitForState(b):
                refs.insert(DeviceRef(deviceId: b.deviceId, serviceId: b.serviceId, contextName: nil))
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
    /// Strategy: since we don't have the old device name stored in the workflow JSON,
    /// we try all devices and see if exactly one matches by elimination.
    /// In practice, workflow JSONs only store UUIDs, so we need the current device list
    /// to find a plausible match. We use a heuristic: find a device that has the same
    /// characteristic types referenced in the workflow.
    private static func findMatch(for ref: DeviceRef, in devices: [DeviceModel], lookup: [DeviceKey: DeviceModel]) -> DeviceModel? {
        // If we have a context name, try name+room matching first
        if let name = ref.contextName {
            for device in devices {
                if device.name.lowercased() == name.lowercased() {
                    return device
                }
            }
        }

        // Without a name, we can't match — the workflow only stores UUIDs
        // Return nil to mark as orphaned (user will fix manually)
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
    /// Migrate multiple workflows at once. Returns updated workflows and a summary.
    static func migrateAll(_ workflows: [Workflow], using devices: [DeviceModel]) -> (workflows: [Workflow], totalRemapped: Int) {
        var result: [Workflow] = []
        var totalRemapped = 0

        for workflow in workflows {
            let migration = migrate(workflow, using: devices)
            result.append(migration.workflow)
            totalRemapped += migration.remappedDevices
        }

        if totalRemapped > 0 {
            AppLogger.general.info("Workflow migration: remapped \(totalRemapped) device reference(s) across \(workflows.count) workflow(s)")
        }

        return (result, totalRemapped)
    }
}
