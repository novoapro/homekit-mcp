import SwiftUI

struct LogRow: View {
    let log: StateChangeLog
    let detailedLogsEnabled: Bool

    @State private var isExpanded = false

    private var hasDetailedData: Bool {
        log.detailedRequestBody != nil || log.detailedResponseBody != nil || (log.workflowExecution?.blockResults.isEmpty == false)
    }

    private func executionStatusColor(_ status: ExecutionStatus) -> Color {
        switch status {
        case .success: return Theme.Status.active
        case .skipped, .conditionNotMet: return Theme.Status.inactive
        case .running: return .blue
        case .failure: return Theme.Status.error
        case .cancelled: return Theme.Status.inactive
        }
    }

    private var categoryColor: Color {
        switch log.payload {
        case .stateChange: return Theme.Tint.main
        case .mcpCall: return Color.teal
        case .restCall: return Color.indigo
        case .webhookCall: return Theme.Tint.secondary
        case .webhookError, .serverError, .sceneError: return Theme.Status.error
        case .workflowError: return Theme.Status.error
        case .workflowExecution: return Theme.Status.active
        case .sceneExecution: return Theme.Tint.main
        case .backupRestore: return Color.orange
        case .aiInteraction: return Color.purple
        case .aiInteractionError: return Theme.Status.error
        }
    }

