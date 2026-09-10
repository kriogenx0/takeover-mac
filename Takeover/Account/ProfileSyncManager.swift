import Foundation
import Combine

@MainActor
final class ProfileSyncManager: ObservableObject {
    static let shared = ProfileSyncManager()

    @Published private(set) var thisComputerID: Int?
    @Published private(set) var isPushing = false
    @Published var lastPushError: String?
    @Published private(set) var lastPushedAt: Date?

    // Restore side
    @Published private(set) var computers: [APIComputer] = []
    @Published var isLoadingComputers = false
    @Published var computersError: String?
    @Published private(set) var profilesByComputer: [Int: Profile] = [:]

    private var pushTask: Task<Void, Never>?

    private init() {}

    func reset() {
        thisComputerID = nil
        computers = []
        profilesByComputer = [:]
        lastPushedAt = nil
        lastPushError = nil
    }

    /// Ensure this Mac has a row on the account. Safe to call repeatedly.
    @discardableResult
    func registerThisMac() async -> Int? {
        guard AccountManager.shared.isSignedIn else { return nil }
        do {
            let computer = try await APIClient.registerComputer(
                clientUUID: ComputerIdentity.id, name: ComputerIdentity.name)
            thisComputerID = computer.id
            return computer.id
        } catch {
            lastPushError = error.localizedDescription
            return nil
        }
    }

    /// Debounced upload of the current profile. No-op when signed out.
    func schedulePush(_ profile: Profile) {
        guard AccountManager.shared.isSignedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.push(profile)
        }
    }

    func push(_ profile: Profile) async {
        guard AccountManager.shared.isSignedIn else { return }
        isPushing = true
        lastPushError = nil
        defer { isPushing = false }
        do {
            var id = thisComputerID
            if id == nil { id = await registerThisMac() }
            guard let id else { return }
            try await APIClient.putProfile(computerID: id, profile: profile)
            lastPushedAt = Date()
        } catch {
            lastPushError = error.localizedDescription
        }
    }

    // MARK: - Restore side

    func loadComputers() async {
        guard AccountManager.shared.isSignedIn else { return }
        isLoadingComputers = true
        computersError = nil
        defer { isLoadingComputers = false }
        do {
            computers = try await APIClient.listComputers()
        } catch {
            computersError = error.localizedDescription
        }
    }

    func profile(for computerID: Int, force: Bool = false) async -> Profile? {
        if !force, let cached = profilesByComputer[computerID] { return cached }
        do {
            let env = try await APIClient.fetchProfile(computerID: computerID)
            profilesByComputer[computerID] = env.profile
            return env.profile
        } catch {
            computersError = error.localizedDescription
            return nil
        }
    }

    func isThisMac(_ computer: APIComputer) -> Bool {
        computer.name == ComputerIdentity.name || computer.id == thisComputerID
    }
}
