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
        }
    }
}

/// Unified log type for both device state change logs and workflow execution logs
enum UnifiedLog: Identifiable {
    case stateChange(StateChangeLog)
    case workflowExecution(WorkflowExecutionLog)

    var id: AnyHashable {
        switch self {
        case .stateChange(let log): return log.id
        case .workflowExecution(let log): return log.id
        }
    }

    var timestamp: Date {
        switch self {
        case .stateChange(let log): return log.timestamp
        case .workflowExecution(let log): return log.triggeredAt
        }
    }

    var category: LogCategoryFilter {
        switch self {
        case .stateChange(_): return .stateChange
        case .workflowExecution(_): return .workflowExecution
        }
    }
}

@MainActor
class LogViewModel: ObservableObject {
    // Publish grouped logs directly to the view to avoid main thread computation
    @Published var groupedLogs: [(date: String, label: String, logs: [UnifiedLog])] = []
    @Published var searchText = ""
    @Published var filteredLogCount = 0

    // Filters
    @Published var selectedCategories: Set<LogCategoryFilter> = []
    @Published var selectedDevices: Set<String> = []
    @Published var selectedServices: Set<String> = []

    // We keep the raw logs here but don't publish them to avoid unnecessary view updates
    private var rawStateChangeLogs: [StateChangeLog] = []
    private var rawWorkflowExecutionLogs: [WorkflowExecutionLog] = []

    var hasLogs: Bool { !rawStateChangeLogs.isEmpty || !rawWorkflowExecutionLogs.isEmpty }
    var totalLogCount: Int { rawStateChangeLogs.count + rawWorkflowExecutionLogs.count }

