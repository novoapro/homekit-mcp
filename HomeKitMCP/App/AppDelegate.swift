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
        container.homeKitManager.$cachedDevices
            .first(where: { !$0.isEmpty })
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] devices in
                guard let self else { return }
                Task {
                    let workflows = await self.container.workflowStorageService.getAllWorkflows()
                    guard !workflows.isEmpty else { return }
                    let scenes = await MainActor.run { self.container.homeKitManager.cachedScenes }
                    let migration = WorkflowMigrationService.migrateAll(workflows, using: devices, scenes: scenes)
                    let totalRemapped = migration.totalRemappedDevices + migration.totalRemappedScenes
                    if totalRemapped > 0 {
                        await self.container.workflowStorageService.replaceAll(workflows: migration.workflows)
                        AppLogger.workflow.info("Startup migration: remapped \(migration.totalRemappedDevices) device(s), \(migration.totalRemappedScenes) scene(s)")
                    }
                    // Log orphans
                    for (workflowName, orphans) in migration.orphanedReferences {
                        for orphan in orphans {
                            let kind = orphan.isScene ? "scene" : "device"
                            let desc = orphan.referenceName ?? orphan.referenceId
                            AppLogger.workflow.warning("Startup migration: workflow '\(workflowName)' has orphaned \(kind) '\(desc)' in \(orphan.location)")
                            let logEntry = StateChangeLog(
                                id: UUID(), timestamp: Date(),
                                deviceId: workflowName, deviceName: workflowName,
                                characteristicType: "orphan-detection",
                                oldValue: nil, newValue: nil,
                                category: .workflowError,
                                errorDetails: "Orphaned \(kind) '\(desc)' in \(orphan.location) — not found after migration"
                            )
                            await self.container.loggingService.logEntry(logEntry)
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
