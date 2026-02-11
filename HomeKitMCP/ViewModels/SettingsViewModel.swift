import Foundation
import Combine

class SettingsViewModel: ObservableObject {
    @Published var webhookStatus: WebhookStatus = .idle
    @Published var isSendingTest = false
    @Published var mcpServerRunning = false
    @Published var mcpConnectedClients = 0

    let storage: StorageService
    private let webhookService: WebhookService
    private let mcpServer: MCPServer
    private var cancellables = Set<AnyCancellable>()

    init(storage: StorageService, webhookService: WebhookService, mcpServer: MCPServer) {
        self.storage = storage
        self.webhookService = webhookService
        self.mcpServer = mcpServer

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
