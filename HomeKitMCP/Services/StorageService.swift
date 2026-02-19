import Foundation

@MainActor
class StorageService: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var webhookURL: String? {
        didSet { defaults.set(webhookURL, forKey: Keys.webhookURL) }
    }
    @Published var mcpServerPort: Int {
        didSet { defaults.set(mcpServerPort, forKey: Keys.mcpServerPort) }
    }
    @Published var webhookEnabled: Bool {
        didSet { defaults.set(webhookEnabled, forKey: Keys.webhookEnabled) }
    }
    @Published var mcpServerEnabled: Bool {
        didSet { defaults.set(mcpServerEnabled, forKey: Keys.mcpServerEnabled) }
    }
    @Published var hideRoomNameInTheApp: Bool {
        didSet { defaults.set(hideRoomNameInTheApp, forKey: Keys.hideRoomNameInTheApp) }
    }

    init() {
        // Register defaults for keys that need non-nil/non-zero initial values
        defaults.register(defaults: [
            Keys.mcpServerPort: 3000,
            Keys.webhookEnabled: true,
            Keys.mcpServerEnabled: true,
            Keys.hideRoomNameInTheApp: true
        ])

        self.webhookURL = defaults.string(forKey: Keys.webhookURL)
        self.mcpServerPort = defaults.integer(forKey: Keys.mcpServerPort)
        self.webhookEnabled = defaults.bool(forKey: Keys.webhookEnabled)
        self.mcpServerEnabled = defaults.bool(forKey: Keys.mcpServerEnabled)
        self.hideRoomNameInTheApp = defaults.bool(forKey: Keys.hideRoomNameInTheApp)
    }

    func isWebhookConfigured() -> Bool {
        guard let url = webhookURL, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    // MARK: - Nonisolated Readers

    /// Thread-safe readers that go directly to UserDefaults.
    /// Use these from nonisolated or actor-isolated contexts that need read-only access.

    nonisolated func readHideRoomName() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.hideRoomNameInTheApp)
    }

    nonisolated func readWebhookURL() -> String? {
        UserDefaults.standard.string(forKey: Keys.webhookURL)
    }

    nonisolated func readWebhookEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.webhookEnabled)
    }

    private enum Keys {
        static let webhookURL = "webhookURL"
        static let mcpServerPort = "mcpServerPort"
        static let webhookEnabled = "webhookEnabled"
        static let mcpServerEnabled = "mcpServerEnabled"
        static let hideRoomNameInTheApp = "hideRoomNameInTheApp"
    }
}
