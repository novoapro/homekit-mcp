import Foundation
import Combine

class LogViewModel: ObservableObject {
    // Publish grouped logs directly to the view to avoid main thread computation
    @Published var groupedLogs: [(date: String, label: String, logs: [StateChangeLog])] = []
    @Published var searchText = ""
    @Published var filteredLogCount = 0
    
    // We keep the raw logs here but don't publish them to avoid unnecessary view updates
    private var rawLogs: [StateChangeLog] = []

    var hasLogs: Bool { !rawLogs.isEmpty }
    var totalLogCount: Int { rawLogs.count }
    
    private let loggingService: LoggingService
    private var cancellables = Set<AnyCancellable>()
    
    init(loggingService: LoggingService) {
        self.loggingService = loggingService
        
        // Listen to service updates
        loggingService.logsSubject
            .receive(on: DispatchQueue.main) // Receive on main to update local state safely
            .sink { [weak self] logs in
                self?.rawLogs = logs
                self?.updateView()
            }
            .store(in: &cancellables)
            
        // Listen to search text changes
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateView()
            }
            .store(in: &cancellables)
            
        // Initial fetch
        Task {
            let existing = await loggingService.getLogs()
            await MainActor.run {
                self.rawLogs = existing
                self.updateView()
            }
        }
    }
    
    private func updateView() {
        let logs = self.rawLogs
        let query = self.searchText
        
        Task.detached(priority: .userInitiated) {
            let filtered = Self.filterLogs(logs, with: query)
            let grouped = Self.groupLogs(filtered)
            let count = filtered.count
            
            await MainActor.run {
                self.groupedLogs = grouped
                self.filteredLogCount = count
            }
        }
    }
    
    private static func filterLogs(_ logs: [StateChangeLog], with query: String) -> [StateChangeLog] {
        guard !query.isEmpty else { return logs }
        let lowerQuery = query.localizedLowercase
        return logs.filter { log in
            log.deviceName.localizedCaseInsensitiveContains(lowerQuery) ||
            CharacteristicTypes.displayName(for: log.characteristicType)
                .localizedCaseInsensitiveContains(lowerQuery) ||
            log.category.rawValue.localizedCaseInsensitiveContains(lowerQuery) ||
            (log.errorDetails?.localizedCaseInsensitiveContains(lowerQuery) ?? false)
        }
    }
    
    private static func groupLogs(_ logs: [StateChangeLog]) -> [(date: String, label: String, logs: [StateChangeLog])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let groupedDictionary = Dictionary(grouping: logs) { log in
            calendar.startOfDay(for: log.timestamp)
        }
        
        return groupedDictionary
            .sorted { $0.key > $1.key }
            .map { (date, logs) in
                let label: String
                if calendar.isDateInToday(date) {
                    label = "Today"
                } else if calendar.isDateInYesterday(date) {
                    label = "Yesterday"
                } else {
                    label = formatter.string(from: date)
                }
                return (date: date.ISO8601Format(), label: label, logs: logs)
            }
    }

    func clearLogs() {
        Task {
            await loggingService.clearLogs()
        }
    }
}
