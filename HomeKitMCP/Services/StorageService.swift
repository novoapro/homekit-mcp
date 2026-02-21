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
class StorageService: ObservableObject, StorageServiceProtocol {
    private let defaults = UserDefaults.standard
    let keychainService: KeychainService

    @Published var webhookURL: String? {
        didSet {
            if let url = webhookURL, !url.isEmpty {
                keychainService.save(key: KeychainService.Keys.webhookURL, value: url)
            } else {
                keychainService.delete(key: KeychainService.Keys.webhookURL)
            }
        }
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
    @Published var mcpServerBindAddress: String {
        didSet { defaults.set(mcpServerBindAddress, forKey: Keys.mcpServerBindAddress) }
    }
    @Published var sunEventLatitude: Double {
        didSet { defaults.set(sunEventLatitude, forKey: Keys.sunEventLatitude) }
    }
    @Published var sunEventLongitude: Double {
        didSet { defaults.set(sunEventLongitude, forKey: Keys.sunEventLongitude) }
    }
    @Published var pollingEnabled: Bool {
        didSet { defaults.set(pollingEnabled, forKey: Keys.pollingEnabled) }
    }
    @Published var pollingInterval: Int {
        didSet { defaults.set(pollingInterval, forKey: Keys.pollingInterval) }
    }
    @Published var workflowsEnabled: Bool {
        didSet { defaults.set(workflowsEnabled, forKey: Keys.workflowsEnabled) }
    }
    @Published var autoBackupEnabled: Bool {
        didSet { defaults.set(autoBackupEnabled, forKey: Keys.autoBackupEnabled) }
    }
    @Published var deviceStateLoggingEnabled: Bool {
        didSet { defaults.set(deviceStateLoggingEnabled, forKey: Keys.deviceStateLoggingEnabled) }
    }

    init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService

        // Register defaults for keys that need non-nil/non-zero initial values
        defaults.register(defaults: [
            Keys.mcpServerPort: 3000,
            Keys.webhookEnabled: true,
            Keys.mcpServerEnabled: true,
            Keys.hideRoomNameInTheApp: true,
            Keys.detailedLogsEnabled: false,
            Keys.aiEnabled: false,
            Keys.aiProvider: AIProvider.claude.rawValue,
            Keys.aiModelId: "",
            Keys.mcpServerBindAddress: "127.0.0.1",
            Keys.pollingEnabled: false,
            Keys.pollingInterval: 30,
            Keys.workflowsEnabled: true,
            Keys.autoBackupEnabled: false,
            Keys.deviceStateLoggingEnabled: true
        ])

        // Migrate webhook URL from UserDefaults to Keychain (one-time)
        if let legacyURL = defaults.string(forKey: Keys.webhookURL), !legacyURL.isEmpty {
            if keychainService.read(key: KeychainService.Keys.webhookURL) == nil {
                keychainService.save(key: KeychainService.Keys.webhookURL, value: legacyURL)
            }
            defaults.removeObject(forKey: Keys.webhookURL)
        }

        self.webhookURL = keychainService.read(key: KeychainService.Keys.webhookURL)
        self.mcpServerPort = defaults.integer(forKey: Keys.mcpServerPort)
        self.webhookEnabled = defaults.bool(forKey: Keys.webhookEnabled)
        self.mcpServerEnabled = defaults.bool(forKey: Keys.mcpServerEnabled)
        self.hideRoomNameInTheApp = defaults.bool(forKey: Keys.hideRoomNameInTheApp)
        self.detailedLogsEnabled = defaults.bool(forKey: Keys.detailedLogsEnabled)
        self.aiEnabled = defaults.bool(forKey: Keys.aiEnabled)
        self.aiProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aiProvider) ?? "") ?? .claude
        self.aiModelId = defaults.string(forKey: Keys.aiModelId) ?? ""
        self.mcpServerBindAddress = defaults.string(forKey: Keys.mcpServerBindAddress) ?? "127.0.0.1"
        self.sunEventLatitude = defaults.double(forKey: Keys.sunEventLatitude)
        self.sunEventLongitude = defaults.double(forKey: Keys.sunEventLongitude)
        self.pollingEnabled = defaults.bool(forKey: Keys.pollingEnabled)
        self.pollingInterval = defaults.integer(forKey: Keys.pollingInterval)
        self.workflowsEnabled = defaults.bool(forKey: Keys.workflowsEnabled)
        self.autoBackupEnabled = defaults.bool(forKey: Keys.autoBackupEnabled)
        self.deviceStateLoggingEnabled = defaults.bool(forKey: Keys.deviceStateLoggingEnabled)
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
        keychainService.read(key: KeychainService.Keys.webhookURL)
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

    nonisolated func readBindAddress() -> String {
        UserDefaults.standard.string(forKey: Keys.mcpServerBindAddress) ?? "127.0.0.1"
    }

    nonisolated func readSunEventLatitude() -> Double {
        UserDefaults.standard.double(forKey: Keys.sunEventLatitude)
    }

    nonisolated func readSunEventLongitude() -> Double {
        UserDefaults.standard.double(forKey: Keys.sunEventLongitude)
    }

    nonisolated func readPollingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.pollingEnabled)
    }

    nonisolated func readPollingInterval() -> Int {
        let val = UserDefaults.standard.integer(forKey: Keys.pollingInterval)
        return val > 0 ? val : 30
    }

    nonisolated func readWorkflowsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.workflowsEnabled)
    }

    nonisolated func readDeviceStateLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.deviceStateLoggingEnabled)
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
        static let mcpServerBindAddress = "mcpServerBindAddress"
        static let sunEventLatitude = "sunEventLatitude"
        static let sunEventLongitude = "sunEventLongitude"
        static let pollingEnabled = "pollingEnabled"
        static let pollingInterval = "pollingInterval"
        static let workflowsEnabled = "workflowsEnabled"
        static let autoBackupEnabled = "autoBackupEnabled"
        static let deviceStateLoggingEnabled = "deviceStateLoggingEnabled"
    }
}
