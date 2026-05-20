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
    @Published var restDeviceControlEnabled: Bool {
        didSet { defaults.set(restDeviceControlEnabled, forKey: Keys.restDeviceControlEnabled) }
    }
    @Published var hideRoomNameInTheApp: Bool {
        didSet { defaults.set(hideRoomNameInTheApp, forKey: Keys.hideRoomNameInTheApp) }
    }
    @Published var useServiceTypeAsName: Bool {
        didSet { defaults.set(useServiceTypeAsName, forKey: Keys.useServiceTypeAsName) }
    }
    @Published var loggingEnabled: Bool {
        didSet { defaults.set(loggingEnabled, forKey: Keys.loggingEnabled) }
    }
    @Published var mcpLoggingEnabled: Bool {
        didSet { defaults.set(mcpLoggingEnabled, forKey: Keys.mcpLoggingEnabled) }
    }
    @Published var restLoggingEnabled: Bool {
        didSet { defaults.set(restLoggingEnabled, forKey: Keys.restLoggingEnabled) }
    }
    @Published var webhookLoggingEnabled: Bool {
        didSet { defaults.set(webhookLoggingEnabled, forKey: Keys.webhookLoggingEnabled) }
    }
    @Published var automationLoggingEnabled: Bool {
        didSet { defaults.set(automationLoggingEnabled, forKey: Keys.automationLoggingEnabled) }
    }
    @Published var mcpDetailedLogsEnabled: Bool {
        didSet { defaults.set(mcpDetailedLogsEnabled, forKey: Keys.mcpDetailedLogsEnabled) }
    }
    @Published var restDetailedLogsEnabled: Bool {
        didSet { defaults.set(restDetailedLogsEnabled, forKey: Keys.restDetailedLogsEnabled) }
    }
    @Published var webhookDetailedLogsEnabled: Bool {
        didSet { defaults.set(webhookDetailedLogsEnabled, forKey: Keys.webhookDetailedLogsEnabled) }
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
    @Published var automationsEnabled: Bool {
        didSet { defaults.set(automationsEnabled, forKey: Keys.automationsEnabled) }
    }
    @Published var autoBackupEnabled: Bool {
        didSet { defaults.set(autoBackupEnabled, forKey: Keys.autoBackupEnabled) }
    }
    @Published var autoBackupIntervalHours: Int {
        didSet { defaults.set(autoBackupIntervalHours, forKey: Keys.autoBackupIntervalHours) }
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
    @Published var automationSyncEnabled: Bool {
        didSet { defaults.set(automationSyncEnabled, forKey: Keys.automationSyncEnabled) }
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
    @Published var logSkippedAutomations: Bool {
        didSet { defaults.set(logSkippedAutomations, forKey: Keys.logSkippedAutomations) }
    }
    @Published var webhookPrivateIPAllowlist: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(webhookPrivateIPAllowlist) {
                defaults.set(data, forKey: Keys.webhookPrivateIPAllowlist)
            }
        }
    }
    @Published var webhookEndpoints: [WebhookEndpoint] {
        didSet {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(webhookEndpoints) {
                defaults.set(data, forKey: Keys.webhookEndpoints)
            }
        }
    }
    @Published var temperatureUnit: String {
        didSet { defaults.set(temperatureUnit, forKey: Keys.temperatureUnit) }
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
            Keys.restDeviceControlEnabled: false,
            Keys.hideRoomNameInTheApp: true,
            Keys.useServiceTypeAsName: false,
            Keys.loggingEnabled: true,
            Keys.mcpLoggingEnabled: true,
            Keys.restLoggingEnabled: true,
            Keys.webhookLoggingEnabled: true,
            Keys.automationLoggingEnabled: true,
            Keys.mcpDetailedLogsEnabled: false,
            Keys.restDetailedLogsEnabled: false,
            Keys.webhookDetailedLogsEnabled: false,
            Keys.aiEnabled: false,
            Keys.aiProvider: AIProvider.claude.rawValue,
            Keys.aiModelId: "",
            Keys.aiSystemPrompt: "",
            Keys.mcpServerBindAddress: "127.0.0.1",
            Keys.corsEnabled: true,
            Keys.pollingEnabled: false,
            Keys.pollingInterval: 30,
            Keys.automationsEnabled: true,
            Keys.autoBackupEnabled: false,
            Keys.autoBackupIntervalHours: 24,
            Keys.deviceStateLoggingEnabled: true,
            Keys.logOnlyWebhookDevices: false,
            Keys.registryMigrationCompleted: false,
            Keys.automationSyncEnabled: false,
            Keys.logAccessEnabled: true,
            Keys.logCacheSize: 500,
            Keys.websocketEnabled: true,
            Keys.logSkippedAutomations: true,
            Keys.temperatureUnit: "celsius"
        ])

        // Migrate webhook URL from UserDefaults to Keychain (one-time)
        if let legacyURL = defaults.string(forKey: Keys.webhookURL), !legacyURL.isEmpty {
            if keychainService.read(key: KeychainService.Keys.webhookURL) == nil {
                keychainService.save(key: KeychainService.Keys.webhookURL, value: legacyURL)
            }
            defaults.removeObject(forKey: Keys.webhookURL)
        }

        // Migrate single webhook URL → multi-endpoint list (one-time)
        if defaults.object(forKey: Keys.webhookEndpoints) == nil,
           let singleURL = keychainService.read(key: KeychainService.Keys.webhookURL), !singleURL.isEmpty {
            let migrated = WebhookEndpoint(name: "Default", url: singleURL, enabled: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode([migrated]) {
                defaults.set(data, forKey: Keys.webhookEndpoints)
            }
        }

        // Migrate hideSkippedAutomationLogs → logSkippedAutomations (inverted logic)
        if defaults.object(forKey: Keys.hideSkippedAutomationLogs) != nil {
            let oldValue = defaults.bool(forKey: Keys.hideSkippedAutomationLogs)
            defaults.set(!oldValue, forKey: Keys.logSkippedAutomations)
            defaults.removeObject(forKey: Keys.hideSkippedAutomationLogs)
        }

        // Migrate detailedLogsEnabled → per-category detailed toggles
        let legacyDetailedKey = "detailedLogsEnabled"
        if defaults.object(forKey: legacyDetailedKey) != nil {
            let oldValue = defaults.bool(forKey: legacyDetailedKey)
            if defaults.object(forKey: Keys.mcpDetailedLogsEnabled) == nil {
                defaults.set(oldValue, forKey: Keys.mcpDetailedLogsEnabled)
            }
            if defaults.object(forKey: Keys.restDetailedLogsEnabled) == nil {
                defaults.set(oldValue, forKey: Keys.restDetailedLogsEnabled)
            }
            if defaults.object(forKey: Keys.webhookDetailedLogsEnabled) == nil {
                defaults.set(oldValue, forKey: Keys.webhookDetailedLogsEnabled)
            }
            defaults.removeObject(forKey: legacyDetailedKey)
        }

        self.webhookURL = keychainService.read(key: KeychainService.Keys.webhookURL)
        self.mcpServerPort = defaults.integer(forKey: Keys.mcpServerPort)
        self.webhookEnabled = defaults.bool(forKey: Keys.webhookEnabled)
        self.mcpServerEnabled = defaults.bool(forKey: Keys.mcpServerEnabled)
        self.mcpProtocolEnabled = defaults.bool(forKey: Keys.mcpProtocolEnabled)
        self.restApiEnabled = defaults.bool(forKey: Keys.restApiEnabled)
        self.restDeviceControlEnabled = defaults.bool(forKey: Keys.restDeviceControlEnabled)
        self.hideRoomNameInTheApp = defaults.bool(forKey: Keys.hideRoomNameInTheApp)
        self.useServiceTypeAsName = defaults.bool(forKey: Keys.useServiceTypeAsName)
        self.loggingEnabled = defaults.bool(forKey: Keys.loggingEnabled)
        self.mcpLoggingEnabled = defaults.bool(forKey: Keys.mcpLoggingEnabled)
        self.restLoggingEnabled = defaults.bool(forKey: Keys.restLoggingEnabled)
        self.webhookLoggingEnabled = defaults.bool(forKey: Keys.webhookLoggingEnabled)
        self.automationLoggingEnabled = defaults.bool(forKey: Keys.automationLoggingEnabled)
        self.mcpDetailedLogsEnabled = defaults.bool(forKey: Keys.mcpDetailedLogsEnabled)
        self.restDetailedLogsEnabled = defaults.bool(forKey: Keys.restDetailedLogsEnabled)
        self.webhookDetailedLogsEnabled = defaults.bool(forKey: Keys.webhookDetailedLogsEnabled)
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
        self.automationsEnabled = defaults.bool(forKey: Keys.automationsEnabled)
        self.autoBackupEnabled = defaults.bool(forKey: Keys.autoBackupEnabled)
        let rawIntervalHours = defaults.integer(forKey: Keys.autoBackupIntervalHours)
        self.autoBackupIntervalHours = rawIntervalHours > 0 ? rawIntervalHours : 24
        self.deviceStateLoggingEnabled = defaults.bool(forKey: Keys.deviceStateLoggingEnabled)
        self.logOnlyWebhookDevices = defaults.bool(forKey: Keys.logOnlyWebhookDevices)
        self.registryMigrationCompleted = defaults.bool(forKey: Keys.registryMigrationCompleted)
        self.automationSyncEnabled = defaults.bool(forKey: Keys.automationSyncEnabled)
        self.logAccessEnabled = defaults.bool(forKey: Keys.logAccessEnabled)
        self.websocketEnabled = defaults.bool(forKey: Keys.websocketEnabled)
        self.logSkippedAutomations = defaults.bool(forKey: Keys.logSkippedAutomations)
        let rawCacheSize = defaults.integer(forKey: Keys.logCacheSize)
        self.logCacheSize = rawCacheSize > 0 ? rawCacheSize : 500
        if let data = defaults.data(forKey: Keys.webhookPrivateIPAllowlist),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            self.webhookPrivateIPAllowlist = list
        } else {
            self.webhookPrivateIPAllowlist = []
        }
        self.temperatureUnit = defaults.string(forKey: Keys.temperatureUnit) ?? "celsius"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = defaults.data(forKey: Keys.webhookEndpoints),
           let endpoints = try? decoder.decode([WebhookEndpoint].self, from: data) {
            self.webhookEndpoints = endpoints
        } else {
            self.webhookEndpoints = []
        }
    }

    func isWebhookConfigured() -> Bool {
        webhookEndpoints.contains { $0.enabled && !$0.url.isEmpty && URL(string: $0.url) != nil }
    }

    // MARK: - Nonisolated Readers

    /// Thread-safe readers that go directly to UserDefaults.
    /// Use these from nonisolated or actor-isolated contexts that need read-only access.

    nonisolated func readHideRoomName() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.hideRoomNameInTheApp)
    }

    nonisolated func readUseServiceTypeAsName() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.useServiceTypeAsName)
    }

    nonisolated func readWebhookURL() -> String? {
        keychainService.read(key: KeychainService.Keys.webhookURL)
    }

    nonisolated func readWebhookEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.webhookEnabled)
    }

    nonisolated func readLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.loggingEnabled)
    }

    nonisolated func readMcpLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.mcpLoggingEnabled)
    }

    nonisolated func readRestLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.restLoggingEnabled)
    }

    nonisolated func readWebhookLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.webhookLoggingEnabled)
    }

    nonisolated func readAutomationLoggingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.automationLoggingEnabled)
    }

    nonisolated func readMcpDetailedLogsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.mcpDetailedLogsEnabled)
    }

    nonisolated func readRestDetailedLogsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.restDetailedLogsEnabled)
    }

    nonisolated func readWebhookDetailedLogsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.webhookDetailedLogsEnabled)
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

    nonisolated func readAutomationsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.automationsEnabled)
    }

    nonisolated func readMCPProtocolEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.mcpProtocolEnabled)
    }

    nonisolated func readRestApiEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.restApiEnabled)
    }

    nonisolated func readRestDeviceControlEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.restDeviceControlEnabled)
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

    nonisolated func readAutomationSyncEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.automationSyncEnabled)
    }

    nonisolated func readWebhookEndpoints() -> [WebhookEndpoint] {
        guard let data = UserDefaults.standard.data(forKey: Keys.webhookEndpoints) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WebhookEndpoint].self, from: data)) ?? []
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

    nonisolated func readLogSkippedAutomations() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.logSkippedAutomations)
    }

    nonisolated func readLogCacheSize() -> Int {
        let val = UserDefaults.standard.integer(forKey: Keys.logCacheSize)
        return val > 0 ? val : 500
    }

    nonisolated func readTemperatureUnit() -> String {
        UserDefaults.standard.string(forKey: Keys.temperatureUnit) ?? "celsius"
    }

    private enum Keys {
        static let webhookURL = "webhookURL"
        static let mcpServerPort = "mcpServerPort"
        static let webhookEnabled = "webhookEnabled"
        static let mcpServerEnabled = "mcpServerEnabled"
        static let mcpProtocolEnabled = "mcpProtocolEnabled"
        static let restApiEnabled = "restApiEnabled"
        static let restDeviceControlEnabled = "restDeviceControlEnabled"
        static let hideRoomNameInTheApp = "hideRoomNameInTheApp"
        static let useServiceTypeAsName = "useServiceTypeAsName"
        static let loggingEnabled = "loggingEnabled"
        static let mcpLoggingEnabled = "mcpLoggingEnabled"
        static let restLoggingEnabled = "restLoggingEnabled"
        static let webhookLoggingEnabled = "webhookLoggingEnabled"
        static let automationLoggingEnabled = "automationLoggingEnabled"
        static let mcpDetailedLogsEnabled = "mcpDetailedLogsEnabled"
        static let restDetailedLogsEnabled = "restDetailedLogsEnabled"
        static let webhookDetailedLogsEnabled = "webhookDetailedLogsEnabled"
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
        static let automationsEnabled = "automationsEnabled"
        static let autoBackupEnabled = "autoBackupEnabled"
        static let autoBackupIntervalHours = "autoBackupIntervalHours"
        static let deviceStateLoggingEnabled = "deviceStateLoggingEnabled"
        static let logOnlyWebhookDevices = "logOnlyWebhookDevices"
        static let registryMigrationCompleted = "registryMigrationCompleted"
        static let automationSyncEnabled = "automationSyncEnabled"
        static let webhookPrivateIPAllowlist = "webhookPrivateIPAllowlist"
        static let webhookEndpoints = "webhookEndpoints"
        static let logAccessEnabled = "logAccessEnabled"
        static let logCacheSize = "logCacheSize"
        static let websocketEnabled = "websocketEnabled"
        static let hideSkippedAutomationLogs = "hideSkippedAutomationLogs" // legacy, for migration
        static let logSkippedAutomations = "logSkippedAutomations"
        static let temperatureUnit = "temperatureUnit"
    }
}
