import SwiftUI

struct WorkflowRow: View {
    let workflow: Workflow
    let recentLogs: [WorkflowExecutionLog]
    let onToggle: () -> Void

    private var statusColor: Color {
        guard workflow.isEnabled else { return Theme.Status.inactive }
        if workflow.metadata.consecutiveFailures > 0 { return Theme.Status.error }
        if workflow.metadata.totalExecutions > 0 { return Theme.Status.active }
        return Theme.Tint.main
    }

    private var lastStatus: ExecutionStatus? {
        recentLogs.first?.status
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

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

            Toggle("", isOn: .constant(workflow.isEnabled))
                .labelsHidden()
                .tint(Theme.Tint.main)
                .onTapGesture {
                    onToggle()
                }
        }
        .padding(.vertical, 4)
    }
}
