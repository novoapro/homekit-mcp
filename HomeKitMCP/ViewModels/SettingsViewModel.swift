import Foundation
import Combine

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
    @Published var detailedLogsEnabled: Bool {
        didSet {
            storage.detailedLogsEnabled = detailedLogsEnabled
        }
    }
    @Published var pollingEnabled: Bool {
        didSet { storage.pollingEnabled = pollingEnabled }
    }
    @Published var pollingInterval: Int {
        didSet { storage.pollingInterval = pollingInterval }
    }
    @Published var workflowsEnabled: Bool {
        didSet { storage.workflowsEnabled = workflowsEnabled }
    }
    @Published var deviceStateLoggingEnabled: Bool {
        didSet { storage.deviceStateLoggingEnabled = deviceStateLoggingEnabled }
    }

    // MARK: - Location Properties

    @Published var sunEventLatitude: Double {
        didSet { storage.sunEventLatitude = sunEventLatitude }
    }
    @Published var sunEventLongitude: Double {
        didSet { storage.sunEventLongitude = sunEventLongitude }
    }

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
    @Published var aiApiKeyConfigured: Bool = false
    @Published var aiTestResult: AITestResult?
    @Published var isTestingAI = false
    @Published var mcpApiToken: String = ""

    let storage: StorageService
    private let webhookService: WebhookService
    private let mcpServer: MCPServer
    let configService: DeviceConfigurationService
    let keychainService: KeychainService
    let aiWorkflowService: AIWorkflowService
    let backupService: BackupService
    let cloudBackupService: CloudBackupService
    let appleSignInService: AppleSignInService
    private var cancellables = Set<AnyCancellable>()

    init(
        storage: StorageService,
        webhookService: WebhookService,
        mcpServer: MCPServer,
        configService: DeviceConfigurationService,
        keychainService: KeychainService,
        aiWorkflowService: AIWorkflowService,
        backupService: BackupService,
        cloudBackupService: CloudBackupService,
        appleSignInService: AppleSignInService
    ) {
        self.storage = storage
        self.webhookService = webhookService
        self.mcpServer = mcpServer
        self.configService = configService
        self.keychainService = keychainService
        self.aiWorkflowService = aiWorkflowService
        self.backupService = backupService
        self.cloudBackupService = cloudBackupService
        self.appleSignInService = appleSignInService
        self.webhookEnabled = storage.webhookEnabled
        self.hideRoomNameInTheApp = storage.hideRoomNameInTheApp
        self.detailedLogsEnabled = storage.detailedLogsEnabled
        self.pollingEnabled = storage.pollingEnabled
        self.pollingInterval = storage.pollingInterval
        self.workflowsEnabled = storage.workflowsEnabled
        self.deviceStateLoggingEnabled = storage.deviceStateLoggingEnabled
        self.sunEventLatitude = storage.sunEventLatitude
        self.sunEventLongitude = storage.sunEventLongitude
        self.aiEnabled = storage.aiEnabled
        self.aiProvider = storage.aiProvider
        self.aiModelId = storage.aiModelId
        self.aiApiKeyConfigured = keychainService.exists(key: KeychainService.Keys.aiApiKey)
        self.mcpApiToken = keychainService.getOrCreateMCPApiToken()

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

    func resetDeviceConfiguration() {
        Task {
            await configService.resetAll()
        }
    }

    var localIPAddress: String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // en0 = Wi-Fi, en1 = Ethernet on some Macs
            guard name == "en0" || name == "en1" else { continue }
            var addr = ptr.pointee.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            _ = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    getnameinfo(sockaddrPtr, socklen_t(sa.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                }
            }
            address = String(cString: hostname)
            break
        }
        return address
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

    // MARK: - MCP API Token Methods

    func regenerateMCPApiToken() {
        mcpApiToken = keychainService.regenerateMCPApiToken()
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
                let response = try await aiWorkflowService.testConnection()
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
}
