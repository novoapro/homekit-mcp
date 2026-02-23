import Combine
import SwiftUI

/// Live-updating detail view that observes the LogViewModel for real-time block execution updates.
struct WorkflowExecutionLogDetailView: View {
    private let logId: UUID
    private let staticLog: WorkflowExecutionLog?
    private let onCancel: ((UUID) -> Void)?
    @ObservedObject private var viewModel: _LogViewModelProxy
    @State private var showingKillConfirmation = false

    /// Live-updating initializer — used from LogViewerView.
    init(logId: UUID, viewModel: LogViewModel, onCancel: ((UUID) -> Void)? = nil) {
        self.logId = logId
        self.staticLog = nil
        self.onCancel = onCancel
        self._viewModel = ObservedObject(wrappedValue: _LogViewModelProxy(viewModel: viewModel))
    }

    /// Static snapshot initializer — used from WorkflowDetailView.
    init(log: WorkflowExecutionLog, onCancel: ((UUID) -> Void)? = nil) {
        self.logId = log.id
        self.staticLog = log
        self.onCancel = onCancel
        self._viewModel = ObservedObject(wrappedValue: _LogViewModelProxy(viewModel: nil))
    }

    private var log: WorkflowExecutionLog? {
        viewModel.viewModel?.workflowExecutionLog(id: logId) ?? staticLog
    }

    var body: some View {
        if let log {
            logContent(log)
        } else {
            Text("Log not found")
                .foregroundColor(Theme.Text.secondary)
        }
    }

