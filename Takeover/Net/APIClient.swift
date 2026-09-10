import Foundation

/// REST client for takeover-api. JWT is kept in the Keychain. Base URL is
/// overridable via `UserDefaults` key `takeover.apiBaseURL`. Ported/trimmed
/// from AudioBunny's APIClient.
enum APIClient {
    static var baseURL: String {
        UserDefaults.standard.string(forKey: "takeover.apiBaseURL") ?? "http://localhost:3020/api/v1"
    }

    private static let tokenKey = "takeover.jwt"

    private static var token: String? {
        get { KeychainStore.get(key: tokenKey) }
        set {
            if let newValue { KeychainStore.set(newValue, key: tokenKey) }
            else { KeychainStore.remove(key: tokenKey) }
        }
    }

    static var isSignedIn: Bool { token != nil }
    static func clearToken() { token = nil }

    // MARK: - Auth

    static func register(email: String, password: String, username: String) async throws -> AuthResponse {
        let response: AuthResponse = try await send("auth/register", "POST", body: [
            "email": email, "password": password, "username": username,
        ])
        token = response.token
        return response
    }

    static func login(login: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await send("auth/login", "POST", body: [
            "login": login, "password": password,
        ])
        token = response.token
        return response
    }

    static func signInWithApple(idToken: String, email: String?) async throws -> AuthResponse {
        var body = ["id_token": idToken]
        if let email { body["email"] = email }
        let response: AuthResponse = try await send("auth/apple", "POST", body: body)
        token = response.token
        return response
    }

    static func me() async throws -> APIUser {
        try await send("auth/me", "GET")
    }

    // MARK: - Computers / profile

    static func registerComputer(clientUUID: String, name: String) async throws -> APIComputer {
        try await send("computers/register", "POST", body: ["client_uuid": clientUUID, "name": name])
    }

    static func listComputers() async throws -> [APIComputer] {
        try await send("computers", "GET")
    }

    static func fetchProfile(computerID: Int) async throws -> ProfileEnvelope {
        try await send("computers/\(computerID)/profile", "GET")
    }

    @discardableResult
    static func putProfile(computerID: Int, profile: Profile) async throws -> Bool {
        var req = try makeRequest("computers/\(computerID)/profile", method: "PUT")
        req.httpBody = try JSONEncoder().encode(["profile": profile])
        let _: OkResponse = try await perform(req)
        return true
    }

    // MARK: - Plumbing

    private static func send<T: Decodable>(_ path: String, _ method: String, body: [String: String]? = nil) async throws -> T {
        var req = try makeRequest(path, method: method)
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(req)
    }

    private static func makeRequest(_ path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private static func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 { clearToken() }
            throw APIError.serverError(msg)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Rails renders timestamps with fractional seconds ("…:35.011Z"), which
    /// `.iso8601` can't parse — try with and without.
    private static let decoder: JSONDecoder = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "bad date: \(s)"))
        }
        return d
    }()
}

enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .serverError(let m): return m
        }
    }
}

private struct OkResponse: Decodable { let ok: Bool }

private struct APIErrorBody: Decodable {
    let message: String
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let e = try c.decodeIfPresent(String.self, forKey: .error) { message = e }
        else if let errs = try c.decodeIfPresent([String].self, forKey: .errors) { message = errs.joined(separator: ", ") }
        else { message = "Request failed" }
    }
    enum CodingKeys: String, CodingKey { case error, errors }
}
