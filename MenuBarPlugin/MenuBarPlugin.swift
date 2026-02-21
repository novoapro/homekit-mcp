import AppKit

/// AppKit bundle plugin that provides NSStatusItem menu bar functionality for the Mac Catalyst app.
/// Loaded at runtime by the Catalyst app via NSBundle.
/// Principal class specified in Info.plist as "MenuBarPlugin.MenuBarPlugin".
class MenuBarPlugin: NSObject {
    private var statusItem: NSStatusItem?
    private var actionHandler: ((String) -> Void)?
    private var isRunning = false

    /// Called by the Catalyst app to set up the menu bar icon.
    @objc func setupMenuBar(actionHandler: @escaping (String) -> Void) {
        NSLog("MenuBarPlugin: setupMenuBar called")
        self.actionHandler = actionHandler

        // Bring the app to foreground on launch so the window is visible
        NSApplication.shared.activate(ignoringOtherApps: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Load custom icon from main app bundle's asset catalog
            let mainBundle = Bundle.main
            var image: NSImage?
            if let catalogImage = mainBundle.image(forResource: "MenuBarIcon") {
                image = catalogImage
                NSLog("MenuBarPlugin: Custom menu bar icon loaded from asset catalog")
            } else {
                // Fallback to SF Symbol if custom icon not found
                image = NSImage(systemSymbolName: "house.fill", accessibilityDescription: "HomeKit MCP")
                NSLog("MenuBarPlugin: Falling back to system symbol 'house.fill'")
            }
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        } else {
            NSLog("MenuBarPlugin: Failed to get status item button")
        }

        rebuildMenu()
        NSLog("MenuBarPlugin: Menu rebuilt")
    }

    /// Called by the Catalyst app to update the server status display.
    @objc func updateStatus(isRunning: Bool) {
        self.isRunning = isRunning
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle = isRunning ? "MCP Server: Running" : "MCP Server: Stopped"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit HomeKit MCP", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        actionHandler?("showWindow")
    }

    @objc private func quit() {
        actionHandler?("quit")
    }
}
