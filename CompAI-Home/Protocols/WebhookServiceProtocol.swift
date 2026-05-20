import Foundation
import Combine

/// Protocol abstracting WebhookService for dependency injection and testability.
protocol WebhookServiceProtocol: AnyObject, Sendable {
    // MARK: - Publishers
    var statusSubject: CurrentValueSubject<WebhookStatus, Never> { get }
    var endpointStatusSubject: CurrentValueSubject<[UUID: WebhookStatus], Never> { get }

    // MARK: - Actions
    func sendStateChange(_ change: StateChange) async
    func sendTest() async -> Bool
    func sendTest(endpointId: UUID) async -> Bool
}
