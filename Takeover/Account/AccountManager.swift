import Foundation
import Combine

@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    @Published private(set) var currentUser: APIUser?
    @Published var authError: String?
    @Published var isLoadingAuth = false
    /// Flips true once `refresh()` has run its first time this launch — lets
    /// the UI wait for a real answer before deciding whether to prompt for
    /// sign-in, instead of racing the initial (always signed-out) state.
    @Published private(set) var hasCheckedAuth = false

    var isSignedIn: Bool { currentUser != nil && APIClient.isSignedIn }

    private init() {}

    /// Called on launch: if a token is stored, confirm it still works.
    func refresh() async {
        defer { hasCheckedAuth = true }
        guard APIClient.isSignedIn else { return }
        do {
            currentUser = try await APIClient.me()
        } catch {
            // Token rejected / server down — treat as signed out but keep quiet.
            currentUser = nil
        }
    }

    func register(email: String, password: String, username: String) async {
        await run { try await APIClient.register(email: email, password: password, username: username) }
    }

    func login(login: String, password: String) async {
        await run { try await APIClient.login(login: login, password: password) }
    }

    func loginWithApple(idToken: String, email: String?) async {
        await run { try await APIClient.signInWithApple(idToken: idToken, email: email) }
    }

    func signOut() {
        APIClient.clearToken()
        currentUser = nil
        ProfileSyncManager.shared.reset()
    }

    private func run(_ call: () async throws -> AuthResponse) async {
        isLoadingAuth = true
        authError = nil
        defer { isLoadingAuth = false }
        do {
            let response = try await call()
            currentUser = response.user
            await ProfileSyncManager.shared.registerThisMac()
        } catch {
            authError = error.localizedDescription
        }
    }
}
