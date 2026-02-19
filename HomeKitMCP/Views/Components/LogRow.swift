import SwiftUI

struct LogRow: View {
    let log: StateChangeLog
    let detailedLogsEnabled: Bool

    @State private var isExpanded = false

    private var isError: Bool {
        log.category == .webhookError || log.category == .serverError
    }

    private var isMCP: Bool {
        log.category == .mcpCall
    }

    private var isREST: Bool {
        log.category == .restCall
    }

    private var isWebhookCall: Bool {
        log.category == .webhookCall
    }

    private var hasDetailedData: Bool {
        log.detailedRequestBody != nil || log.detailedResponseBody != nil
    }

    /// Tint color for the log category.
    private var categoryColor: Color {
        if isError { return Theme.Status.error }
        if isMCP { return .teal }
        if isREST { return .indigo }
        if isWebhookCall { return Theme.Tint.secondary }
        return Theme.Text.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: icon + name + service badge + timestamp
            headerRow

            // Content: action + result per category
            contentSection

            // Expandable detail CTA
            if detailedLogsEnabled && hasDetailedData {
                detailSection
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            categoryIcon
            Text(log.deviceName)
                .font(.headline)
                .foregroundColor(categoryColor)

            if let serviceName = log.serviceName, !isMCP && !isREST {
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
    }

    @ViewBuilder
    private var categoryIcon: some View {
        switch log.category {
        case .webhookError, .serverError:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(Theme.Status.error)
        case .mcpCall:
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.caption)
                .foregroundColor(.teal)
        case .restCall:
            Image(systemName: "globe")
                .font(.caption)
                .foregroundColor(.indigo)
        case .webhookCall:
            Image(systemName: "paperplane.circle.fill")
                .font(.caption)
                .foregroundColor(Theme.Tint.secondary)
        case .stateChange:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        switch log.category {
        case .mcpCall:
            mcpContent
        case .restCall:
            restContent
        case .webhookCall:
            webhookContent
        case .webhookError, .serverError:
            errorContent
        case .stateChange:
            stateChangeContent
        }
    }

    private var mcpContent: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        }
    }

    private var restContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(log.characteristicType)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.indigo)

            if let responseBody = log.responseBody {
                Text("← \(responseBody)")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var webhookContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let requestBody = log.requestBody {
                Text(requestBody)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Tint.secondary)
            }
            if let responseBody = log.responseBody {
                Text("← \(responseBody)")
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }
        }
    }

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(log.category == .serverError ? "Server Error" : "Webhook Error")
                    .font(.subheadline)
                    .foregroundColor(Theme.Status.error)
                Spacer()
            }
            if let errorDetails = log.errorDetails {
                Text(errorDetails)
                    .font(.caption)
                    .foregroundColor(Theme.Status.error)
                    .lineLimit(3)
            }
        }
    }

    private var stateChangeContent: some View {
        HStack(spacing: 4) {
            Text(CharacteristicTypes.displayName(for: log.characteristicType))
                .font(.subheadline)
                .foregroundColor(Theme.Text.secondary)

            Spacer()

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

    // MARK: - Detail Expansion

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(isExpanded ? "Hide Details" : "Show Details")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(Theme.Tint.main)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let detailedReq = log.detailedRequestBody {
                        Text("Request:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Text.secondary)
                        Text(Self.formatJSON(detailedReq))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Theme.Text.secondary)
                            .textSelection(.enabled)
                    }
                    if let detailedResp = log.detailedResponseBody {
                        Text("Response:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Text.secondary)
                        Text(Self.formatJSON(detailedResp))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Theme.Text.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(6)
            }
        }
    }

    /// Attempts to pretty-print a JSON string; returns as-is if not valid JSON.
    private static func formatJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return string
        }
        return prettyString
    }
}

#Preview {
    List {
        LogRow(log: PreviewData.sampleLogs[0], detailedLogsEnabled: true)
        LogRow(log: PreviewData.sampleLogs[1], detailedLogsEnabled: false)
    }
}
