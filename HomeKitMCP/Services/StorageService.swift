import Foundation

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini (Google)"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        }
    }
}

// MARK: - Storage Service

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
    @Published var detailedLogsEnabled: Bool {
        didSet { defaults.set(detailedLogsEnabled, forKey: Keys.detailedLogsEnabled) }
    }
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Keys.aiEnabled) }
    }
    @Published var aiProvider: AIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider) }
    }
    @Published var aiModelId: String {
        didSet { defaults.set(aiModelId, forKey: Keys.aiModelId) }
    }

    init() {
        // Register defaults for keys that need non-nil/non-zero initial values
        defaults.register(defaults: [
            Keys.mcpServerPort: 3000,
            Keys.webhookEnabled: true,
            Keys.mcpServerEnabled: true,
            Keys.hideRoomNameInTheApp: true,
            Keys.detailedLogsEnabled: false,
            Keys.aiEnabled: false,
            Keys.aiProvider: AIProvider.claude.rawValue,
            Keys.aiModelId: ""
        ])

        self.webhookURL = defaults.string(forKey: Keys.webhookURL)
        self.mcpServerPort = defaults.integer(forKey: Keys.mcpServerPort)
        self.webhookEnabled = defaults.bool(forKey: Keys.webhookEnabled)
        self.mcpServerEnabled = defaults.bool(forKey: Keys.mcpServerEnabled)
        self.hideRoomNameInTheApp = defaults.bool(forKey: Keys.hideRoomNameInTheApp)
        self.detailedLogsEnabled = defaults.bool(forKey: Keys.detailedLogsEnabled)
        self.aiEnabled = defaults.bool(forKey: Keys.aiEnabled)
        self.aiProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aiProvider) ?? "") ?? .claude
        self.aiModelId = defaults.string(forKey: Keys.aiModelId) ?? ""
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

    nonisolated func readDetailedLogsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.detailedLogsEnabled)
    }

    nonisolated func readAIEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.aiEnabled)
    }

    nonisolated func readAIProvider() -> AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: Keys.aiProvider) ?? "") ?? .claude
    }

    nonisolated func readAIModelId() -> String {
        UserDefaults.standard.string(forKey: Keys.aiModelId) ?? ""
    }

    private enum Keys {
        static let webhookURL = "webhookURL"
        static let mcpServerPort = "mcpServerPort"
        static let webhookEnabled = "webhookEnabled"
        static let mcpServerEnabled = "mcpServerEnabled"
        static let hideRoomNameInTheApp = "hideRoomNameInTheApp"
        static let detailedLogsEnabled = "detailedLogsEnabled"
        static let aiEnabled = "aiEnabled"
        static let aiProvider = "aiProvider"
        static let aiModelId = "aiModelId"
    }
}
