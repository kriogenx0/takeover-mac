import Foundation

// Identifies this app install to the server. A Keychain-persisted random UUID
// maps 1:1 to this install and survives a reinstall — deliberately not
// IOPlatformUUID, which is shared by every account on the physical Mac.
// Ported from AudioBunny.
enum ComputerIdentity {
    private static let key = "takeover.computerId"

    static var id: String {
        if let override = UserDefaults.standard.string(forKey: "takeover.computerIdOverride"), !override.isEmpty {
            return override // debug: pretend to be a different Mac (see RestoreView)
        }
        if let existing = KeychainStore.get(key: key) { return existing }
        let generated = UUID().uuidString
        KeychainStore.set(generated, key: key)
        return generated
    }

    static var name: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
}