    var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !selectedDevices.isEmpty || !selectedServices.isEmpty
    }

    /// Unique device names — pre-computed in `updateView()`, never re-scanned on every access.
    @Published private(set) var availableDevices: [String] = []
    /// Unique service names — pre-computed in `updateView()`, never re-scanned on every access.
    @Published private(set) var availableServices: [String] = []

    /// Returns the latest version of a workflow execution log by ID, for live detail views.
    func workflowExecutionLog(id: UUID) -> WorkflowExecutionLog? {
        rawWorkflowExecutionLogs.first(where: { $0.id == id })
    }

    private let loggingService: LoggingService
    private let executionLogService: WorkflowExecutionLogService
    private let storage: StorageService
    private var cancellables = Set<AnyCancellable>()

    var detailedLogsEnabled: Bool {
        storage.readDetailedLogsEnabled()
    }

    init(loggingService: LoggingService, executionLogService: WorkflowExecutionLogService, storage: StorageService) {
        self.loggingService = loggingService
        self.executionLogService = executionLogService
        self.storage = storage

        // Listen to device state change log updates
        loggingService.logsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logs in
                self?.rawStateChangeLogs = logs
                self?.updateView()
            }
            .store(in: &cancellables)

        // Listen to workflow execution log updates
        // Throttle to ensure rapid updates (e.g., during block execution) don't cancel each other,
        // while still guaranteeing the latest state is always delivered.
        executionLogService.logsSubject
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] logs in
                self?.rawWorkflowExecutionLogs = logs
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
            let existingDeviceLogs = await loggingService.getLogs()
            let existingExecutionLogs = await executionLogService.getLogs()
            await MainActor.run {
                self.rawStateChangeLogs = existingDeviceLogs
                self.rawWorkflowExecutionLogs = existingExecutionLogs
                self.updateView()
            }
        }
    }

    private func updateView() {
        // Convert device logs to unified format
        let unifiedDeviceLogs = rawStateChangeLogs.map { UnifiedLog.stateChange($0) }
        // Convert workflow logs to unified format
        let unifiedWorkflowLogs = rawWorkflowExecutionLogs.map { UnifiedLog.workflowExecution($0) }
        // Combine all logs
        let allLogs = unifiedDeviceLogs + unifiedWorkflowLogs

        let filtered = Self.filterLogs(allLogs, with: searchText, categories: selectedCategories, devices: selectedDevices, services: selectedServices)
        let grouped = Self.groupLogs(filtered)

        self.groupedLogs = grouped
        self.filteredLogCount = filtered.count

        // Update cached filter option lists — previously computed properties that scanned
        // all 500 logs on every access. Now computed once per update, O(n) total.
        self.availableDevices = computeAvailableDevices()
        self.availableServices = computeAvailableServices()
    }

    private func computeAvailableDevices() -> [String] {
        let filtered = rawStateChangeLogs.filter { log in
            guard !selectedCategories.isEmpty else { return true }
            let allowedCategories = selectedCategories.flatMap { $0.logCategories ?? [] }
            return allowedCategories.contains(log.category)
        }
        return Array(Set(filtered.map(\.deviceName))).sorted()
    }

    private func computeAvailableServices() -> [String] {
        let filtered = rawStateChangeLogs.filter { log in
            if !selectedCategories.isEmpty {
                let allowedCategories = selectedCategories.flatMap { $0.logCategories ?? [] }
                guard allowedCategories.contains(log.category) else { return false }
            }
            if !selectedDevices.isEmpty {
                guard selectedDevices.contains(log.deviceName) else { return false }
            }
            return true
        }
        return Array(Set(filtered.compactMap(\.serviceName))).sorted()
    }

    private static func filterLogs(
        _ logs: [UnifiedLog],
        with query: String,
        categories: Set<LogCategoryFilter>,
        devices: Set<String>,
        services: Set<String>
    ) -> [UnifiedLog] {
        var result = logs

        // Exclude workflowExecution and workflowError from StateChangeLog (we show them separately as WorkflowExecutionLog)
        result = result.filter { log in
            switch log {
            case .stateChange(let stateLog):
                return stateLog.category != .workflowExecution && stateLog.category != .workflowError
            case .workflowExecution(_):
                return true
            }
        }

        // Category filter
        if !categories.isEmpty {
            result = result.filter { log in
                switch log {
                case .stateChange(let stateLog):
                    let allowedCategories = categories.flatMap { $0.logCategories ?? [] }
                    return allowedCategories.contains(stateLog.category)
                case .workflowExecution(_):
                    return categories.contains(.workflowExecution)
                }
            }
        }

        // Device filter
        if !devices.isEmpty {
            result = result.filter { log in
                switch log {
                case .stateChange(let stateLog):
                    return devices.contains(stateLog.deviceName)
                case .workflowExecution(_):
                    return false // Workflow logs don't have device filtering
                }
            }
        }

        // Service filter
        if !services.isEmpty {
            result = result.filter { log in
                switch log {
                case .stateChange(let stateLog):
                    return stateLog.serviceName != nil && services.contains(stateLog.serviceName!)
                case .workflowExecution(_):
                    return false // Workflow logs don't have service filtering
                }
            }
        }

        // Text search
        guard !query.isEmpty else { return result }
        let lowerQuery = query.localizedLowercase
        return result.filter { log in
            switch log {
            case .stateChange(let stateLog):
                return stateLog.deviceName.localizedCaseInsensitiveContains(lowerQuery) ||
                    CharacteristicTypes.displayName(for: stateLog.characteristicType)
                        .localizedCaseInsensitiveContains(lowerQuery) ||
                    stateLog.category.rawValue.localizedCaseInsensitiveContains(lowerQuery) ||
                    (stateLog.serviceName?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                    (stateLog.errorDetails?.localizedCaseInsensitiveContains(lowerQuery) ?? false)
            case .workflowExecution(let workflowLog):
                return workflowLog.workflowName.localizedCaseInsensitiveContains(lowerQuery) ||
                    (workflowLog.triggerEvent?.deviceName?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                    (workflowLog.triggerEvent?.triggerDescription?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                    (workflowLog.errorMessage?.localizedCaseInsensitiveContains(lowerQuery) ?? false)
            }
        }
    }

    private static func groupLogs(_ logs: [UnifiedLog]) -> [(date: String, label: String, logs: [UnifiedLog])] {
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
                // Sort logs within each date group by timestamp (newest first)
                let sortedLogs = logs.sorted { $0.timestamp > $1.timestamp }
                return (date: date.ISO8601Format(), label: label, logs: sortedLogs)
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
            await executionLogService.clearLogs()
        }
    }
}
