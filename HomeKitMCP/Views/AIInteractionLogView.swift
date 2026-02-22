import SwiftUI

// MARK: - List View

struct AIInteractionLogView: View {
    let interactionLog: AIInteractionLogService

    @Environment(\.dismiss) private var dismiss
    @State private var logs: [AIInteractionLog] = []

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Interactions")
                            .font(.headline)
                        Text("AI workflow generation attempts will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(logs) { log in
                        NavigationLink {
                            AIInteractionDetailView(log: log)
                        } label: {
                            AIInteractionLogRow(log: log)
                        }
                        .listRowBackground(Theme.contentBackground)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.mainBackground)
            .navigationTitle("AI Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                logs = await interactionLog.getLogs()
            }
        }
    }
}

// MARK: - Row

private struct AIInteractionLogRow: View {
    let log: AIInteractionLog

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: log.parsedSuccessfully ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(log.parsedSuccessfully ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.operation.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(log.provider)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(log.model)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(log.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1fs", log.durationSeconds))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = log.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail View

struct AIInteractionDetailView: View {
    let log: AIInteractionLog

    var body: some View {
        List {
            // Summary
            Section {
                LabeledContent("Operation", value: log.operation.capitalized)
                LabeledContent("Provider", value: log.provider)
                LabeledContent("Model", value: log.model)
                LabeledContent("Duration", value: String(format: "%.2fs", log.durationSeconds))
                LabeledContent("Result") {
                    Label(
                        log.parsedSuccessfully ? "Success" : "Failed",
                        systemImage: log.parsedSuccessfully ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(log.parsedSuccessfully ? .green : .red)
                }
                LabeledContent("Time") {
                    Text(log.timestamp, format: .dateTime)
                }
            } header: {
                Text("Summary")
            }
            .listRowBackground(Theme.contentBackground)

            // Error
            if let error = log.errorMessage {
                Section {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                } header: {
                    HStack {
                        Text("Error")
                        Spacer()
                        CopyButton(text: error)
                    }
                }
                .listRowBackground(Theme.contentBackground)
            }

            // User Message
            Section {
                Text(log.userMessage)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            } header: {
                HStack {
                    Text("User Message")
                    Spacer()
                    CopyButton(text: log.userMessage)
                }
            }
            .listRowBackground(Theme.contentBackground)

            // Raw Response
            if let response = log.rawResponse {
                Section {
                    Text(response)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } header: {
                    HStack {
                        Text("Raw Response")
                        Spacer()
                        CopyButton(text: response)
                    }
                }
                .listRowBackground(Theme.contentBackground)
            }

            // System Prompt
            Section {
                Text(log.systemPrompt)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            } header: {
                HStack {
                    Text("System Prompt")
                    Spacer()
                    CopyButton(text: log.systemPrompt)
                }
            }
            .listRowBackground(Theme.contentBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Interaction Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Copy Button

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
        }
    }
}
