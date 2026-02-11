import Foundation
import Combine

class LogViewModel: ObservableObject {
    @Published var logs: [StateChangeLog] = []

    private let loggingService: LoggingService
    private var cancellables = Set<AnyCancellable>()

    init(loggingService: LoggingService) {
        self.loggingService = loggingService

        loggingService.logsSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$logs)

        Task {
            let existing = await loggingService.getLogs()
            await MainActor.run {
                self.logs = existing
            }
        }
    }

    func clearLogs() {
        Task {
            await loggingService.clearLogs()
        }
    }
}
