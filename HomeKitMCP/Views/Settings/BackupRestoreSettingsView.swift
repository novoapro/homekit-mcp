import SwiftUI

struct BackupRestoreSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var appleSignInService: AppleSignInService
    @ObservedObject private var cloudBackupService: CloudBackupService

    @State private var showingImportPicker = false
    @State private var showingRestoreConfirmation = false
    @State private var showingBackupError = false
    @State private var showingBackupSuccess = false
    @State private var showingRestoreSuccess = false
    @State private var backupErrorMessage = ""
    @State private var pendingRestoreBundle: BackupBundle?
    @State private var exportFileURL: URL?
    @State private var showingCloudBackupSuccess = false
    @State private var showingResetConfirmation = false

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.appleSignInService = viewModel.appleSignInService
        self.cloudBackupService = viewModel.cloudBackupService
    }

    var body: some View {
        Form {
            Section {
                // Export
                Button {
                    Task {
                        do {
                            let url = try await viewModel.backupService.exportToFile()
                            exportFileURL = url
                        } catch {
                            backupErrorMessage = error.localizedDescription
                            showingBackupError = true
                        }
                    }
                } label: {
                    HStack {
                        Label("Export Backup...", systemImage: "square.and.arrow.up")
                        Spacer()
                        if viewModel.backupService.isBackingUp {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(viewModel.backupService.isBackingUp)

                // Import
                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import Backup...", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.backupService.isRestoring)
            } header: {
                Label("Local Backup", systemImage: "internaldrive")
            }

            // iCloud section (only when signed in)
            if appleSignInService.isSignedIn {
                Section {
                    // Back Up to iCloud
                    Button {
                        Task {
                            do {
                                try await cloudBackupService.saveToCloud()
                                showingCloudBackupSuccess = true
                            } catch {
                                backupErrorMessage = error.localizedDescription
                                showingBackupError = true
                            }
                        }
                    } label: {
                        HStack {
                            Label("Back Up to iCloud", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            if cloudBackupService.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(cloudBackupService.isSyncing)

                    // Auto-Backup toggle
                    Toggle("Auto-Backup to iCloud", isOn: Binding(
                        get: { cloudBackupService.autoBackupEnabled },
                        set: { cloudBackupService.autoBackupEnabled = $0 }
                    ))

                    // Last backup info
                    if let lastDate = cloudBackupService.lastCloudBackupDate {
                        LabeledContent("Last Cloud Backup") {
                            Text(lastDate, format: .dateTime.month().day().hour().minute())
                                .foregroundColor(Theme.Text.secondary)
                        }
                    }

                    // Manage cloud backups
                    NavigationLink {
                        CloudBackupListView(cloudBackupService: cloudBackupService)
                    } label: {
                        Label("Manage Cloud Backups...", systemImage: "icloud")
                    }
                } header: {
                    Label("iCloud", systemImage: "icloud")
                } footer: {
                    Text("Backups include settings, workflows, device configurations, and API keys.")
                }
            }

            Section {
                Button("Reset Device Configuration", role: .destructive) {
                    showingResetConfirmation = true
                }
            } header: {
                Label("Data", systemImage: "externaldrive")
            } footer: {
                Text("Resets all per-device MCP visibility and webhook notification toggles to defaults.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Backup & Restore")
        .alert("Reset Device Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                viewModel.resetDeviceConfiguration()
            }
        } message: {
            Text("This will reset all MCP and webhook toggles to their defaults (MCP: on, Webhook: off).")
        }
        .alert("Restore Backup?", isPresented: $showingRestoreConfirmation) {
            Button("Cancel", role: .cancel) { pendingRestoreBundle = nil }
            Button("Restore", role: .destructive) {
                guard let bundle = pendingRestoreBundle else { return }
                Task {
                    do {
                        try await viewModel.backupService.restoreBackup(bundle)
                        showingRestoreSuccess = true
                    } catch {
                        backupErrorMessage = error.localizedDescription
                        showingBackupError = true
                    }
                    pendingRestoreBundle = nil
                }
            }
        } message: {
            if let bundle = pendingRestoreBundle {
                Text("This will replace all current settings, workflows, and device configurations with the backup from \(bundle.deviceName) created on \(bundle.createdAt.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
        .alert("Error", isPresented: $showingBackupError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupErrorMessage)
        }
        .alert("Backup Exported", isPresented: $showingBackupSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your backup has been exported successfully.")
        }
        .alert("Restore Complete", isPresented: $showingRestoreSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All settings, workflows, and device configurations have been restored. You may need to restart the app for all changes to take effect.")
        }
        .alert("Cloud Backup Complete", isPresented: $showingCloudBackupSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been backed up to iCloud.")
        }
        .sheet(item: $exportFileURL) { url in
            DocumentExportPicker(url: url)
        }
        .sheet(isPresented: $showingImportPicker) {
            DocumentImportPicker { url in
                Task {
                    do {
                        let bundle = try await viewModel.backupService.importFromFile(url: url)
                        pendingRestoreBundle = bundle
                        showingRestoreConfirmation = true
                    } catch {
                        backupErrorMessage = error.localizedDescription
                        showingBackupError = true
                    }
                }
            }
        }
    }
}

// MARK: - URL + Identifiable (for item-based sheet)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Document Export Picker

struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

// MARK: - Document Import Picker

struct DocumentImportPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

#Preview {
    NavigationStack {
        BackupRestoreSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
