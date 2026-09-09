import Foundation
import Security

/// Takeover Cloud: optional sync of the user's settings to takeover-api.
/// Settings still live in a local folder (`StorageLocation.cloudCachePath`);
/// each save is pushed as this Mac's profile, and a new Mac restores from the
/// most recently updated one.
@MainActor
final class TakeoverCloud: ObservableObject {
    static let shared = TakeoverCloud()

    @Published private(set) var account: CloudAccount?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    var isSignedIn: Bool { token != nil }

    private var token: String? {
        get { Keychain.read(account: Self.tokenKey) }
        set {
            if let newValue { Keychain.write(newValue, account: Self.tokenKey) } else { Keychain.delete(account: Self.tokenKey) }
            objectWillChange.send()
        }
    }

    private var computerID: Int?
    private static let tokenKey = "takeover-cloud-token"
    private static let clientUUIDKey = "TakeoverCloudClientUUID"

    private init() {}

    // MARK: - Account

    func signIn(login: String, password: String) async throws {
        let response: AuthResponse = try await request("POST", "auth/login", body: ["login": login, "password": password], authorized: false)
        token = response.token
        try await refreshAccount()
    }

    func register(email: String, password: String) async throws {
        let response: AuthResponse = try await request("POST", "auth/register", body: ["email": email, "password": password], authorized: false)
        token = response.token
        try await refreshAccount()
    }

    func signOut() {
        token = nil
        account = nil
        computerID = nil
    }

    /// Reloads the account, including its trial/subscription state.
    func refreshAccount() async throws {
        account = try await request("GET", "auth/me")
    }

    // MARK: - Sync

    /// Pushes the settings as this Mac's profile. Errors are kept in
    /// `lastError` rather than thrown, so a failed sync never blocks a save.
    func push(_ settings: SettingsYaml) async {
        guard isSignedIn else { return }
        do {
            let id = try await registerComputer()
            let _: EmptyResponse = try await request("PUT", "computers/\(id)/profile", body: ["profile": CloudProfile(settings: settings)])
            lastSyncedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The most recently updated profile on the account, if any Mac has
    /// pushed one.
    func latestProfile() async throws -> SettingsYaml? {
        let computers: [CloudComputer] = try await request("GET", "computers")
        guard let latest = computers
            .filter({ $0.profileUpdatedAt != nil })
            .max(by: { ($0.profileUpdatedAt ?? "") < ($1.profileUpdatedAt ?? "") }) else {
            return nil
        }
        let response: ProfileResponse = try await request("GET", "computers/\(latest.id)/profile")
        return response.profile?.settings
    }

    private func registerComputer() async throws -> Int {
        if let computerID { return computerID }
        let uuid = UserDefaults.standard.string(forKey: Self.clientUUIDKey) ?? {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: Self.clientUUIDKey)
            return new
        }()
        let name = Host.current().localizedName ?? "Mac"
        let computer: CloudComputer = try await request("POST", "computers/register", body: ["client_uuid": uuid, "name": name])
        computerID = computer.id
        return computer.id
    }

    // MARK: - HTTP

    private func request<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        authorized: Bool = true
    ) async throws -> Response {
        var request = URLRequest(url: Config.apiBaseURL.appendingPathComponent("api/v1/\(path)"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            guard let token else { throw CloudError.signedOut }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return try JSONDecoder().decode(Response.self, from: data)
        case 401:
            if authorized { signOut() }
            throw CloudError.server(Self.message(in: data) ?? "Please sign in again.")
        case 402:
            throw CloudError.subscriptionRequired
        default:
            throw CloudError.server(Self.message(in: data) ?? "Takeover Cloud returned \(status).")
        }
    }

    private static func message(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? String { return error }
        if let errors = object["errors"] as? [String] { return errors.joined(separator: "\n") }
        return nil
    }
}

// MARK: - Wire types

struct CloudAccount: Decodable {
    let id: Int
    let email: String
    let username: String?
    let subscription: CloudSubscription?
}

/// Trial/subscription state as reported by takeover-api. Admin accounts are
/// free; everyone else gets a 30-day trial, then $3/month.
struct CloudSubscription: Decodable {
    let status: String
    let trialEndsAt: String?
    let price: String?
    let checkoutURL: String?

    enum CodingKeys: String, CodingKey {
        case status, price
        case trialEndsAt = "trial_ends_at"
        case checkoutURL = "checkout_url"
    }

    var trialEndDate: Date? {
        trialEndsAt.flatMap { ISO8601DateFormatter.withFractionalSeconds.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
    }

    var summary: String {
        switch status {
        case "admin":
            return "Admin account, no subscription needed."
        case "trialing":
            if let end = trialEndDate {
                let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
                return "Free trial, \(days) day\(days == 1 ? "" : "s") left. Then \(price ?? "$3/month")."
            }
            return "Free trial. Then \(price ?? "$3/month")."
        case "active":
            return "Subscribed, \(price ?? "$3/month")."
        default:
            return "Trial ended. Subscribe for \(price ?? "$3/month") to keep syncing."
        }
    }

    var needsPayment: Bool { status != "admin" && status != "trialing" && status != "active" }
}

private struct AuthResponse: Decodable {
    let token: String
}

private struct EmptyResponse: Decodable {}

private struct CloudComputer: Decodable {
    let id: Int
    let profileUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case profileUpdatedAt = "profile_updated_at"
    }
}

private struct ProfileResponse: Decodable {
    let profile: CloudProfile?
}

/// Profile schema v1 from takeover-api's README: the settings file's keys plus
/// `apps[].source`.
struct CloudProfile: Codable {
    var version: Int?
    var macDefaults: [MacDefaultConfig]?
    var links: [LinkConfig]?
    var apps: [CloudApp]?

    enum CodingKeys: String, CodingKey {
        case version, links, apps
        case macDefaults = "mac_defaults"
    }

    struct CloudApp: Codable {
        var name: String
        var source: String?
        var path: String?
    }

    init(settings: SettingsYaml) {
        version = 1
        macDefaults = settings.macDefaults ?? []
        links = settings.links
        apps = (settings.appInstallers ?? []).map { CloudApp(name: $0.name, source: "local", path: $0.path) }
    }

    var settings: SettingsYaml {
        SettingsYaml(
            links: links ?? [],
            macDefaults: macDefaults,
            appInstallers: (apps ?? []).compactMap { app in
                app.path.map { AppInstallerConfig(name: app.name, path: $0) }
            }
        )
    }
}

enum CloudError: LocalizedError {
    case signedOut
    case subscriptionRequired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Sign in to Takeover Cloud."
        case .subscriptionRequired: return "Your Takeover Cloud trial has ended. Subscribe for $3/month to keep syncing."
        case .server(let message): return message
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Keychain

private enum Keychain {
    static let service = "alexvaos.Takeover"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
