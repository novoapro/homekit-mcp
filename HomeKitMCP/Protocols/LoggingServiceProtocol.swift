import Foundation
import Combine

/// Protocol abstracting LoggingService for dependency injection and testability.
protocol LoggingServiceProtocol: AnyObject, Sendable {
    // MARK: - Publishers
    var logsSubject: PassthroughSubject<[StateChangeLog], Never> { get }

    // MARK: - Write
    func log(_ change: StateChange) async
    func logEntry(_ entry: StateChangeLog) async

    // MARK: - Read
    func getLogs() async -> [StateChangeLog]
    func clearLogs() async
}
