import SwiftUI

struct WorkflowRow: View {
    let workflow: Workflow
    let recentLogs: [WorkflowExecutionLog]
    let onToggle: () -> Void

    @State private var isEnabled: Bool = false
    @State private var isHovered = false

    private var statusColor: Color {
        guard workflow.isEnabled else { return Theme.Status.inactive }
        if workflow.metadata.consecutiveFailures > 0 { return Theme.Status.error }
        if workflow.metadata.totalExecutions > 0 { return Theme.Status.active }
        return Theme.Tint.main
    }

    private var lastStatus: ExecutionStatus? {
        recentLogs.first?.status
    }

    /// Icon and color based on primary trigger type
    private var triggerIcon: String {
        guard let firstTrigger = workflow.triggers.first else { return "bolt.fill" }
        switch firstTrigger {
        case .deviceStateChange: return "bolt.fill"
        case .schedule: return "clock.fill"
        case .webhook: return "arrow.down.circle.fill"
        case .compound: return "arrow.triangle.branch"
        case .workflow: return "arrow.triangle.turn.up.right.diamond"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Circular trigger-type icon (36x36, matching Home app style)
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: triggerIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(workflow.name)
                        .font(.headline)
                        .foregroundColor(Theme.Text.primary)

                    if !workflow.isEnabled {
                        Text("Disabled")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .foregroundColor(Theme.Text.secondary)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    // Trigger type pill
                    if let firstTrigger = workflow.triggers.first {
                        Text(triggerTypeLabel(firstTrigger))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.1))
                            .foregroundColor(statusColor)
                            .cornerRadius(4)
                    }

                    // Trigger count
                    Label("\(workflow.triggers.count)", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)

                    // Block count
                    Label("\(workflow.blocks.count)", systemImage: "list.number")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)

                    // Execution count
                    if workflow.metadata.totalExecutions > 0 {
                        Label("\(workflow.metadata.totalExecutions)", systemImage: "play.circle")
                            .font(.caption)
                            .foregroundColor(Theme.Text.secondary)
                    }
                }

                if let description = workflow.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }

                if let lastTriggered = workflow.metadata.lastTriggeredAt {
                    Text("Last triggered \(lastTriggered, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(Theme.Text.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Theme.Tint.main)
                .onChange(of: isEnabled) { newValue in
                    if newValue != workflow.isEnabled {
                        onToggle()
                    }
                }
        }
        .padding(.vertical, 8)
        .onAppear { isEnabled = workflow.isEnabled }
        .onChange(of: workflow.isEnabled) { newValue in
            isEnabled = newValue
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(workflow.isEnabled ? "Disable" : "Enable",
                      systemImage: workflow.isEnabled ? "pause.circle" : "play.circle")
            }
        }
    }

    private func triggerTypeLabel(_ trigger: WorkflowTrigger) -> String {
        switch trigger {
        case .deviceStateChange: return "Device"
        case .schedule: return "Schedule"
        case .webhook: return "Webhook"
        case .compound: return "Compound"
        case .workflow: return "Workflow"
        }
    }
}
