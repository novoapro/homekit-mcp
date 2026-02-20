import UIKit
import Combine

class AppDelegate: UIResponder, UIApplicationDelegate {
    let storageService = StorageService()
    let loggingService = LoggingService()
    let configService = DeviceConfigurationService()
    let workflowStorageService = WorkflowStorageService()
    let workflowExecutionLogService = WorkflowExecutionLogService()
    let keychainService = KeychainService()
    lazy var webhookService = WebhookService(storage: storageService, loggingService: loggingService)
    lazy var homeKitManager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, configService: configService, storage: storageService)
    lazy var workflowEngine: WorkflowEngine = {
        let engine = WorkflowEngine(
            storageService: workflowStorageService,
            homeKitManager: homeKitManager,
            loggingService: loggingService,
            executionLogService: workflowExecutionLogService
        )
        return engine
    }()
    lazy var aiWorkflowService = AIWorkflowService(storage: storageService, homeKitManager: homeKitManager, keychainService: keychainService)
    lazy var mcpServer = MCPServer(
        homeKitManager: homeKitManager, loggingService: loggingService, configService: configService, storage: storageService,
        workflowStorageService: workflowStorageService, workflowEngine: workflowEngine, workflowExecutionLogService: workflowExecutionLogService,
        port: storageService.mcpServerPort
    )
    lazy var homeKitViewModel = HomeKitViewModel(homeKitManager: homeKitManager, configService: configService)
    lazy var logViewModel = LogViewModel(loggingService: loggingService, storage: storageService)
    lazy var settingsViewModel = SettingsViewModel(
        storage: storageService, webhookService: webhookService, mcpServer: mcpServer, configService: configService,
        keychainService: keychainService, aiWorkflowService: aiWorkflowService
    )
    lazy var workflowViewModel = WorkflowViewModel(storageService: workflowStorageService, executionLogService: workflowExecutionLogService, workflowEngine: workflowEngine, homeKitManager: homeKitManager)

    private var cancellables = Set<AnyCancellable>()

    #if targetEnvironment(macCatalyst)
    var menuBarController: MenuBarController?
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        installSignalHandlers()
        setupWorkflowEngine()
        startMCPServerIfEnabled()

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
        mcpServer.stop()
    }

    /// Trap SIGTERM/SIGINT so the Vapor server is shut down even if the process is killed externally.
    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            // Access the shared AppDelegate and stop the server synchronously
            guard let delegate = UIApplication.shared.delegate as? AppDelegate else {
                exit(0)
            }
            delegate.mcpServer.stop()
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }

    private func setupWorkflowEngine() {
        homeKitManager.workflowEngine = workflowEngine
        Task {
            await workflowEngine.registerEvaluator(DeviceStateChangeTriggerEvaluator())
        }
    }

    private func startMCPServerIfEnabled() {
        guard storageService.mcpServerEnabled else { return }
        do {
            try mcpServer.start()
            AppLogger.server.info("MCP Server started on port \(self.storageService.mcpServerPort)")
        } catch {
            AppLogger.server.error("Failed to start MCP Server: \(error)")
        }
    }

    #if targetEnvironment(macCatalyst)
    private func setupMenuBar() {
        menuBarController = MenuBarController()
        menuBarController?.setup(mcpServer: mcpServer)
    }

    private func observeQuitNotification() {
        NotificationCenter.default.publisher(for: .menuBarQuitRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mcpServer.stop()
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                // Give Vapor time to release the port before exiting
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    exit(0)
                }
            }
            .store(in: &cancellables)
    }
    #endif
}
