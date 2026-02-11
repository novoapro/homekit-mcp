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
        // The plugin bundle is embedded in the app's Resources directory
        guard let bundleURL = Bundle.main.url(forResource: "MenuBarPlugin", withExtension: "bundle") else {
            print("MenuBarController: Plugin bundle not found in resources")
            return
        }

        guard let bundle = Bundle(url: bundleURL) else {
            print("MenuBarController: Could not create bundle from \(bundleURL)")
            return
        }

        do {
            try bundle.loadAndReturnError()
        } catch {
            print("MenuBarController: Failed to load plugin bundle: \(error)")
            return
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            print("MenuBarController: Could not get principal class from plugin")
            return
        }

        let instance = principalClass.init()
        self.plugin = instance

        // Call setupMenuBar(actionHandler:) via selector to avoid cross-target type dependency
        let selector = NSSelectorFromString("setupMenuBarWithActionHandler:")
        if instance.responds(to: selector) {
            let handler: @convention(block) (String) -> Void = { [weak self] action in
                self?.handleAction(action)
            }
            instance.perform(selector, with: handler)
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
        // Try to find an existing connected window scene and bring it forward
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            // Scene still exists — just activate it
            UIApplication.shared.requestSceneSessionActivation(
                windowScene.session, userActivity: nil, options: nil, errorHandler: nil
            )
            return
        }

        // No connected scenes — request a brand new one (pass nil for session)
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
