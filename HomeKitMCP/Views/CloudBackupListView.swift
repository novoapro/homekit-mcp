import SwiftUI

struct CloudBackupListView: View {
    @ObservedObject var cloudBackupService: CloudBackupService
    @State private var showingRestoreConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteAllConfirmation = false
    @State private var selectedBackup: CloudBackupMetadata?
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if cloudBackupService.cloudBackups.isEmpty && !cloudBackupService.isSyncing {
                emptyState
            } else {
                backupList
            }
        }
        .navigationTitle("Cloud Backups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        do {
                            try await cloudBackupService.fetchCloudBackups()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(cloudBackupService.isSyncing)
            }
        }
        .task {
            do {
                try await cloudBackupService.fetchCloudBackups()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
        .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
            Button("Restore", role: .destructive) {
                guard let backup = selectedBackup else { return }
                Task {
                    do {
                        try await cloudBackupService.downloadAndRestore(recordName: backup.id)
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let backup = selectedBackup {
                Text("This will replace all current settings, workflows, and device configurations with the backup from \(backup.deviceName) created on \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
        .alert("Delete Backup", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let backup = selectedBackup else { return }
                Task {
                    do {
                        try await cloudBackupService.deleteCloudBackup(recordName: backup.id)
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this cloud backup? This cannot be undone.")
        }
        .alert("Delete All Backups", isPresented: $showingDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) {
                Task {
                    do {
                        try await cloudBackupService.deleteAllCloudBackups()
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all \(cloudBackupService.cloudBackups.count) cloud backups? This cannot be undone.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud")
                .font(.system(size: 48))
                .foregroundColor(Theme.Text.tertiary)
            Text("No Cloud Backups")
                .font(.headline)
                .foregroundColor(Theme.Text.secondary)
            Text("Back up your settings and workflows to iCloud from the Settings page.")
                .font(.caption)
                .foregroundColor(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let error = cloudBackupService.lastSyncError {
                VStack(spacing: 4) {
                    Label("Sync Error", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Backup List

    private var backupList: some View {
        List {
            Section {
                ForEach(cloudBackupService.cloudBackups) { backup in
                    backupRow(backup)
                }
            } header: {
                Text("\(cloudBackupService.cloudBackups.count) backup\(cloudBackupService.cloudBackups.count == 1 ? "" : "s")")
            }

            if cloudBackupService.cloudBackups.count > 1 {
                Section {
                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete All Backups", systemImage: "trash")
                            Spacer()
                        }
                    }
                    .disabled(cloudBackupService.isSyncing)
                }
            }
        }
        .overlay {
            if cloudBackupService.isSyncing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Backup Row

    private func backupRow(_ backup: CloudBackupMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                        .foregroundColor(Theme.Text.primary)
                    HStack(spacing: 8) {
                        Label(backup.deviceName, systemImage: "desktopcomputer")
                        Label("v\(backup.appVersion)", systemImage: "app.badge")
                    }
                    .font(.caption)
                    .foregroundColor(Theme.Text.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Restore") {
                        selectedBackup = backup
                        showingRestoreConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(role: .destructive) {
                        selectedBackup = backup
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
