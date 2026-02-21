#if targetEnvironment(macCatalyst)
import UIKit
import Combine

/// Loads the AppKit plugin bundle at runtime and bridges menu bar actions to UIKit.
@MainActor
class MenuBarController {
    private var plugin: NSObject?
    private var mcpServer: MCPServer?
    private var cancellables = Set<AnyCancellable>()

    func setup(mcpServer: MCPServer? = nil) {
        self.mcpServer = mcpServer
        loadPlugin()
        observeServerStatus()
    }

    private func loadPlugin() {
        AppLogger.menuBar.debug("Starting plugin load...")
        // The plugin bundle is embedded in the app's Resources directory
        guard let bundleURL = Bundle.main.url(forResource: "MenuBarPlugin", withExtension: "bundle") else {
            AppLogger.menuBar.error("Plugin bundle not found in resources")
            return
        }
        AppLogger.menuBar.debug("Found bundle at \(bundleURL.path)")

        guard let bundle = Bundle(url: bundleURL) else {
            AppLogger.menuBar.error("Could not create bundle from \(bundleURL)")
            return
        }

        do {
            try bundle.loadAndReturnError()
            AppLogger.menuBar.debug("Bundle loaded successfully")
        } catch {
            AppLogger.menuBar.error("Failed to load plugin bundle: \(error)")
            return
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            AppLogger.menuBar.error("Could not get principal class from plugin")
            return
        }
        AppLogger.menuBar.debug("Principal class found: \(String(describing: principalClass))")

        let instance = principalClass.init()
        self.plugin = instance
        AppLogger.menuBar.debug("Plugin instance created")

        // Call setupMenuBar(actionHandler:) via selector to avoid cross-target type dependency
        let selector = NSSelectorFromString("setupMenuBarWithActionHandler:")
        if instance.responds(to: selector) {
            AppLogger.menuBar.debug("Configuring menu bar...")
            let handler: @convention(block) (String) -> Void = { [weak self] action in
                self?.handleAction(action)
            }
            instance.perform(selector, with: handler)
            AppLogger.menuBar.debug("Setup call performed")
        } else {
            AppLogger.menuBar.warning("Instance does not respond to setup selector")
        }
    }

    private func observeServerStatus() {
        mcpServer?.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.updatePluginStatus(isRunning: isRunning)
            }
            .store(in: &cancellables)
    }

    private func updatePluginStatus(isRunning: Bool) {
        let selector = NSSelectorFromString("updateStatusWithIsRunning:")
        if let plugin, plugin.responds(to: selector) {
            plugin.perform(selector, with: NSNumber(value: isRunning))
        }
    }

    private func handleAction(_ action: String) {
        DispatchQueue.main.async {
            switch action {
            case "showWindow":
                self.showMainWindow()
            case "quit":
                self.quitApp()
            default:
                break
            }
        }
    }

    private func showMainWindow() {
        // First try to find a foreground or connected scene and activate it
        let connectedScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let existing = connectedScenes.first {
            existing.windows.forEach { $0.makeKeyAndVisible() }
            UIApplication.shared.requestSceneSessionActivation(
                existing.session, userActivity: nil, options: nil, errorHandler: nil
            )
            return
        }

        // Check for any disconnected sessions we can reactivate
        let allSessions = UIApplication.shared.openSessions
        if let disconnected = allSessions.first(where: { $0.scene == nil }) {
            UIApplication.shared.requestSceneSessionActivation(
                disconnected, userActivity: nil, options: nil, errorHandler: { error in
                    AppLogger.menuBar.warning("Scene reactivation error: \(error)")
                    // Fallback: create a brand new session
                    UIApplication.shared.requestSceneSessionActivation(
                        nil, userActivity: nil, options: nil, errorHandler: nil
                    )
                }
            )
            return
        }

        // No sessions at all — create a new one
        UIApplication.shared.requestSceneSessionActivation(
            nil, userActivity: nil, options: nil, errorHandler: { error in
                AppLogger.menuBar.warning("Scene activation error: \(error)")
            }
        )
    }

    private func quitApp() {
        // Post notification so AppDelegate can clean up
        NotificationCenter.default.post(name: .menuBarQuitRequested, object: nil)
    }
}

extension Notification.Name {
    static let menuBarQuitRequested = Notification.Name("menuBarQuitRequested")
}
#endif