    var body: some View {
        HStack(alignment: isExpanded ? .firstTextBaseline : .center, spacing: 10) {
            // Column 1: Category icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                categoryIconImage
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(categoryColor)
            }

            // Column 2: Content
            VStack(alignment: .leading, spacing: 4) {
                headerRow
                contentSection

                if detailedLogsEnabled && hasDetailedData && isExpanded {
                    detailSection
                }
            }

            // Column 3: Time
            Text(log.timestamp, style: .time)
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
                .frame(minWidth: 50)

            // Column 4: Chevron
            if detailedLogsEnabled && hasDetailedData {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(.systemGray2))
                    .frame(width: 16)
            } else {
                Color.clear
                    .frame(width: 16, height: 1)
            }
        }
        .padding(.vertical, 8)
        .modifier(ExpandableTapModifier(isExpandable: detailedLogsEnabled && hasDetailedData, isExpanded: $isExpanded))
        .contextMenu {
            Button {
                UIPasteboard.general.string = "\(log.deviceName) — \(log.characteristicType) — \(log.timestamp)"
            } label: {
                Label("Copy Log Entry", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(log.deviceName)
                .font(.headline)
                .foregroundColor(Theme.Text.primary)

            // Room + service badges for device-related categories
            switch log.payload {
            case .stateChange(let p):
                if let roomName = p.roomName { roomBadge(roomName) }
                if let serviceName = p.serviceName { serviceBadge(serviceName) }
            case .webhookCall(let p):
                if let roomName = p.roomName { roomBadge(roomName) }
                if let serviceName = p.serviceName { serviceBadge(serviceName) }
            case .webhookError(let p):
                if let roomName = p.roomName { roomBadge(roomName) }
                if let serviceName = p.serviceName { serviceBadge(serviceName) }
            case .workflowExecution(let e):
                statusBadge(e.status.displayName, color: executionStatusColor(e.status))
            case .workflowError(let e):
                statusBadge(e.status.displayName, color: executionStatusColor(e.status))
            default:
                EmptyView()
            }

            Spacer()
        }
    }

    private func roomBadge(_ name: String) -> some View {
        Text(name)
            .font(.footnote)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.systemGray5))
            .foregroundColor(Theme.Text.secondary)
            .cornerRadius(4)
    }

    private func serviceBadge(_ name: String) -> some View {
        Text(name)
            .font(.footnote)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Tint.main.opacity(0.1))
            .foregroundColor(Theme.Tint.main)
            .cornerRadius(4)
    }

    private func statusBadge(_ status: String, color: Color) -> some View {
        Text(status)
            .font(.footnote)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    // MARK: - Category Icon

    @ViewBuilder
    private var categoryIconImage: some View {
        switch log.payload {
        case .stateChange:
            Image(systemName: "bolt.circle.fill")
        case .mcpCall:
            Image(systemName: "arrow.left.arrow.right.circle.fill")
        case .restCall:
            Image(systemName: "link.circle.fill")
        case .webhookCall:
            Image(systemName: "paperplane.circle.fill")
        case .webhookError, .serverError, .sceneError:
            Image(systemName: "exclamationmark.circle.fill")
        case .workflowError(let e):
            switch e.status {
            case .success: Image(systemName: "checkmark.circle.fill")
            case .cancelled: Image(systemName: "minus.circle.fill")
            default: Image(systemName: "exclamationmark.circle.fill")
            }
        case .workflowExecution:
            Image(systemName: "bolt.circle.fill")
        case .sceneExecution:
            Image(systemName: "play.circle.fill")
        case .backupRestore:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
        case .aiInteraction:
            Image(systemName: "brain.head.profile")
        case .aiInteractionError:
            Image(systemName: "exclamationmark.circle.fill")
        }
    }

    // MARK: - Content (typed payload pattern matching)

    @ViewBuilder
    private var contentSection: some View {
        switch log.payload {
        case .stateChange(let p):
            stateChangeContent(p)
        case .mcpCall(let p):
            apiCallContent(p, color: Color.teal)
        case .restCall(let p):
            apiCallContent(p, color: Color.indigo)
        case .webhookCall(let p):
            webhookCallContent(p)
        case .webhookError(let p):
            webhookErrorContent(p)
        case .serverError(let p):
            errorContent(label: "Server Error", details: p.errorDetails)
        case .workflowExecution(let e):
            workflowContent(e, isError: false)
        case .workflowError(let e):
            workflowContent(e, isError: true)
        case .sceneExecution(let p):
            sceneContent(p)
        case .sceneError(let p):
            sceneErrorContent(p)
        case .backupRestore(let p):
            backupRestoreContent(p)
        case .aiInteraction(let p):
            aiInteractionContent(p)
        case .aiInteractionError(let p):
            aiInteractionContent(p)
        }
    }

    private func stateChangeContent(_ p: DeviceStatePayload) -> some View {
        HStack(spacing: 4) {
            Text(CharacteristicTypes.displayName(for: p.characteristicType))
                .font(.subheadline)
                .foregroundColor(Theme.Text.secondary)
            if let oldValue = p.oldValue {
                Text(CharacteristicTypes.formatValue(oldValue.value, characteristicType: p.characteristicType))
                    .font(.subheadline)
                    .foregroundColor(Theme.Text.secondary)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(Theme.Text.secondary)
            }

            if let newValue = p.newValue {
                Text(CharacteristicTypes.formatValue(newValue.value, characteristicType: p.characteristicType))
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

    private func apiCallContent(_ p: APICallPayload, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.method)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)

            Text("← \(p.result)")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
                .lineLimit(2)
        }
    }

    private func webhookCallContent(_ p: WebhookLogPayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.summary)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Theme.Tint.secondary)
            Text("← \(p.result)")
                .font(.footnote)
                .foregroundColor(Theme.Text.secondary)
        }
    }

    private func webhookErrorContent(_ p: WebhookLogPayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.summary)
                .font(.subheadline)
                .foregroundColor(Theme.Status.error)
            if let errorDetails = p.errorDetails {
                Text(errorDetails)
                    .font(.footnote)
                    .foregroundColor(Theme.Status.error)
                    .lineLimit(3)
            }
        }
    }

    private func errorContent(label: String, details: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Theme.Status.error)
                Spacer()
            }
            Text(details)
                .font(.footnote)
                .foregroundColor(Theme.Status.error)
                .lineLimit(3)
        }
    }

    private func workflowContent(_ e: WorkflowExecutionLog, isError: Bool) -> some View {
        let messageColor = isError ? Theme.Status.error : Theme.Text.secondary
        return VStack(alignment: .leading, spacing: 4) {
            if let trigger = e.triggerEvent {
                let desc = trigger.triggerDescription ?? {
                    guard let deviceName = trigger.deviceName else { return nil as String? }
                    let charName = trigger.characteristicName ?? ""
                    let oldStr = trigger.oldValue.map { "\($0.value)" } ?? "?"
                    let newStr = trigger.newValue.map { "\($0.value)" } ?? "?"
                    return "\(deviceName) \(charName): \(oldStr) → \(newStr)"
                }()
                if let desc {
                    Text(desc)
                        .font(.footnote)
                        .foregroundColor(isError ? Theme.Status.error : Theme.Text.secondary)
                }
            }
            if let errorMessage = e.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(messageColor)
                    .lineLimit(3)
            }
        }
    }

    private func sceneContent(_ p: ScenePayload) -> some View {
        HStack(spacing: 4) {
            if let summary = p.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(Theme.Text.secondary)
            }
        }
    }

    private func sceneErrorContent(_ p: ScenePayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let summary = p.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(Theme.Status.error)
            }
            if let errorDetails = p.errorDetails {
                Text(errorDetails)
                    .font(.footnote)
                    .foregroundColor(Theme.Status.error)
                    .lineLimit(3)
            }
        }
    }

    private func backupRestoreContent(_ p: BackupRestorePayload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.summary)
                .font(.footnote)
                .foregroundColor(p.subtype == "orphan-detection" ? Theme.Status.error : Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func aiInteractionContent(_ p: AIInteractionPayload) -> some View {
        HStack(spacing: 4) {
            Text(p.operation.capitalized)
                .font(.subheadline)
                .foregroundColor(Theme.Text.secondary)
            Text("\u{00B7}")
                .foregroundColor(.secondary)
            Text(p.model)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text("\u{00B7}")
                .foregroundColor(.secondary)
            Text(String(format: "%.1fs", p.durationSeconds))
                .font(.footnote)
                .foregroundColor(.secondary)
            if let error = p.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Detail Expansion

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                // Workflow execution: show inline block tree
                if let execLog = log.workflowExecution {
                    workflowBlockTree(execLog)
                } else {
                    if let detailedReq = log.detailedRequestBody {
                        HStack {
                            Text("Request:")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.Text.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = detailedReq
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.footnote)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.Tint.main)
                        }
                        Text(Self.formatJSON(detailedReq))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Theme.Text.secondary)
                            .textSelection(.enabled)
                    }
                    if let detailedResp = log.detailedResponseBody {
                        HStack {
                            Text("Response:")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.Text.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = detailedResp
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.footnote)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.Tint.main)
                        }
                        Text(Self.formatJSON(detailedResp))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Theme.Text.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray5))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func workflowBlockTree(_ e: WorkflowExecutionLog) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let conditionResults = e.conditionResults, !conditionResults.isEmpty {
                Text("Conditions")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(conditionResults.indices, id: \.self) { i in
                    conditionRow(conditionResults[i], depth: 0)
                }
            }
            if !e.blockResults.isEmpty {
                if e.conditionResults != nil {
                    Divider().padding(.vertical, 2)
                }
                Text("Steps")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Text.secondary)
                ForEach(e.blockResults.indices, id: \.self) { i in
                    blockRow(e.blockResults[i], depth: 0)
                }
            }
        }
    }

    private func conditionRow(_ c: ConditionResult, depth: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(String(repeating: "  ", count: depth))
                    .font(.system(.caption2, design: .monospaced))
                Text(c.passed ? "✓" : "✗")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(c.passed ? Theme.Status.active : Theme.Status.error)
                Text(c.conditionDescription)
                    .font(.caption2)
                    .foregroundColor(Theme.Text.secondary)
            }
            if let subs = c.subResults {
                ForEach(subs.indices, id: \.self) { i in
                    conditionRow(subs[i], depth: depth + 1)
                }
            }
        })
    }

    private func blockRow(_ b: BlockResult, depth: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(String(repeating: "  ", count: depth))
                    .font(.system(.caption2, design: .monospaced))
                blockStatusIcon(b.status)
                    .font(.system(size: 10))
                Text(b.blockName ?? b.blockType)
                    .font(.caption2)
                    .foregroundColor(Theme.Text.secondary)
                if let detail = b.detail, !detail.isEmpty {
                    Text("· \(detail)")
                        .font(.caption2)
                        .foregroundColor(Theme.Text.secondary)
                        .lineLimit(1)
                }
            }
            if let nested = b.nestedResults {
                ForEach(nested.indices, id: \.self) { i in
                    blockRow(nested[i], depth: depth + 1)
                }
            }
        })
    }

    @ViewBuilder
    private func blockStatusIcon(_ status: ExecutionStatus) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.Status.active)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundColor(Theme.Status.error)
        case .skipped, .conditionNotMet:
            Image(systemName: "minus.circle.fill").foregroundColor(Theme.Text.secondary)
        case .cancelled:
            Image(systemName: "minus.circle.fill").foregroundColor(Theme.Status.warning)
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundColor(Theme.Status.active)
        }
    }

    private struct ExpandableTapModifier: ViewModifier {
        let isExpandable: Bool
        @Binding var isExpanded: Bool

        func body(content: Content) -> some View {
            if isExpandable {
                content
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Theme.Animation.expand) {
                            isExpanded.toggle()
                        }
                    }
            } else {
                content
            }
        }
    }

    private static func formatJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return string
        }
        return prettyString
    }
}

