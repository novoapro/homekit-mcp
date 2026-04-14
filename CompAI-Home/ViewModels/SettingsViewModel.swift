import Foundation
import Combine
import CoreLocation

// MARK: - AI Test Result

enum AITestResult {
    case success(String)
    case failure(String)
}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var webhookStatus: WebhookStatus = .idle
    @Published var isSendingTest = false
    @Published var mcpServerRunning: Bool?
    @Published var mcpConnectedClients = 0
    @Published var mcpServerError: String?
    @Published var webhookEnabled: Bool {
        didSet {
            storage.webhookEnabled = webhookEnabled
        }
    }
    @Published var hideRoomNameInTheApp: Bool {
        didSet {
            storage.hideRoomNameInTheApp = hideRoomNameInTheApp
        }
    }
    @Published var useServiceTypeAsName: Bool {
        didSet {
            storage.useServiceTypeAsName = useServiceTypeAsName
        }
    }
    @Published var loggingEnabled: Bool {
        didSet { storage.loggingEnabled = loggingEnabled }
    }
    @Published var mcpLoggingEnabled: Bool {
        didSet { storage.mcpLoggingEnabled = mcpLoggingEnabled }
    }
    @Published var restLoggingEnabled: Bool {
        didSet { storage.restLoggingEnabled = restLoggingEnabled }
    }
    @Published var webhookLoggingEnabled: Bool {
        didSet { storage.webhookLoggingEnabled = webhookLoggingEnabled }
    }
    @Published var automationLoggingEnabled: Bool {
        didSet { storage.automationLoggingEnabled = automationLoggingEnabled }
    }
    @Published var mcpDetailedLogsEnabled: Bool {
        didSet { storage.mcpDetailedLogsEnabled = mcpDetailedLogsEnabled }
    }
    @Published var restDetailedLogsEnabled: Bool {
        didSet { storage.restDetailedLogsEnabled = restDetailedLogsEnabled }
    }
    @Published var webhookDetailedLogsEnabled: Bool {
        didSet { storage.webhookDetailedLogsEnabled = webhookDetailedLogsEnabled }
    }
    @Published var pollingEnabled: Bool {
        didSet { storage.pollingEnabled = pollingEnabled }
    }
    @Published var pollingInterval: Int {
        didSet { storage.pollingInterval = pollingInterval }
    }
    @Published var automationsEnabled: Bool {
        didSet { storage.automationsEnabled = automationsEnabled }
    }
    @Published var automationSyncEnabled: Bool {
        didSet { storage.automationSyncEnabled = automationSyncEnabled }
    }
    @Published var deviceStateLoggingEnabled: Bool {
        didSet { storage.deviceStateLoggingEnabled = deviceStateLoggingEnabled }
    }
    @Published var logOnlyWebhookDevices: Bool {
        didSet { storage.logOnlyWebhookDevices = logOnlyWebhookDevices }
    }
    @Published var logAccessEnabled: Bool {
        didSet { storage.logAccessEnabled = logAccessEnabled }
    }
    @Published var logCacheSize: Int {
        didSet { storage.logCacheSize = logCacheSize }
    }
    @Published var logSkippedAutomations: Bool {
        didSet { storage.logSkippedAutomations = logSkippedAutomations }
    }
    @Published var webhookPrivateIPAllowlist: [String] {
        didSet { storage.webhookPrivateIPAllowlist = webhookPrivateIPAllowlist }
    }
    @Published var temperatureUnit: String {
        willSet {
            if newValue != temperatureUnit {
                let convert: (Double) -> Double = newValue == "fahrenheit"
                    ? TemperatureConversion.celsiusToFahrenheit
                    : TemperatureConversion.fahrenheitToCelsius
                Task {
                    await TemperatureConversion.migrateAutomations(
                        automationStorage: automationStorageService,
                        registry: deviceRegistryService,
                        convert: convert
                    )
                }
            }
        }
        didSet { storage.temperatureUnit = temperatureUnit }
    }

    // MARK: - Location Properties

    @Published var sunEventLatitude: Double {
        didSet { storage.sunEventLatitude = sunEventLatitude }
    }
    @Published var sunEventLongitude: Double {
        didSet { storage.sunEventLongitude = sunEventLongitude }
    }
    @Published var sunEventZipCode: String {
        didSet { storage.sunEventZipCode = sunEventZipCode }
    }
    @Published var sunEventCityName: String {
        didSet { storage.sunEventCityName = sunEventCityName }
    }
    @Published var isGeocoding = false
    @Published var geocodingError: String?

    var hasValidCoordinates: Bool {
        sunEventLatitude != 0.0 || sunEventLongitude != 0.0
    }

    var todaySunrise: Date? {
        guard hasValidCoordinates else { return nil }
        return SolarCalculator.sunrise(for: Date(), latitude: sunEventLatitude, longitude: sunEventLongitude)
    }

    var todaySunset: Date? {
        guard hasValidCoordinates else { return nil }
        return SolarCalculator.sunset(for: Date(), latitude: sunEventLatitude, longitude: sunEventLongitude)
    }

    // MARK: - AI Properties

    @Published var aiEnabled: Bool {
        didSet { storage.aiEnabled = aiEnabled }
    }
    @Published var aiProvider: AIProvider {
        didSet { storage.aiProvider = aiProvider }
    }
    @Published var aiModelId: String {
        didSet { storage.aiModelId = aiModelId }
    }
    @Published var aiSystemPrompt: String {
        didSet { storage.aiSystemPrompt = aiSystemPrompt }
    }
    @Published var aiApiKeyConfigured: Bool = false
    @Published var aiTestResult: AITestResult?
    @Published var isTestingAI = false
    @Published var apiTokens: [APIToken] = []
    @Published var oauthCredentials: [OAuthCredential] = []

    let storage: StorageService
    private let webhookService: WebhookService
    private let mcpServer: MCPServer
    let keychainService: KeychainService
    private let oauthService: OAuthService
    let aiAutomationService: AIAutomationService
    let backupService: BackupService
    let cloudBackupService: CloudBackupService
    let appleSignInService: AppleSignInService
    let deviceRegistryService: DeviceRegistryService
    let homeKitManager: HomeKitManager
    let automationStorageService: AutomationStorageService
    let stateVariableStorageService: StateVariableStorageService
    let subscriptionService: SubscriptionService
    private var cancellables = Set<AnyCancellable>()

    var isProUser: Bool { subscriptionService.currentTier == .pro }

    init(
        storage: StorageService,
        webhookService: WebhookService,
        mcpServer: MCPServer,
        keychainService: KeychainService,
        aiAutomationService: AIAutomationService,
        backupService: BackupService,
        cloudBackupService: CloudBackupService,
        appleSignInService: AppleSignInService,
        deviceRegistryService: DeviceRegistryService,
        homeKitManager: HomeKitManager,
        automationStorageService: AutomationStorageService,
        stateVariableStorageService: StateVariableStorageService,
        subscriptionService: SubscriptionService,
        oauthService: OAuthService
    ) {
        self.storage = storage
        self.webhookService = webhookService
        self.mcpServer = mcpServer
        self.keychainService = keychainService
        self.aiAutomationService = aiAutomationService
        self.backupService = backupService
        self.cloudBackupService = cloudBackupService
        self.appleSignInService = appleSignInService
        self.deviceRegistryService = deviceRegistryService
        self.homeKitManager = homeKitManager
        self.automationStorageService = automationStorageService
        self.stateVariableStorageService = stateVariableStorageService
        self.subscriptionService = subscriptionService
        self.oauthService = oauthService
        self.webhookEnabled = storage.webhookEnabled
        self.hideRoomNameInTheApp = storage.hideRoomNameInTheApp
        self.useServiceTypeAsName = storage.useServiceTypeAsName
        self.loggingEnabled = storage.loggingEnabled
        self.mcpLoggingEnabled = storage.mcpLoggingEnabled
        self.restLoggingEnabled = storage.restLoggingEnabled
        self.webhookLoggingEnabled = storage.webhookLoggingEnabled
        self.automationLoggingEnabled = storage.automationLoggingEnabled
        self.mcpDetailedLogsEnabled = storage.mcpDetailedLogsEnabled
        self.restDetailedLogsEnabled = storage.restDetailedLogsEnabled
        self.webhookDetailedLogsEnabled = storage.webhookDetailedLogsEnabled
        self.pollingEnabled = storage.pollingEnabled
        self.pollingInterval = storage.pollingInterval
        self.automationsEnabled = storage.automationsEnabled
        self.automationSyncEnabled = storage.automationSyncEnabled
        self.deviceStateLoggingEnabled = storage.deviceStateLoggingEnabled
        self.logOnlyWebhookDevices = storage.logOnlyWebhookDevices
        self.logAccessEnabled = storage.logAccessEnabled
        self.logCacheSize = storage.logCacheSize
        self.logSkippedAutomations = storage.logSkippedAutomations
        self.webhookPrivateIPAllowlist = storage.webhookPrivateIPAllowlist
        self.temperatureUnit = storage.temperatureUnit
        self.sunEventLatitude = storage.sunEventLatitude
        self.sunEventLongitude = storage.sunEventLongitude
        self.sunEventZipCode = storage.sunEventZipCode
        self.sunEventCityName = storage.sunEventCityName
        self.aiEnabled = storage.aiEnabled
        self.aiProvider = storage.aiProvider
        self.aiModelId = storage.aiModelId
        let storedPrompt = storage.aiSystemPrompt
        self.aiSystemPrompt = storedPrompt.isEmpty ? AIAutomationService.defaultSystemPrompt : storedPrompt
        self.aiApiKeyConfigured = keychainService.exists(key: KeychainService.Keys.aiApiKey)
        self.apiTokens = keychainService.getAPITokens()
        self.oauthCredentials = keychainService.getOAuthCredentials()

        webhookService.statusSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.webhookStatus = status
                if case .sending = status {
                    self?.isSendingTest = true
                } else {
                    self?.isSendingTest = false
                }
            }
            .store(in: &cancellables)

        mcpServer.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.mcpServerRunning = running
            }
            .store(in: &cancellables)

        mcpServer.$connectedClients
            .receive(on: DispatchQueue.main)
            .assign(to: &$mcpConnectedClients)

        mcpServer.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$mcpServerError)

        scheduleMidnightRefresh()
    }

    func sendTestWebhook() {
        Task {
            _ = await webhookService.sendTest()
        }
    }

    func toggleMCPServer(enabled: Bool) {
        storage.mcpServerEnabled = enabled
        if enabled {
            Task {
                do {
                    try await mcpServer.start()
                } catch {
                    AppLogger.server.error("Failed to start MCP server: \(error)")
                }
            }
        } else {
            mcpServer.stop()
        }
    }

    var localIPAddress: String {
        NetworkInterfaceEnumerator.availableInterfaces().first?.address ?? "127.0.0.1"
    }

    func isValidURL(_ string: String) -> Bool {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }

    // MARK: - AI Methods

    func saveAIApiKey(_ key: String) {
        if key.isEmpty {
            clearAIApiKey()
        } else {
            keychainService.save(key: KeychainService.Keys.aiApiKey, value: key)
            aiApiKeyConfigured = true
        }
    }

    func clearAIApiKey() {
        keychainService.delete(key: KeychainService.Keys.aiApiKey)
        aiApiKeyConfigured = false
        aiTestResult = nil
    }

    func resetAISystemPrompt() {
        aiSystemPrompt = AIAutomationService.defaultSystemPrompt
    }

    // MARK: - API Token Methods

    func addAPIToken(name: String) {
        let token = keychainService.addAPIToken(name: name)
        apiTokens.append(token)
    }

    func deleteAPIToken(id: UUID) {
        keychainService.deleteAPIToken(id: id)
        apiTokens.removeAll { $0.id == id }
    }

    // MARK: - OAuth Credential Methods

    func addOAuthCredential(name: String) -> OAuthCredential {
        let credential = keychainService.addOAuthCredential(name: name)
        oauthCredentials.append(credential)
        return credential
    }

    func revokeOAuthCredential(id: UUID) {
        var credentials = keychainService.getOAuthCredentials()
        if let index = credentials.firstIndex(where: { $0.id == id }) {
            credentials[index].isRevoked = true
            keychainService.updateOAuthCredential(credentials[index])
            oauthCredentials = credentials
            Task {
                await oauthService.revokeCredential(id: id)
            }
        }
    }

    func deleteOAuthCredential(id: UUID) {
        Task {
            await oauthService.revokeCredential(id: id)
        }
        keychainService.deleteOAuthCredential(id: id)
        oauthCredentials.removeAll { $0.id == id }
    }

    func testAIConnection() {
        guard aiApiKeyConfigured else {
            aiTestResult = .failure("No API key configured")
            return
        }

        isTestingAI = true
        aiTestResult = nil

        Task {
            do {
                let response = try await aiAutomationService.testConnection()
                await MainActor.run {
                    self.aiTestResult = .success(response)
                    self.isTestingAI = false
                }
            } catch {
                await MainActor.run {
                    self.aiTestResult = .failure(error.localizedDescription)
                    self.isTestingAI = false
                }
            }
        }
    }

    // MARK: - Geocoding

    /// Geocodes the stored zipcode if coordinates are not yet set.
    /// Called on app launch to restore location state after fresh install or failed geocoding.
    func refreshSunEventCoordinatesIfNeeded() {
        let zip = sunEventZipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zip.isEmpty, sunEventLatitude == 0.0, sunEventLongitude == 0.0 else { return }
        geocodeZipCode()
    }

    /// Schedules a task that fires at the next midnight to refresh the solar time display,
    /// then reschedules itself for the following midnight.
    private func scheduleMidnightRefresh() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) else { return }
        let interval = nextMidnight.timeIntervalSinceNow
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
            await MainActor.run {
                self?.objectWillChange.send()
                self?.scheduleMidnightRefresh()
            }
        }
    }

    func geocodeZipCode() {
        let zip = sunEventZipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zip.isEmpty else {
            geocodingError = "Please enter a zip or postal code."
            return
        }

        isGeocoding = true
        geocodingError = nil

        Task {
            do {
                let geocoder = CLGeocoder()
                let placemarks = try await geocoder.geocodeAddressString(zip)
                guard let placemark = placemarks.first,
                      let location = placemark.location else {
                    geocodingError = "Could not find location for \"\(zip)\"."
                    isGeocoding = false
                    return
                }

                sunEventLatitude = location.coordinate.latitude
                sunEventLongitude = location.coordinate.longitude
                sunEventCityName = placemark.locality
                    ?? placemark.administrativeArea
                    ?? "Unknown"
                geocodingError = nil
                isGeocoding = false
            } catch {
                geocodingError = "Geocoding failed: \(error.localizedDescription)"
                isGeocoding = false
            }
        }
    }
}
