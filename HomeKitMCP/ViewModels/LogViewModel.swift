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
    case sceneExecution = "Scene"
    case backupRestore = "Backup"
    case aiInteraction = "AI Interaction"

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
        case .workflowExecution: return [.workflowExecution, .workflowError]
        case .sceneExecution: return [.sceneExecution, .sceneError]
        case .backupRestore: return [.backupRestore]
        case .aiInteraction: return [.aiInteraction, .aiInteractionError]
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
        case .sceneExecution: return "play.circle.fill"
        case .backupRestore: return "arrow.triangle.2.circlepath.circle.fill"
        case .aiInteraction: return "brain.head.profile"
        }
    }
}

@MainActor
class LogViewModel: ObservableObject {
    // Publish grouped logs directly to the view to avoid main thread computation
    @Published var groupedLogs: [(date: String, label: String, logs: [StateChangeLog])] = []
    @Published var searchText = ""
    @Published var filteredLogCount = 0
    @Published var isRefreshing = false

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

    /// Unique device names — pre-computed in `updateView()`, never re-scanned on every access.
    @Published private(set) var availableDevices: [String] = []
    /// Unique service names — pre-computed in `updateView()`, never re-scanned on every access.
    @Published private(set) var availableServices: [String] = []

    /// Returns the latest version of a workflow execution log by ID, for live detail views.
    func workflowExecutionLog(id: UUID) -> WorkflowExecutionLog? {
        rawLogs.first(where: { $0.id == id })?.workflowExecution
    }

    private let loggingService: LoggingService
    private let storage: StorageService
    private var cancellables = Set<AnyCancellable>()

    init(loggingService: LoggingService, storage: StorageService) {
        self.loggingService = loggingService
        self.storage = storage

        // Listen to log updates (unified — all categories in one stream)
        loggingService.logsSubject
            .receive(on: DispatchQueue.main)
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
            let existingLogs = await loggingService.getLogs()
            await MainActor.run {
                self.rawLogs = existingLogs
                self.updateView()
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        let freshLogs = await loggingService.getLogs()
        rawLogs = freshLogs
        updateView()
        isRefreshing = false
    }

    private func updateView() {
        let filtered = Self.filterLogs(rawLogs, with: searchText, categories: selectedCategories, devices: selectedDevices, services: selectedServices)
        let grouped = Self.groupLogs(filtered)

        self.groupedLogs = grouped
        self.filteredLogCount = filtered.count

        // Update cached filter option lists
        self.availableDevices = computeAvailableDevices()
        self.availableServices = computeAvailableServices()
    }

    private func computeAvailableDevices() -> [String] {
        let filtered = rawLogs.filter { log in
            guard !selectedCategories.isEmpty else { return true }
            let allowedCategories = selectedCategories.flatMap { $0.logCategories ?? [] }
            return allowedCategories.contains(log.category)
        }
        return Array(Set(filtered.map(\.deviceName))).sorted()
    }

    private func computeAvailableServices() -> [String] {
        let filtered = rawLogs.filter { log in
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
        _ logs: [StateChangeLog],
        with query: String,
        categories: Set<LogCategoryFilter>,
        devices: Set<String>,
        services: Set<String>
    ) -> [StateChangeLog] {
        var result = logs

        // Category filter
        if !categories.isEmpty {
            let allowedCategories = Set(categories.flatMap { $0.logCategories ?? [] })
            result = result.filter { allowedCategories.contains($0.category) }
        }

        // Device filter
        if !devices.isEmpty {
            result = result.filter { devices.contains($0.deviceName) }
        }

        // Service filter
        if !services.isEmpty {
            result = result.filter { log in
                log.serviceName != nil && services.contains(log.serviceName!)
            }
        }

        // Text search
        guard !query.isEmpty else { return result }
        let lowerQuery = query.localizedLowercase
        return result.filter { log in
            if log.deviceName.localizedCaseInsensitiveContains(lowerQuery) { return true }
            if CharacteristicTypes.displayName(for: log.characteristicType)
                .localizedCaseInsensitiveContains(lowerQuery) { return true }
            if log.category.rawValue.localizedCaseInsensitiveContains(lowerQuery) { return true }
            if log.serviceName?.localizedCaseInsensitiveContains(lowerQuery) ?? false { return true }
            if log.errorDetails?.localizedCaseInsensitiveContains(lowerQuery) ?? false { return true }
            // Workflow-specific search
            if let wf = log.workflowExecution {
                if wf.workflowName.localizedCaseInsensitiveContains(lowerQuery) { return true }
                if wf.triggerEvent?.deviceName?.localizedCaseInsensitiveContains(lowerQuery) ?? false { return true }
                if wf.triggerEvent?.triggerDescription?.localizedCaseInsensitiveContains(lowerQuery) ?? false { return true }
                if wf.errorMessage?.localizedCaseInsensitiveContains(lowerQuery) ?? false { return true }
            }
            // AI interaction search
            if let ai = log.aiInteraction {
                if ai.operation.localizedCaseInsensitiveContains(lowerQuery) { return true }
                if ai.provider.localizedCaseInsensitiveContains(lowerQuery) { return true }
                if ai.model.localizedCaseInsensitiveContains(lowerQuery) { return true }
            }
            return false
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
        }
    }
}