#Preview {
    List {
        Section(header: Text("Device State Change")) {
            LogRow(log: PreviewData.sampleLogs[0], detailedLogsEnabled: false)
                .listRowBackground(Theme.contentBackground)
            NavigationLink {
                Text("Workflow Detail View")
            } label: {
                WorkflowExecutionLogRow(log: PreviewData.sampleWorkflowLogs[0])
            }
            .buttonStyle(.plain)
            .listRowBackground(Theme.contentBackground)
            LogRow(log: PreviewData.sampleLogs[1], detailedLogsEnabled: true)
                .listRowBackground(Theme.contentBackground)
            LogRow(log: PreviewData.sampleLogs[2], detailedLogsEnabled: true)
                .listRowBackground(Theme.contentBackground)
            LogRow(log: PreviewData.sampleLogs[3], detailedLogsEnabled: false)
                .listRowBackground(Theme.contentBackground)
            LogRow(log: PreviewData.sampleLogs[4], detailedLogsEnabled: false)
                .listRowBackground(Theme.contentBackground)
            LogRow(log: PreviewData.sampleLogs[5], detailedLogsEnabled: false)
                .listRowBackground(Theme.contentBackground)

            NavigationLink {
                Text("Workflow Detail View")
            } label: {
                WorkflowExecutionLogRow(log: PreviewData.sampleWorkflowLogs[1])
            }
            .listRowBackground(Theme.contentBackground)

            NavigationLink {
                Text("Workflow Detail View")
            } label: {
                WorkflowExecutionLogRow(log: PreviewData.sampleWorkflowLogs[2])
            }
            .listRowBackground(Theme.contentBackground)
        }
    }
    .listStyle(.plain)
}
