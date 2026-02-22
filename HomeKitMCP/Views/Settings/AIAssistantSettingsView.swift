import SwiftUI

struct AIAssistantSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let aiWorkflowService: AIWorkflowService

    @State private var aiApiKeyInput = ""
    @State private var showingDiagnostics = false
    @State private var showingSystemPrompt = false

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

            Section {
                DisclosureGroup("System Prompt", isExpanded: $showingSystemPrompt) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Customize the instructions sent to the AI model. Edit directly or reset to restore the built-in default.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $viewModel.aiSystemPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 200, maxHeight: 400)
                            .padding(4)
                            .background(Theme.contentBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                        HStack {
                            if viewModel.aiSystemPrompt == AIWorkflowService.defaultSystemPrompt {
                                Label("Using default prompt", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label("Using custom prompt", systemImage: "pencil.circle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            if viewModel.aiSystemPrompt != AIWorkflowService.defaultSystemPrompt {
                                Button("Reset to Default", role: .destructive) {
                                    viewModel.resetAISystemPrompt()
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            } header: {
                Label("Prompt Configuration", systemImage: "text.alignleft")
            } footer: {
                Text("The system prompt defines how the AI generates workflows. Device and scene context is automatically appended to each request.")
            }
            .disabled(!viewModel.aiEnabled)
            .opacity(viewModel.aiEnabled ? 1 : 0.5)

            Section {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("View Interaction History", systemImage: "clock.arrow.circlepath")
                }

                Button("Clear History", role: .destructive) {
                    Task { await aiWorkflowService.interactionLog.clearLogs() }
                }
            } header: {
                Label("Diagnostics", systemImage: "wrench.and.screwdriver")
            } footer: {
                Text("View prompts, responses, and errors from AI workflow generation attempts.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("AI Assistant")
        .sheet(isPresented: $showingDiagnostics) {
            AIInteractionLogView(interactionLog: aiWorkflowService.interactionLog)
        }
    }
}

#Preview {
    NavigationStack {
        AIAssistantSettingsView(
            viewModel: PreviewData.settingsViewModel,
            aiWorkflowService: PreviewData.settingsViewModel.aiWorkflowService
        )
    }
}
