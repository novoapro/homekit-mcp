import Foundation
import Combine

class SettingsViewModel: ObservableObject {
    @Published var webhookStatus: WebhookStatus = .idle
    @Published var isSendingTest = false
    @Published var mcpServerRunning = false
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

    let storage: StorageService
    private let webhookService: WebhookService
    private let mcpServer: MCPServer
    let configService: DeviceConfigurationService
    private var cancellables = Set<AnyCancellable>()

    init(storage: StorageService, webhookService: WebhookService, mcpServer: MCPServer, configService: DeviceConfigurationService) {
        self.storage = storage
        self.webhookService = webhookService
        self.mcpServer = mcpServer
        self.configService = configService
        self.webhookEnabled = storage.webhookEnabled
        self.hideRoomNameInTheApp = storage.hideRoomNameInTheApp

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
            .assign(to: &$mcpServerRunning)

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
            do {
                try mcpServer.start()
            } catch {
                print("Failed to start MCP server: \(error)")
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
}
