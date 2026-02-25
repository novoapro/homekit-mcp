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
    nonisolated let keychainService: KeychainService

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
    @Published var mcpProtocolEnabled: Bool {
        didSet { defaults.set(mcpProtocolEnabled, forKey: Keys.mcpProtocolEnabled) }
    }
    @Published var restApiEnabled: Bool {
        didSet { defaults.set(restApiEnabled, forKey: Keys.restApiEnabled) }
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
    @Published var aiSystemPrompt: String {
        didSet { defaults.set(aiSystemPrompt, forKey: Keys.aiSystemPrompt) }
    }
    @Published var mcpServerBindAddress: String {
        didSet { defaults.set(mcpServerBindAddress, forKey: Keys.mcpServerBindAddress) }
    }
    @Published var corsEnabled: Bool {
        didSet { defaults.set(corsEnabled, forKey: Keys.corsEnabled) }
    }
    @Published var corsAllowedOrigins: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(corsAllowedOrigins) {
                defaults.set(data, forKey: Keys.corsAllowedOrigins)
            }
        }
    }
    @Published var sunEventLatitude: Double {
        didSet { defaults.set(sunEventLatitude, forKey: Keys.sunEventLatitude) }
    }
    @Published var sunEventLongitude: Double {
        didSet { defaults.set(sunEventLongitude, forKey: Keys.sunEventLongitude) }
    }
    @Published var sunEventZipCode: String {
        didSet { defaults.set(sunEventZipCode, forKey: Keys.sunEventZipCode) }
    }
    @Published var sunEventCityName: String {
        didSet { defaults.set(sunEventCityName, forKey: Keys.sunEventCityName) }
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
    @Published var logOnlyWebhookDevices: Bool {
        didSet { defaults.set(logOnlyWebhookDevices, forKey: Keys.logOnlyWebhookDevices) }
    }
    @Published var registryMigrationCompleted: Bool {
        didSet { defaults.set(registryMigrationCompleted, forKey: Keys.registryMigrationCompleted) }
    }
    @Published var workflowSyncEnabled: Bool {
        didSet { defaults.set(workflowSyncEnabled, forKey: Keys.workflowSyncEnabled) }
    }
    @Published var logAccessEnabled: Bool {
        didSet { defaults.set(logAccessEnabled, forKey: Keys.logAccessEnabled) }
    }
    @Published var logCacheSize: Int {
        didSet { defaults.set(logCacheSize, forKey: Keys.logCacheSize) }
    }
    @Published var websocketEnabled: Bool {
        didSet { defaults.set(websocketEnabled, forKey: Keys.websocketEnabled) }
    }
    @Published var webhookPrivateIPAllowlist: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(webhookPrivateIPAllowlist) {
                defaults.set(data, forKey: Keys.webhookPrivateIPAllowlist)
            }
        }
    }

    init(keychainService: KeychainService = KeychainService()) {
        self.keychainService = keychainService

        // Register defaults for keys that need non-nil/non-zero initial values
        defaults.register(defaults: [
            Keys.mcpServerPort: 3000,
            Keys.webhookEnabled: true,
            Keys.mcpServerEnabled: true,
            Keys.mcpProtocolEnabled: true,
            Keys.restApiEnabled: true,
            Keys.hideRoomNameInTheApp: true,
            Keys.detailedLogsEnabled: false,
            Keys.aiEnabled: false,
            Keys.aiProvider: AIProvider.claude.rawValue,
            Keys.aiModelId: "",
            Keys.aiSystemPrompt: "",
            Keys.mcpServerBindAddress: "127.0.0.1",
            Keys.corsEnabled: true,
            Keys.pollingEnabled: false,
            Keys.pollingInterval: 30,
            Keys.workflowsEnabled: true,
            Keys.autoBackupEnabled: false,
            Keys.deviceStateLoggingEnabled: true,
            Keys.logOnlyWebhookDevices: false,
            Keys.registryMigrationCompleted: false,
            Keys.workflowSyncEnabled: false,
            Keys.logAccessEnabled: true,
            Keys.logCacheSize: 500,
            Keys.websocketEnabled: true
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
        self.mcpProtocolEnabled = defaults.bool(forKey: Keys.mcpProtocolEnabled)
        self.restApiEnabled = defaults.bool(forKey: Keys.restApiEnabled)
        self.hideRoomNameInTheApp = defaults.bool(forKey: Keys.hideRoomNameInTheApp)
        self.detailedLogsEnabled = defaults.bool(forKey: Keys.detailedLogsEnabled)
        self.aiEnabled = defaults.bool(forKey: Keys.aiEnabled)
        self.aiProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aiProvider) ?? "") ?? .claude
        self.aiModelId = defaults.string(forKey: Keys.aiModelId) ?? ""
        self.aiSystemPrompt = defaults.string(forKey: Keys.aiSystemPrompt) ?? ""
        self.mcpServerBindAddress = defaults.string(forKey: Keys.mcpServerBindAddress) ?? "127.0.0.1"
        self.corsEnabled = defaults.bool(forKey: Keys.corsEnabled)
        if let data = defaults.data(forKey: Keys.corsAllowedOrigins),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            self.corsAllowedOrigins = list
        } else {
            self.corsAllowedOrigins = []
        }
        self.sunEventLatitude = defaults.double(forKey: Keys.sunEventLatitude)
        self.sunEventLongitude = defaults.double(forKey: Keys.sunEventLongitude)
        self.sunEventZipCode = defaults.string(forKey: Keys.sunEventZipCode) ?? ""
        self.sunEventCityName = defaults.string(forKey: Keys.sunEventCityName) ?? ""
        self.pollingEnabled = defaults.bool(forKey: Keys.pollingEnabled)
        self.pollingInterval = defaults.integer(forKey: Keys.pollingInterval)
        self.workflowsEnabled = defaults.bool(forKey: Keys.workflowsEnabled)
        self.autoBackupEnabled = defaults.bool(forKey: Keys.autoBackupEnabled)
        self.deviceStateLoggingEnabled = defaults.bool(forKey: Keys.deviceStateLoggingEnabled)
        self.logOnlyWebhookDevices = defaults.bool(forKey: Keys.logOnlyWebhookDevices)
        self.registryMigrationCompleted = defaults.bool(forKey: Keys.registryMigrationCompleted)
        self.workflowSyncEnabled = defaults.bool(forKey: Keys.workflowSyncEnabled)
        self.logAccessEnabled = defaults.bool(forKey: Keys.logAccessEnabled)
        self.websocketEnabled = defaults.bool(forKey: Keys.websocketEnabled)
        let rawCacheSize = defaults.integer(forKey: Keys.logCacheSize)
        self.logCacheSize = rawCacheSize > 0 ? rawCacheSize : 500
        if let data = defaults.data(forKey: Keys.webhookPrivateIPAllowlist),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            self.webhookPrivateIPAllowlist = list
        } else {
            self.webhookPrivateIPAllowlist = []
        }
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

    nonisolated func readAISystemPrompt() -> String {
        UserDefaults.standard.string(forKey: Keys.aiSystemPrompt) ?? ""
    }

    nonisolated func readBindAddress() -> String {
        UserDefaults.standard.string(forKey: Keys.mcpServerBindAddress) ?? "127.0.0.1"
    }

    nonisolated func readCorsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.corsEnabled)
    }

    nonisolated func readCorsAllowedOrigins() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: Keys.corsAllowedOrigins),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    nonisolated func readSunEventLatitude() -> Double {
        UserDefaults.standard.double(forKey: Keys.sunEventLatitude)
    }

    nonisolated func readSunEventLongitude() -> Double {
        UserDefaults.standard.double(forKey: Keys.sunEventLongitude)
    }

    nonisolated func readSunEventZipCode() -> String {
        UserDefaults.standard.string(forKey: Keys.sunEventZipCode) ?? ""
    }

    nonisolated func readSunEventCityName() -> String {
        UserDefaults.standard.string(forKey: Keys.sunEventCityName) ?? ""
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

    nonisolated func readMCPProtocolEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.mcpProtocolEnabled)
    }

    nonisolated func readRestApiEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.restApiEnabled)
    }

    nonisolated func readDeviceStateLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.deviceStateLoggingEnabled)
    }

    nonisolated func readLogOnlyWebhookDevices() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.logOnlyWebhookDevices)
    }

    nonisolated func readRegistryMigrationCompleted() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.registryMigrationCompleted)
    }

    nonisolated func readWorkflowSyncEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.workflowSyncEnabled)
    }

    nonisolated func readWebhookPrivateIPAllowlist() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: Keys.webhookPrivateIPAllowlist) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    nonisolated func readLogAccessEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.logAccessEnabled)
    }

    nonisolated func readWebsocketEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.websocketEnabled)
    }

    nonisolated func readLogCacheSize() -> Int {
        let val = UserDefaults.standard.integer(forKey: Keys.logCacheSize)
        return val > 0 ? val : 500
    }

    private enum Keys {
        static let webhookURL = "webhookURL"
        static let mcpServerPort = "mcpServerPort"
        static let webhookEnabled = "webhookEnabled"
        static let mcpServerEnabled = "mcpServerEnabled"
        static let mcpProtocolEnabled = "mcpProtocolEnabled"
        static let restApiEnabled = "restApiEnabled"
        static let hideRoomNameInTheApp = "hideRoomNameInTheApp"
        static let detailedLogsEnabled = "detailedLogsEnabled"
        static let aiEnabled = "aiEnabled"
        static let aiProvider = "aiProvider"
        static let aiModelId = "aiModelId"
        static let aiSystemPrompt = "aiSystemPrompt"
        static let mcpServerBindAddress = "mcpServerBindAddress"
        static let corsEnabled = "corsEnabled"
        static let corsAllowedOrigins = "corsAllowedOrigins"
        static let sunEventLatitude = "sunEventLatitude"
        static let sunEventLongitude = "sunEventLongitude"
        static let sunEventZipCode = "sunEventZipCode"
        static let sunEventCityName = "sunEventCityName"
        static let pollingEnabled = "pollingEnabled"
        static let pollingInterval = "pollingInterval"
        static let workflowsEnabled = "workflowsEnabled"
        static let autoBackupEnabled = "autoBackupEnabled"
        static let deviceStateLoggingEnabled = "deviceStateLoggingEnabled"
        static let logOnlyWebhookDevices = "logOnlyWebhookDevices"
        static let registryMigrationCompleted = "registryMigrationCompleted"
        static let workflowSyncEnabled = "workflowSyncEnabled"
        static let webhookPrivateIPAllowlist = "webhookPrivateIPAllowlist"
        static let logAccessEnabled = "logAccessEnabled"
        static let logCacheSize = "logCacheSize"
        static let websocketEnabled = "websocketEnabled"
    }
}
