import UIKit
import Combine

class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Single source of truth for all service and view model creation.
    let container = ServiceContainer()

    private var cancellables = Set<AnyCancellable>()

    #if targetEnvironment(macCatalyst)
    var menuBarController: MenuBarController?
    #endif

    // MARK: - Lifecycle Accessors (for HomeKitMCPApp environment objects)

    var homeKitViewModel: HomeKitViewModel { container.homeKitViewModel }
    var logViewModel: LogViewModel { container.logViewModel }
    var settingsViewModel: SettingsViewModel { container.settingsViewModel }
    var workflowViewModel: WorkflowViewModel { container.workflowViewModel }

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        installSignalHandlers()
        setupWorkflowEngine()
        startMCPServerIfEnabled()
        container.appleSignInService.checkExistingCredential()
        container.settingsViewModel.refreshSunEventCoordinatesIfNeeded()

        #if targetEnvironment(macCatalyst)
        setupMenuBar()
        observeQuitNotification()
        #endif

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Discard extra *connected* sessions to enforce single-window,
        // but keep disconnected sessions so the window can be restored from the menu bar
        let connectedScenes = application.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        if connectedScenes.count > 1 {
            for scene in connectedScenes where scene.session != connectingSceneSession {
                application.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func applicationWillTerminate(_ application: UIApplication) {
        container.mcpServer.stop()
    }

    // MARK: - Private Setup

    /// Trap SIGTERM/SIGINT so the Vapor server is shut down even if the process is killed externally.
    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            guard let delegate = UIApplication.shared.delegate as? AppDelegate else {
                exit(0)
            }
            delegate.container.mcpServer.stop()
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }

    private func setupWorkflowEngine() {
        // Wire cross-service subscriptions (HomeKitManager → WorkflowEngine via Combine).
        container.wireServices()
        Task {
            await container.workflowEngine.registerEvaluator(DeviceStateChangeTriggerEvaluator())
            await container.scheduleTriggerManager.setEngine(container.workflowEngine)
            await container.scheduleTriggerManager.setStorage(container.storageService)
            let workflows = await container.workflowStorageService.getAllWorkflows()
            await container.scheduleTriggerManager.reloadSchedules(workflows: workflows)
        }
        container.workflowStorageService.workflowsSubject
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] workflows in
                guard let self else { return }
                Task {
                    await self.container.scheduleTriggerManager.reloadSchedules(workflows: workflows)
                }
            }
            .store(in: &cancellables)

        // One-shot migration: when HomeKit devices first become available, check all
        // workflows for orphaned device UUIDs and remap them automatically.
        // Also performs one-time migration from HomeKit UUIDs to stable registry IDs.
        container.homeKitManager.$cachedDevices
            .first(where: { !$0.isEmpty })
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] devices in
                guard let self else { return }
                Task {
                    var workflows = await self.container.workflowStorageService.getAllWorkflows()
                    guard !workflows.isEmpty else { return }
                    let scenes = await MainActor.run { self.container.homeKitManager.cachedScenes }

                    // --- Legacy orphan migration (name+room matching) ---
                    let migration = WorkflowMigrationService.migrateAll(workflows, using: devices, scenes: scenes)
                    let totalRemapped = migration.totalRemappedDevices + migration.totalRemappedScenes
                    if totalRemapped > 0 {
                        await self.container.workflowStorageService.replaceAll(workflows: migration.workflows)
                        workflows = migration.workflows
                        AppLogger.workflow.info("Startup migration: remapped \(migration.totalRemappedDevices) device(s), \(migration.totalRemappedScenes) scene(s)")
                    }
                    // Log orphans
                    for (workflowName, orphans) in migration.orphanedReferences {
                        for orphan in orphans {
                            let kind = orphan.isScene ? "scene" : "device"
                            let desc = orphan.referenceName ?? orphan.referenceId
                            AppLogger.workflow.warning("Startup migration: workflow '\(workflowName)' has orphaned \(kind) '\(desc)' in \(orphan.location)")
                            let logEntry = StateChangeLog.workflowError(
                                workflowId: workflowName,
                                workflowName: workflowName,
                                errorDetails: "Orphaned \(kind) '\(desc)' in \(orphan.location) — not found after migration"
                            )
                            await self.container.loggingService.logEntry(logEntry)
                        }
                    }

                    // --- Registry normalization: HomeKit UUIDs → stable IDs (runs every startup, idempotent) ---
                    do {
                        let registry = self.container.deviceRegistryService
                        // Ensure registry is synced (may not have completed yet)
                        await registry.syncDevices(devices)
                        await registry.syncScenes(scenes)

                        // Clean up orphaned duplicates from the init() reverse-lookup bug
                        let dedupResult = await registry.deduplicateOrphanedEntries()
                        var currentWorkflows = workflows
                        if dedupResult.hasChanges {
                            AppLogger.registry.info("Startup dedup: removed \(dedupResult.removedDeviceCount) device(s), \(dedupResult.removedSceneCount) scene(s)")
                            if !dedupResult.deviceIdRemapping.isEmpty || !dedupResult.sceneIdRemapping.isEmpty
                                || !dedupResult.serviceIdRemapping.isEmpty || !dedupResult.characteristicIdRemapping.isEmpty {
                                var allServiceRemapping = dedupResult.serviceIdRemapping
                                for (oldCharId, newCharId) in dedupResult.characteristicIdRemapping {
                                    allServiceRemapping[oldCharId] = newCharId
                                }
                                let combinedServiceMap: [String: [String: String]] = allServiceRemapping.isEmpty ? [:] : ["_all": allServiceRemapping]
                                var updatedWorkflows: [Workflow] = []
                                for workflow in currentWorkflows {
                                    if let remapped = WorkflowMigrationService.applyRemapping(
                                        to: workflow,
                                        deviceIdMap: dedupResult.deviceIdRemapping,
                                        serviceIdMap: combinedServiceMap,
                                        sceneIdMap: dedupResult.sceneIdRemapping
                                    ) {
                                        updatedWorkflows.append(remapped)
                                    } else {
                                        updatedWorkflows.append(workflow)
                                    }
                                }
                                await self.container.workflowStorageService.replaceAll(workflows: updatedWorkflows)
                                currentWorkflows = updatedWorkflows
                                AppLogger.registry.info("Startup dedup: remapped workflow references")
                            }
                        }
                        let (migratedWorkflows, count) = WorkflowMigrationService.migrateToStableIds(currentWorkflows, registry: registry)
                        if count > 0 {
                            await self.container.workflowStorageService.replaceAll(workflows: migratedWorkflows)
                            currentWorkflows = migratedWorkflows
                            AppLogger.registry.info("Startup normalization: converted \(count) reference(s) to stable IDs")
                        }
                        if !self.container.storageService.readRegistryMigrationCompleted() {
                            await MainActor.run {
                                self.container.storageService.registryMigrationCompleted = true
                            }
                            AppLogger.registry.info("Registry migration completed")
                        }

                        // Deep validation: check serviceId + characteristicType references against registry
                        let validation = await WorkflowMigrationService.validateAndRepairReferences(
                            currentWorkflows, registry: registry
                        )
                        if !validation.autoFixed.isEmpty {
                            await self.container.workflowStorageService.replaceAll(workflows: validation.updatedWorkflows)
                            AppLogger.registry.info("Startup validation: auto-fixed \(validation.autoFixed.count) issue(s)")
                        }
                        if !validation.unresolvable.isEmpty {
                            AppLogger.registry.warning("Startup validation: \(validation.unresolvable.count) unresolvable issue(s)")
                            for issue in validation.unresolvable {
                                let logEntry = StateChangeLog.workflowError(
                                    workflowId: issue.workflowId.uuidString,
                                    workflowName: issue.workflowName,
                                    errorDetails: "[\(issue.location)] \(issue.detail)"
                                )
                                await self.container.loggingService.logEntry(logEntry)
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func startMCPServerIfEnabled() {
        guard container.storageService.mcpServerEnabled else { return }
        Task {
            do {
                try await container.mcpServer.start()
                AppLogger.server.info("MCP Server started on port \(self.container.storageService.mcpServerPort)")
            } catch {
                AppLogger.server.error("Failed to start MCP Server: \(error)")
            }
        }
    }

    #if targetEnvironment(macCatalyst)
    private func setupMenuBar() {
        menuBarController = MenuBarController()
        menuBarController?.setup(mcpServer: container.mcpServer)
    }

    private func observeQuitNotification() {
        NotificationCenter.default.publisher(for: .menuBarQuitRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.container.mcpServer.stop()
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    exit(0)
                }
            }
            .store(in: &cancellables)
    }
    #endif
}
