#if targetEnvironment(macCatalyst)
import UIKit
import Combine

/// Loads the AppKit plugin bundle at runtime and bridges menu bar actions to UIKit.
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
        print("MenuBarController: Starting plugin load...")
        // The plugin bundle is embedded in the app's Resources directory
        guard let bundleURL = Bundle.main.url(forResource: "MenuBarPlugin", withExtension: "bundle") else {
            print("MenuBarController: Plugin bundle not found in resources")
            return
        }
        print("MenuBarController: Found bundle at \(bundleURL.path)")

        guard let bundle = Bundle(url: bundleURL) else {
            print("MenuBarController: Could not create bundle from \(bundleURL)")
            return
        }

        do {
            try bundle.loadAndReturnError()
            print("MenuBarController: Bundle loaded successfully")
        } catch {
            print("MenuBarController: Failed to load plugin bundle: \(error)")
            return
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            print("MenuBarController: Could not get principal class from plugin")
            return
        }
        print("MenuBarController: Principal class found: \(String(describing: principalClass))")

        let instance = principalClass.init()
        self.plugin = instance
        print("MenuBarController: Plugin instance created")

        // Call setupMenuBar(actionHandler:) via selector to avoid cross-target type dependency
        let selector = NSSelectorFromString("setupMenuBarWithActionHandler:")
        if instance.responds(to: selector) {
            print("MenuBarController: Configuring menu bar...")
            let handler: @convention(block) (String) -> Void = { [weak self] action in
                self?.handleAction(action)
            }
            instance.perform(selector, with: handler)
            print("MenuBarController: Setup call performed")
        } else {
            print("MenuBarController: Instance does not respond to setup selector")
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
                    print("Scene reactivation error: \(error)")
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
                print("Scene activation error: \(error)")
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
