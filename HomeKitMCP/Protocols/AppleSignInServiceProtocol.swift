import Foundation

/// Protocol abstracting AppleSignInService for dependency injection and testability.
@MainActor
protocol AppleSignInServiceProtocol: AnyObject {
    var isSignedIn: Bool { get }
    var userIdentifier: String? { get }
    var userEmail: String? { get }
    var userDisplayName: String? { get }

    func signIn()
    func signOut()
    func checkExistingCredential()
}
