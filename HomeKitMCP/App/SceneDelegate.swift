import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        #if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            titlebar.toolbarStyle = .unified
        }
        // Sized to accommodate sidebar + content layout (matches Apple Home app proportions)
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 550)
        #endif
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Ensure the window is visible when the scene activates
        windowScene.windows.forEach { $0.makeKeyAndVisible() }
    }
}
