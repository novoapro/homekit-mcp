import Foundation
import AuthenticationServices

@MainActor
class AppleSignInService: NSObject, ObservableObject, AppleSignInServiceProtocol {
    @Published var isSignedIn = false
    @Published var userIdentifier: String?
    @Published var userEmail: String?
    @Published var userDisplayName: String?
    @Published var isChecking = false

    private let keychainService: KeychainService

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
        super.init()
    }

    // MARK: - Sign In

    func signIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Sign Out

    func signOut() {
        keychainService.delete(key: KeychainService.Keys.appleSignInUserId)
        keychainService.delete(key: KeychainService.Keys.appleSignInEmail)
        keychainService.delete(key: KeychainService.Keys.appleSignInName)
        isSignedIn = false
        userIdentifier = nil
        userEmail = nil
        userDisplayName = nil
    }

    // MARK: - Check Existing Credential

    func checkExistingCredential() {
        guard let userId = keychainService.read(key: KeychainService.Keys.appleSignInUserId) else {
            isSignedIn = false
            return
        }

        isChecking = true
        Task {
            let provider = ASAuthorizationAppleIDProvider()
            let state = await withCheckedContinuation { continuation in
                provider.getCredentialState(forUserID: userId) { state, _ in
                    continuation.resume(returning: state)
                }
            }

            // Already on @MainActor via Task
            self.isChecking = false
            switch state {
            case .authorized:
                self.isSignedIn = true
                self.userIdentifier = userId
                self.userEmail = self.keychainService.read(key: KeychainService.Keys.appleSignInEmail)
                self.userDisplayName = self.keychainService.read(key: KeychainService.Keys.appleSignInName)
                AppLogger.general.info("Apple Sign In: credential authorized. Name: \(self.userDisplayName ?? "nil"), Email: \(self.userEmail ?? "nil")")
            case .revoked, .notFound:
                AppLogger.general.info("Apple Sign In: credential state = \(state.rawValue), signing out")
                self.signOut()
            default:
                self.isChecking = false
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        let userId = credential.user
        let email = credential.email
        let fullName = credential.fullName

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.userIdentifier = userId
            let savedId = self.keychainService.save(key: KeychainService.Keys.appleSignInUserId, value: userId)
            AppLogger.general.info("Apple Sign In delegate: saved userId=\(savedId)")

            if let email = email {
                self.userEmail = email
                let savedEmail = self.keychainService.save(key: KeychainService.Keys.appleSignInEmail, value: email)
                AppLogger.general.info("Apple Sign In delegate: saved email=\(savedEmail) (\(email))")
            } else {
                // Apple may not provide email on subsequent sign-ins, load from keychain
                self.userEmail = self.keychainService.read(key: KeychainService.Keys.appleSignInEmail)
                AppLogger.general.info("Apple Sign In delegate: email not provided, loaded from keychain: \(self.userEmail ?? "nil")")
            }

            if let name = fullName {
                let displayName = [name.givenName, name.familyName].compactMap { $0 }.joined(separator: " ")
                if !displayName.isEmpty {
                    self.userDisplayName = displayName
                    let savedName = self.keychainService.save(key: KeychainService.Keys.appleSignInName, value: displayName)
                    AppLogger.general.info("Apple Sign In delegate: saved name=\(savedName) (\(displayName))")
                } else {
                    // Load name from keychain if not provided
                    self.userDisplayName = self.keychainService.read(key: KeychainService.Keys.appleSignInName)
                }
            } else {
                // Load name from keychain if not provided
                self.userDisplayName = self.keychainService.read(key: KeychainService.Keys.appleSignInName)
                AppLogger.general.info("Apple Sign In delegate: name not provided, loaded from keychain: \(self.userDisplayName ?? "nil")")
            }

            self.isSignedIn = true
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        // User cancelled or other error — no action needed
        AppLogger.general.error("Apple Sign In failed: \(error.localizedDescription)")
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return windowScene?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}
