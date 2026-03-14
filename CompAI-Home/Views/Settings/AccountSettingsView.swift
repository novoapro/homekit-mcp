import SwiftUI
import AuthenticationServices
import UniformTypeIdentifiers

struct AccountSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var appleSignInService: AppleSignInService
    @ObservedObject private var cloudBackupService: CloudBackupService
    @ObservedObject private var subscriptionService: SubscriptionService

    @State private var showingSignOutConfirmation = false
    @State private var showingCloudBackupSuccess = false
    @State private var showingBackupError = false
    @State private var backupErrorMessage = ""
    @State private var showingFileExporter = false
    @State private var showingFileImporter = false
    @State private var exportDocument: BackupDocument?
    @State private var showingExportSuccess = false
    @State private var showingImportConfirmation = false
    @State private var pendingImportBundle: BackupBundle?
    @State private var showingImportSuccess = false
    @State private var isExporting = false

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.appleSignInService = viewModel.appleSignInService
        self.cloudBackupService = viewModel.cloudBackupService
        self.subscriptionService = viewModel.subscriptionService
    }

    var body: some View {
        Form {
            Section {
                if appleSignInService.isSignedIn {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundColor(Theme.Tint.main)
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = appleSignInService.userDisplayName, !name.isEmpty {
                                Text(name)
                                    .font(.body)
                                if let email = appleSignInService.userEmail, !email.isEmpty {
                                    Text(email)
                                        .font(.footnote)
                                        .foregroundColor(Theme.Text.secondary)
                                }
                            } else if let email = appleSignInService.userEmail, !email.isEmpty {
                                Text(email)
                                    .font(.body)
                            } else {
                                Text("Apple ID Connected")
                                    .font(.body)
                            }
                        }
                        Spacer()
                        Label("Signed In", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.footnote)
                    }

                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                handleAppleSignIn(credential: credential)
                            }
                        case .failure(let error):
                            AppLogger.general.error("Apple Sign In failed: \(error.localizedDescription)")
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                }
            } header: {
                Label("Account", systemImage: "person.crop.circle")
            } footer: {
                if appleSignInService.isSignedIn {
                    Text("Signed in with Apple. You can back up your data to iCloud.")
                } else {
                    Text("Sign in with Apple to enable iCloud backup and restore.")
                }
            }

            // Subscription
            Section {
                NavigationLink {
                    SubscriptionSettingsView(subscriptionService: subscriptionService)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.body)
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(.yellow, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Text("Subscription")
                            .foregroundColor(Theme.Text.primary)

                        Spacer()

                        Text(subscriptionService.currentTier == .pro ? "Pro" : "Free")
                            .font(.subheadline)
                            .foregroundColor(subscriptionService.currentTier == .pro ? Theme.Status.active : Theme.Text.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("Subscription", systemImage: "crown")
            }

            // iCloud Backup section (only when signed in)
            if appleSignInService.isSignedIn {
                Section {
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

                    Toggle("Auto-Backup to iCloud", isOn: Binding(
                        get: { cloudBackupService.autoBackupEnabled },
                        set: { cloudBackupService.autoBackupEnabled = $0 }
                    ))

                    if cloudBackupService.autoBackupEnabled {
                        Picker("Backup Frequency", selection: Binding(
                            get: { cloudBackupService.autoBackupIntervalHours },
                            set: { cloudBackupService.autoBackupIntervalHours = $0 }
                        )) {
                            Text("Every hour").tag(1)
                            Text("Every 6 hours").tag(6)
                            Text("Every 12 hours").tag(12)
                            Text("Every 24 hours").tag(24)
                            Text("Every 48 hours").tag(48)
                        }
                    }

                    if let lastDate = cloudBackupService.lastCloudBackupDate {
                        LabeledContent("Last Cloud Backup") {
                            Text(lastDate, format: .dateTime.month().day().hour().minute())
                                .foregroundColor(Theme.Text.secondary)
                        }
                    }

                    NavigationLink {
                        CloudBackupListView(cloudBackupService: cloudBackupService)
                    } label: {
                        Label("Manage Cloud Backups...", systemImage: "icloud")
                    }
                } header: {
                    Label("iCloud Backup", systemImage: "icloud")
                } footer: {
                    Text("Backups include settings, automations, device configurations, and API keys.")
                }
            }

            // Local file backup section (always available)
            Section {
                Button {
                    Task {
                        isExporting = true
                        do {
                            let bundle = try await viewModel.backupService.createBackup()
                            exportDocument = BackupDocument(bundle: bundle)
                            showingFileExporter = true
                        } catch {
                            backupErrorMessage = error.localizedDescription
                            showingBackupError = true
                        }
                        isExporting = false
                    }
                } label: {
                    HStack {
                        Label("Export Backup to File...", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isExporting)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import Backup from File...", systemImage: "square.and.arrow.down")
                }
            } header: {
                Label("Local Backup", systemImage: "folder")
            } footer: {
                Text("Export your backup to a file you control, or import a previously exported backup. The file includes settings, automations, and API keys.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Account")
        .alert("Sign Out?", isPresented: $showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                appleSignInService.signOut()
            }
        } message: {
            Text("You will no longer be able to back up to or restore from iCloud until you sign in again.")
        }
        .alert("Cloud Backup Complete", isPresented: $showingCloudBackupSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been backed up to iCloud.")
        }
        .alert("Error", isPresented: $showingBackupError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupErrorMessage)
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .compaiBackup,
            defaultFilename: "CompAI-Home-Backup-\(Self.dateFormatter.string(from: Date()))"
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                showingExportSuccess = true
            case .failure(let error):
                backupErrorMessage = error.localizedDescription
                showingBackupError = true
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.compaiBackup, .json]
        ) { result in
            switch result {
            case .success(let url):
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let bundle = try JSONDecoder.iso8601.decode(BackupBundle.self, from: data)
                    pendingImportBundle = bundle
                    showingImportConfirmation = true
                } catch {
                    backupErrorMessage = "Could not read backup file: \(error.localizedDescription)"
                    showingBackupError = true
                }
            case .failure(let error):
                backupErrorMessage = error.localizedDescription
                showingBackupError = true
            }
        }
        .alert("Backup Exported", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your backup has been saved to the selected location.")
        }
        .alert("Restore from File?", isPresented: $showingImportConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingImportBundle = nil
            }
            Button("Restore", role: .destructive) {
                guard let bundle = pendingImportBundle else { return }
                pendingImportBundle = nil
                Task {
                    do {
                        try await viewModel.backupService.restoreBackup(bundle)
                        showingImportSuccess = true
                    } catch {
                        backupErrorMessage = error.localizedDescription
                        showingBackupError = true
                    }
                }
            }
        } message: {
            if let bundle = pendingImportBundle {
                Text("This will replace all current settings, automations, and API keys with the backup from \(bundle.deviceName) created on \(bundle.createdAt.formatted(.dateTime.month().day().year().hour().minute())).")
            } else {
                Text("This will replace all current data with the backup.")
            }
        }
        .alert("Backup Restored", isPresented: $showingImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been restored from the backup file.")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) {
        let userId = credential.user
        let savedId = viewModel.keychainService.save(key: KeychainService.Keys.appleSignInUserId, value: userId)
        AppLogger.general.info("handleAppleSignIn: savedUserId=\(savedId), userId=\(userId)")

        if let email = credential.email {
            let savedEmail = viewModel.keychainService.save(key: KeychainService.Keys.appleSignInEmail, value: email)
            AppLogger.general.info("handleAppleSignIn: savedEmail=\(savedEmail), email=\(email)")
        } else {
            AppLogger.general.info("handleAppleSignIn: no email provided by Apple (expected on subsequent sign-ins)")
        }

        if let name = credential.fullName {
            let displayName = [name.givenName, name.familyName].compactMap { $0 }.joined(separator: " ")
            if !displayName.isEmpty {
                let savedName = viewModel.keychainService.save(key: KeychainService.Keys.appleSignInName, value: displayName)
                AppLogger.general.info("handleAppleSignIn: savedName=\(savedName), name=\(displayName)")
            }
        } else {
            AppLogger.general.info("handleAppleSignIn: no name provided by Apple (expected on subsequent sign-ins)")
        }

        appleSignInService.isSignedIn = true
        appleSignInService.userIdentifier = userId
        appleSignInService.userEmail = credential.email
            ?? viewModel.keychainService.read(key: KeychainService.Keys.appleSignInEmail)
        let savedName: String? = {
            if let name = credential.fullName {
                let display = [name.givenName, name.familyName].compactMap { $0 }.joined(separator: " ")
                return display.isEmpty ? nil : display
            }
            return nil
        }()
        appleSignInService.userDisplayName = savedName
            ?? viewModel.keychainService.read(key: KeychainService.Keys.appleSignInName)
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
