import Foundation
import Combine

/// User-facing label for log category filters.
enum LogCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case stateChange = "Device Update"
    case webhookCall = "Webhook Call"
    case webhookError = "Webhook Error"
    case mcpCall = "MCP Call"
    case restCall = "REST Call"
    case serverError = "Server Error"
    case workflowExecution = "Workflow"
    case workflowError = "Workflow Error"

    var id: String { rawValue }

    /// Maps to the underlying `LogCategory` values.
    var logCategories: [LogCategory]? {
        switch self {
        case .all: return nil
        case .stateChange: return [.stateChange]
        case .webhookCall: return [.webhookCall]
        case .webhookError: return [.webhookError]
        case .mcpCall: return [.mcpCall]
        case .restCall: return [.restCall]
        case .serverError: return [.serverError]
        case .workflowExecution: return [.workflowExecution]
        case .workflowError: return [.workflowError]
        }
    }

    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .stateChange: return "arrow.triangle.2.circlepath"
        case .webhookCall: return "paperplane.circle.fill"
        case .webhookError: return "exclamationmark.triangle.fill"
        case .mcpCall: return "arrow.left.arrow.right.circle.fill"
        case .restCall: return "globe"
        case .serverError: return "xmark.octagon.fill"
        case .workflowExecution: return "bolt.circle.fill"
        case .workflowError: return "bolt.trianglebadge.exclamationmark"
        }
    }
}

class LogViewModel: ObservableObject {
    // Publish grouped logs directly to the view to avoid main thread computation
    @Published var groupedLogs: [(date: String, label: String, logs: [StateChangeLog])] = []
    @Published var searchText = ""
    @Published var filteredLogCount = 0

    // Filters
    @Published var selectedCategories: Set<LogCategoryFilter> = []
    @Published var selectedDevices: Set<String> = []
    @Published var selectedServices: Set<String> = []

    // We keep the raw logs here but don't publish them to avoid unnecessary view updates
    private var rawLogs: [StateChangeLog] = []

    var hasLogs: Bool { !rawLogs.isEmpty }
    var totalLogCount: Int { rawLogs.count }

    var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !selectedDevices.isEmpty || !selectedServices.isEmpty
    }

    /// Unique device names found in the current logs, filtered by selected category.
    var availableDevices: [String] {
        let filtered = rawLogs.filter { log in
            if !selectedCategories.isEmpty {
                let allowedCategories = selectedCategories.flatMap { $0.logCategories ?? [] }
                return allowedCategories.contains(log.category)
            }
            return true
        }
        return Array(Set(filtered.map(\.deviceName))).sorted()
    }

    /// Unique service names found in the current logs, filtered by selected category and device.
    var availableServices: [String] {
        let filtered = rawLogs.filter { log in
            // Filter by category
            if !selectedCategories.isEmpty {
                let allowedCategories = selectedCategories.flatMap { $0.logCategories ?? [] }
                guard allowedCategories.contains(log.category) else { return false }
            }
            // Filter by device
            if !selectedDevices.isEmpty {
                guard selectedDevices.contains(log.deviceName) else { return false }
            }
            return true
        }
        return Array(Set(filtered.compactMap(\.serviceName))).sorted()
    }

    private let loggingService: LoggingService
    private let storage: StorageService
    private var cancellables = Set<AnyCancellable>()
    private var filterTask: Task<Void, Never>?

    var detailedLogsEnabled: Bool {
        storage.readDetailedLogsEnabled()
    }

    init(loggingService: LoggingService, storage: StorageService) {
        self.loggingService = loggingService
        self.storage = storage

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

        // Listen to filter changes
        $selectedCategories
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateView() }
            .store(in: &cancellables)
        
        $selectedDevices
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateView() }
            .store(in: &cancellables)

        $selectedServices
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateView() }
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
        let categories = self.selectedCategories
        let devices = self.selectedDevices
        let services = self.selectedServices

        // Cancel any in-flight filter task to avoid out-of-order results
        filterTask?.cancel()
        filterTask = Task.detached(priority: .userInitiated) {
            let filtered = Self.filterLogs(logs, with: query, categories: categories, devices: devices, services: services)
            guard !Task.isCancelled else { return }
            let grouped = Self.groupLogs(filtered)
            guard !Task.isCancelled else { return }
            let count = filtered.count

            await MainActor.run {
                self.groupedLogs = grouped
                self.filteredLogCount = count
            }
        }
    }

    private static func filterLogs(
        _ logs: [StateChangeLog],
        with query: String,
        categories: Set<LogCategoryFilter>,
        devices: Set<String>,
        services: Set<String>
    ) -> [StateChangeLog] {
        var result = logs

        // Category filter
        if !categories.isEmpty {
            let allowedLogCategories = categories.flatMap { $0.logCategories ?? [] }
            if !allowedLogCategories.isEmpty {
                result = result.filter { allowedLogCategories.contains($0.category) }
            }
        }

        // Device filter
        if !devices.isEmpty {
            result = result.filter { devices.contains($0.deviceName) }
        }

        // Service filter
        if !services.isEmpty {
            result = result.filter { $0.serviceName != nil && services.contains($0.serviceName!) }
        }

        // Text search
        guard !query.isEmpty else { return result }
        let lowerQuery = query.localizedLowercase
        return result.filter { log in
            log.deviceName.localizedCaseInsensitiveContains(lowerQuery) ||
            CharacteristicTypes.displayName(for: log.characteristicType)
                .localizedCaseInsensitiveContains(lowerQuery) ||
            log.category.rawValue.localizedCaseInsensitiveContains(lowerQuery) ||
            (log.serviceName?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
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

    func clearFilters() {
        selectedCategories.removeAll()
        selectedDevices.removeAll()
        selectedServices.removeAll()
    }

    func clearLogs() {
        Task {
            await loggingService.clearLogs()
        }
    }
}
