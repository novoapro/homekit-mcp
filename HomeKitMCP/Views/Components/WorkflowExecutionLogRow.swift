import SwiftUI

struct WorkflowExecutionLogRow: View {
    let log: WorkflowExecutionLog

    @State private var elapsedTime = ""
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Column 1: Status indicator
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.footnote)
                .foregroundColor(Theme.Text.primary)
                .frame(width: 16)

            // Column 2: Header row + subheader and content rows
            VStack(alignment: .leading, spacing: 4) {
                // Header row: workflow name + spacer to fill width
                HStack(alignment: .center, spacing: 8) {
                    Text(log.workflowName)
                        .font(.headline)
                        .foregroundColor(Theme.Text.primary)
                    Spacer()
                }

                // Subheader row: status + steps
                HStack(spacing: 8) {
                    if log.completedAt == nil {
                        Text("Running")
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    } else {
                        Text(log.status.displayName)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(statusTextColor)
                    }
                    Text("•")
                        .foregroundColor(Theme.Text.tertiary)
                    Text("\(log.blockResults.count) steps")
                        .font(.footnote)
                        .foregroundColor(Theme.Text.secondary)
                }

                // Content rows: trigger and error
                if let desc = log.triggerEvent?.triggerDescription ?? log.triggerEvent?.deviceName {
                    Text(desc)
                        .font(.footnote)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }

                if let error = log.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(Theme.Status.error)
                        .lineLimit(1)
                }
            }

            // Column 3: Time of execution
            VStack(alignment: .trailing, spacing: 2) {
                Text(log.triggeredAt, style: .time)
                    .font(.footnote)
                    .foregroundColor(Theme.Text.secondary)

                if let duration = displayedDuration {
                    Text(duration)
                        .font(.footnote)
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            .frame(minWidth: 50)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onAppear {
            updateElapsedTime()
            if log.completedAt == nil {
                startTimer()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var displayedDuration: String? {
        if log.completedAt == nil {
            return !elapsedTime.isEmpty ? elapsedTime : nil
        } else {
            return executionDuration
        }
    }

    private var executionDuration: String? {
        guard let completed = log.completedAt else { return nil }
        let interval = completed.timeIntervalSince(log.triggeredAt)
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        } else {
            return String(format: "%.1fs", interval)
        }
    }

    private var statusColor: Color {
        switch log.status {
        case .success: return Theme.Status.active
        case .failure: return Theme.Status.error
        case .running: return .blue
        case .skipped: return Theme.Status.inactive
        case .conditionNotMet: return Theme.Status.warning
        case .cancelled: return Theme.Status.inactive
        }
    }

    private var statusTextColor: Color {
        if log.completedAt == nil {
            return .blue
        }
        return statusColor
    }

    private func updateElapsedTime() {
        guard log.completedAt == nil else { return }
        let interval = Date().timeIntervalSince(log.triggeredAt)
        elapsedTime = formatDuration(interval)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: "%.0fms", interval * 1000)
        } else if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %ds", minutes, seconds)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsedTime()
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        WorkflowExecutionLogRow(
            log: WorkflowExecutionLog(
                id: UUID(),
                workflowId: UUID(),
                workflowName: "Turn Off Lights",
                triggeredAt: Date().addingTimeInterval(-10),
                completedAt: nil,
                triggerEvent: TriggerEvent(
                    deviceId: "device-1",
                    deviceName: "Living Room",
                    serviceId: "service-1",
                    characteristicType: "power",
                    oldValue: nil,
                    newValue: nil,
                    triggerDescription: "Device state changed"
                ),
                conditionResults: nil,
                blockResults: [
                    BlockResult(
                        blockIndex: 0,
                        blockKind: "action",
                        blockType: "control_device",
                        blockName: "Turn Off Light",
                        status: .running,
                        startedAt: Date().addingTimeInterval(-8),
                        completedAt: nil,
                        detail: nil,
                        errorMessage: nil,
                        nestedResults: nil
                    ),
                ],
                status: .running,
                errorMessage: nil
            )
        )

        WorkflowExecutionLogRow(
            log: WorkflowExecutionLog(
                id: UUID(),
                workflowId: UUID(),
                workflowName: "Turn Off Lights",
                triggeredAt: Date().addingTimeInterval(-120),
                completedAt: Date().addingTimeInterval(-115),
                triggerEvent: TriggerEvent(
                    deviceId: "device-1",
                    deviceName: "Living Room",
                    serviceId: "service-1",
                    characteristicType: "power",
                    oldValue: nil,
                    newValue: nil,
                    triggerDescription: "Device state changed"
                ),
                conditionResults: nil,
                blockResults: [
                    BlockResult(
                        blockIndex: 0,
                        blockKind: "action",
                        blockType: "control_device",
                        blockName: "Turn Off Light",
                        status: .success,
                        startedAt: Date().addingTimeInterval(-118),
                        completedAt: Date().addingTimeInterval(-115),
                        detail: nil,
                        errorMessage: nil,
                        nestedResults: nil
                    ),
                ],
                status: .success,
                errorMessage: nil
            )
        )
    }
    .padding()
}
