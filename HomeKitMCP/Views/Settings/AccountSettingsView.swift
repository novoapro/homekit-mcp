import SwiftUI
import AuthenticationServices

struct AccountSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var appleSignInService: AppleSignInService

    @State private var showingSignOutConfirmation = false

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.appleSignInService = viewModel.appleSignInService
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
                                        .font(.caption)
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
                            .font(.caption)
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
    }

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
