import SwiftUI

struct LogRow: View {
    let log: StateChangeLog
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var homeKitViewModel: HomeKitViewModel

    private var isError: Bool {
        log.category == .webhookError || log.category == .serverError
    }

    private var isMCP: Bool {
        log.category == .mcpCall
    }

    private var isWebhookCall: Bool {
        log.category == .webhookCall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Status.error)
                } else if isMCP {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundColor(.teal)
                } else if isWebhookCall {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Tint.secondary)
                }
                Text(log.deviceName)
                    .font(.headline)
                    .foregroundColor(isError ? Theme.Status.error : isMCP ? .teal : isWebhookCall ? Theme.Tint.secondary : Theme.Text.primary)

                if let serviceName = log.serviceName, !isMCP {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                    Text(serviceName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Tint.main.opacity(0.1))
                        .foregroundColor(Theme.Tint.main)
                        .cornerRadius(4)
                }

                Spacer()
                Text(log.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }

            if isMCP {
                // MCP call row — shows method, request, and response
                Text(log.characteristicType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.teal)

                if let requestBody = log.requestBody {
                    Text("→ \(requestBody)")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(2)
                }
                if let responseBody = log.responseBody {
                    Text("← \(responseBody)")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(2)
                }
            } else if isWebhookCall {
                // Successful webhook call
                HStack(spacing: 4) {
                    Text("Webhook")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.Tint.secondary)
                }

                if let requestBody = log.requestBody {
                    Text("→ \(requestBody)")
                        .font(.caption)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(2)
                }
            } else {
                // State change / error row
                HStack(spacing: 4) {
                    Text(log.category == .serverError ? "Server Error" : isError ? "Webhook Error" : CharacteristicTypes.displayName(for: log.characteristicType))
                        .font(.subheadline)
                        .foregroundColor(isError ? Theme.Status.error : Theme.Text.secondary)

                    Spacer()

                    if !isError {
                        if let oldValue = log.oldValue {
                            Text(CharacteristicTypes.formatValue(oldValue.value, characteristicType: log.characteristicType))
                                .font(.subheadline)
                                .foregroundColor(Theme.Text.secondary)

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(Theme.Text.secondary)
                        }

                        if let newValue = log.newValue {
                            Text(CharacteristicTypes.formatValue(newValue.value, characteristicType: log.characteristicType))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.Text.primary)
                        } else {
                            Text("--")
                                .font(.subheadline)
                                .foregroundColor(Theme.Text.secondary)
                        }
                    }
                }

                if let errorDetails = log.errorDetails {
                    Text(errorDetails)
                        .font(.caption)
                        .foregroundColor(Theme.Status.error)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        LogRow(log: PreviewData.sampleLogs[0])
        LogRow(log: PreviewData.sampleLogs[1])
    }
}
