import SwiftUI

struct LogRow: View {
    let log: StateChangeLog

    private var isError: Bool {
        log.category == .webhookError || log.category == .serverError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.Status.error)
                }
                Text(log.deviceName)
                    .font(.headline)
                    .foregroundColor(isError ? Theme.Status.error : Theme.Text.primary)
                Spacer()
                Text(log.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
            }

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
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        LogRow(log: PreviewData.sampleLogs[0])
        LogRow(log: PreviewData.sampleLogs[1])
    }
}
