import SwiftUI

struct AIAssistantSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var aiApiKeyInput = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Workflow Builder", isOn: $viewModel.aiEnabled)

                Group {
                    Picker("Provider", selection: $viewModel.aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    // API Key
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.aiApiKeyConfigured {
                            HStack {
                                Text(String(repeating: "\u{2022}", count: 32))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Label("Configured", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            .allowsHitTesting(false)
                            Button("Clear Key", role: .destructive) {
                                viewModel.clearAIApiKey()
                                aiApiKeyInput = ""
                            }
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                        } else {
                            SecureField("API Key", text: $aiApiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            Button("Save Key") {
                                viewModel.saveAIApiKey(aiApiKeyInput)
                                aiApiKeyInput = ""
                            }
                            .buttonStyle(.borderless)
                            .disabled(aiApiKeyInput.isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { }

                    // Model Override
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Model ID (optional)", text: $viewModel.aiModelId)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Text("Default: \(viewModel.aiProvider.defaultModel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Test Connection
                    HStack {
                        Button {
                            viewModel.testAIConnection()
                        } label: {
                            HStack {
                                if viewModel.isTestingAI {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text("Test Connection")
                            }
                        }
                        .disabled(!viewModel.aiApiKeyConfigured || viewModel.isTestingAI)

                        Spacer()

                        if let result = viewModel.aiTestResult {
                            switch result {
                            case .success:
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            case .failure(let error):
                                Label(error, systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .disabled(!viewModel.aiEnabled)
                .opacity(viewModel.aiEnabled ? 1 : 0.5)
            } header: {
                Label("AI Assistant", systemImage: "sparkles")
            } footer: {
                Text("Configure an LLM provider to create workflows from natural language descriptions.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("AI Assistant")
    }
}

#Preview {
    NavigationStack {
        AIAssistantSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
