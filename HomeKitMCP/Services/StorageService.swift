import Foundation
import SwiftUI

class StorageService: ObservableObject {
    @AppStorage("webhookURL") var webhookURL: String?
    @AppStorage("mcpServerPort") var mcpServerPort: Int = 3000
    @AppStorage("mcpServerEnabled") var mcpServerEnabled: Bool = true

    func isWebhookConfigured() -> Bool {
        guard let url = webhookURL, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }
}
