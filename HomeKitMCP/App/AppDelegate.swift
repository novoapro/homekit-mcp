import UIKit
import Combine

class AppDelegate: UIResponder, UIApplicationDelegate {
    let storageService = StorageService()
    let loggingService = LoggingService()
    lazy var homeKitManager = HomeKitManager(loggingService: loggingService, webhookService: webhookService)
    lazy var webhookService = WebhookService(storage: storageService)
    lazy var mcpServer = MCPServer(homeKitManager: homeKitManager, loggingService: loggingService, port: storageService.mcpServerPort)
    lazy var homeKitViewModel = HomeKitViewModel(homeKitManager: homeKitManager)
    lazy var logViewModel = LogViewModel(loggingService: loggingService)
    lazy var settingsViewModel = SettingsViewModel(storage: storageService, webhookService: webhookService, mcpServer: mcpServer)

    private var cancellables = Set<AnyCancellable>()

    #if targetEnvironment(macCatalyst)
    var menuBarController: MenuBarController?
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
        // Discard any extra sessions to enforce single-window
        let existingSessions = application.openSessions
        if existingSessions.count > 1 {
            for session in existingSessions where session != connectingSceneSession {
                if session.scene == nil {
                    application.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
                }
            }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        return config
    }

    func applicationWillTerminate(_ application: UIApplication) {
        mcpServer.stop()
    }

    private func startMCPServerIfEnabled() {
        guard storageService.mcpServerEnabled else { return }
        do {
            try mcpServer.start()
            print("MCP Server started on port \(storageService.mcpServerPort)")
        } catch {
            print("Failed to start MCP Server: \(error)")
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
                // Exit the app
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    exit(0)
                }
            }
            .store(in: &cancellables)
    }
    #endif
}
