import SwiftUI

struct LogRow: View {
    let log: StateChangeLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.deviceName)
                    .font(.headline)
                Spacer()
                Text(log.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Text(CharacteristicTypes.displayName(for: log.characteristicType))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if let oldValue = log.oldValue {
                    Text(CharacteristicTypes.formatValue(oldValue.value, characteristicType: log.characteristicType))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let newValue = log.newValue {
                    Text(CharacteristicTypes.formatValue(newValue.value, characteristicType: log.characteristicType))
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("--")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