    @ViewBuilder
    private func logContent(_ log: WorkflowExecutionLog) -> some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: statusIcon(log.status))
                            .foregroundColor(statusColor(log.status))
                            .accessibilityLabel(log.status.displayName)
                        Text(log.workflowName)
                            .font(.headline)
                        Text(log.status.displayName)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor(log.status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(log.status).opacity(0.12))
                            .cornerRadius(4)
                        Spacer()
                        if let duration = executionDuration(log) {
                            Text(duration)
                                .font(.footnote)
                                .foregroundColor(Theme.Text.secondary)
                        } else if log.status == .running {
                            LiveElapsedText(since: log.triggeredAt)
                                .font(.footnote)
                                .foregroundColor(.blue)
                        }
                    }

                    Text(log.triggeredAt, format: .dateTime)
                        .font(.subheadline)
                        .foregroundColor(Theme.Text.secondary)

                    if let error = log.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(Theme.Status.error)
                    }

                    if log.status == .running, onCancel != nil {
                        Button(role: .destructive) {
                            showingKillConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                Text("Kill Workflow")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .padding(.top, 4)
                        .confirmationDialog(
                            "Kill this workflow execution?",
                            isPresented: $showingKillConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Kill Workflow", role: .destructive) {
                                onCancel?(logId)
                            }
                        } message: {
                            Text("This will immediately cancel the running workflow. Any in-progress actions may be left incomplete.")
                        }
                    }
                }
            }
            .listRowBackground(Theme.contentBackground)

            // Trigger
            if let trigger = log.triggerEvent {
                Section("Trigger") {
                    triggerDetailView(trigger)
                }
                .listRowBackground(Theme.contentBackground)
            }

            // Conditions
            if let conditions = log.conditionResults, !conditions.isEmpty {
                Section("Conditions") {
                    ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                        conditionResultView(condition, depth: 0)
                    }
                }
                .listRowBackground(Theme.contentBackground)
            }

            // Steps
            if !log.blockResults.isEmpty {
                Section("Steps") {
                    ForEach(Array(log.blockResults.enumerated()), id: \.offset) { _, block in
                        blockResultView(block, depth: 0)
                    }
                }
                .listRowBackground(Theme.contentBackground)
            } else if log.status == .running {
                Section("Steps") {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for blocks to execute...")
                            .font(.subheadline)
                            .foregroundColor(Theme.Text.secondary)
                    }
                }
                .listRowBackground(Theme.contentBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Execution Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Recursive Condition Result View

    private func conditionResultView(_ result: ConditionResult, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if depth > 0 {
                        ForEach(0..<depth, id: \.self) { _ in
                            Rectangle()
                                .fill(Theme.Tint.secondary.opacity(0.3))
                                .frame(width: 2, height: 20)
                        }
                    }

                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(result.passed ? Theme.Status.active : Theme.Status.error)

                    if let op = result.logicOperator {
                        Text(op)
                            .font(.footnote)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.Tint.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }

                    Text(result.subResults != nil ? (result.passed ? "Passed" : "Failed") : result.conditionDescription)
                        .font(.subheadline)
                }

                if let subs = result.subResults {
                    ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                        conditionResultView(sub, depth: depth + 1)
                    }
                }
            }
        )
    }

    // MARK: - Recursive Block View

    private func blockResultView(_ result: BlockResult, depth: Int) -> AnyView {
        let title = result.blockName ?? result.blockType.replacingOccurrences(of: "_", with: " ").capitalized
        let dur: String? = {
            guard let completed = result.completedAt else { return nil }
            let interval = completed.timeIntervalSince(result.startedAt)
            return interval < 1 ? String(format: "%.0fms", interval * 1000) : String(format: "%.1fs", interval)
        }()
        let isContainer = result.nestedResults != nil && !(result.nestedResults?.isEmpty ?? true)
        let indentWidth = CGFloat(depth) * 20

        return AnyView(Group {
            HStack(alignment: .top, spacing: 0) {
                // Indentation with connector lines for each depth level
                if depth > 0 {
                    HStack(spacing: 0) {
                        ForEach(0 ..< depth, id: \.self) { level in
                            Rectangle()
                                .fill(depthColor(level).opacity(0.3))
                                .frame(width: 2)
                                .padding(.leading, level == 0 ? 6 : 14)
                        }
                    }
                    .frame(width: indentWidth)
                }

                // Step content
                HStack(alignment: .top, spacing: 8) {
                    if result.status == .running {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                            .accessibilityLabel(ExecutionStatus.running.displayName)
                    } else {
                        Image(systemName: stepIcon(result.status))
                            .font(.subheadline)
                            .foregroundColor(statusColor(result.status))
                            .frame(width: 16)
                            .accessibilityLabel(result.status.displayName)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Title row
                        HStack {
                            if isContainer {
                                Image(systemName: containerIcon(result.blockType))
                                    .font(.caption2)
                                    .foregroundColor(Theme.Text.tertiary)
                            }
                            Text(title)
                                .font(.subheadline)
                                .fontWeight(isContainer ? .semibold : .medium)
                            Spacer()
                            if let dur {
                                Text(dur)
                                    .font(.footnote)
                                    .foregroundColor(Theme.Text.tertiary)
                            } else if result.status == .running {
                                LiveElapsedText(since: result.startedAt)
                                    .font(.footnote)
                                    .foregroundColor(.blue)
                            }
                        }

                        // Detail
                        if let detail = result.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundColor(result.status == .running ? .blue : Theme.Text.secondary)
                        }

                        // Error
                        if let error = result.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(Theme.Status.error)
                        }
                    }
                }
                .padding(.leading, depth > 0 ? 8 : 0)
            }

            // Render nested children recursively
            if let nested = result.nestedResults {
                ForEach(Array(nested.enumerated()), id: \.offset) { _, child in
                    blockResultView(child, depth: depth + 1)
                }
            }
        })
    }

    private func containerIcon(_ blockType: String) -> String {
        switch blockType {
        case "conditional": return "arrow.triangle.branch"
        case "repeat", "repeatWhile": return "repeat"
        case "group": return "rectangle.3.group"
        case "delay": return "clock"
        case "waitForState": return "hourglass"
        default: return "square.stack"
        }
    }

    private func depthColor(_ level: Int) -> Color {
        let colors: [Color] = [Theme.Tint.main, .purple, .orange, .teal, .pink]
        return colors[level % colors.count]
    }

    // MARK: - Helpers

    private func triggerDetailView(_ trigger: TriggerEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Trigger description
            if let desc = trigger.triggerDescription {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(Theme.Text.primary)
            }

            // Device info
            if let deviceName = trigger.deviceName {
                HStack(spacing: 6) {
                    Image(systemName: "house")
                        .font(.footnote)
                        .foregroundColor(Theme.Tint.main)
                    Text(deviceName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }

            // Characteristic + value change
            if let charType = trigger.characteristicType {
                let charName = CharacteristicTypes.displayName(for: charType)

                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote)
                        .foregroundColor(Theme.Text.tertiary)
                    Text(charName)
                        .font(.subheadline)
                        .foregroundColor(Theme.Text.secondary)
                }

                // Value transition
                if trigger.oldValue != nil || trigger.newValue != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.footnote)
                            .foregroundColor(Theme.Text.tertiary)

                        if let oldVal = trigger.oldValue {
                            Text(CharacteristicTypes.formatValue(oldVal.value, characteristicType: charType))
                                .font(.subheadline)
                                .foregroundColor(Theme.Text.secondary)

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(Theme.Text.tertiary)
                        }

                        if let newVal = trigger.newValue {
                            Text(CharacteristicTypes.formatValue(newVal.value, characteristicType: charType))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.Text.primary)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(_ status: ExecutionStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .running: return "circle.dotted"
        case .skipped: return "forward.circle.fill"
        case .conditionNotMet: return "exclamationmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }

    private func stepIcon(_ status: ExecutionStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .running: return "circle.dotted"
        case .skipped: return "forward.circle.fill"
        case .conditionNotMet: return "exclamationmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }

    private func executionDuration(_ log: WorkflowExecutionLog) -> String? {
        guard let completed = log.completedAt else { return nil }
        let interval = completed.timeIntervalSince(log.triggeredAt)
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        } else if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            return String(format: "%.0fm %.0fs", interval / 60, interval.truncatingRemainder(dividingBy: 60))
        }
    }

    private func statusColor(_ status: ExecutionStatus) -> Color {
        switch status {
        case .success: return Theme.Status.active
        case .failure: return Theme.Status.error
        case .running: return .blue
        case .skipped: return Theme.Status.inactive
        case .conditionNotMet: return Theme.Status.warning
        case .cancelled: return Theme.Status.inactive
        }
    }
}

// MARK: - Internal Proxy to allow optional LogViewModel observation

/// Thin ObservableObject wrapper that forwards objectWillChange from LogViewModel when available.
class _LogViewModelProxy: ObservableObject {
    let viewModel: LogViewModel?
    private var cancellable: AnyCancellable?

    init(viewModel: LogViewModel?) {
        self.viewModel = viewModel
        if let vm = viewModel {
            // Forward the LogViewModel's objectWillChange to our own
            cancellable = vm.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}

// MARK: - Live Elapsed Time Helper

/// A small view that shows a live-updating elapsed time string.
private struct LiveElapsedText: View {
    let since: Date
    @State private var elapsed: String = ""
    @State private var timer: Timer?

    var body: some View {
        Text(elapsed)
            .onAppear {
                updateElapsed()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    updateElapsed()
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    private func updateElapsed() {
        let interval = Date().timeIntervalSince(since)
        if interval < 1 {
            elapsed = String(format: "%.0fms", interval * 1000)
        } else if interval < 60 {
            elapsed = String(format: "%.1fs", interval)
        } else {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            elapsed = String(format: "%dm %ds", minutes, seconds)
        }
    }
}
