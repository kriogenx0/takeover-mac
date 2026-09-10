import Foundation

// Wire DTOs for takeover-api. See ~/Sites/takeover-api/README.md.

struct AuthResponse: Decodable {
    let token: String
    let user: APIUser
}

struct APIUser: Decodable, Equatable {
    let id: Int
    let email: String
    let username: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, username
        case createdAt = "created_at"
    }
}

struct APIComputer: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let lastSeenAt: Date?
    let profileUpdatedAt: Date?
    let summary: Summary

    struct Summary: Decodable, Equatable {
        let defaults: Int
        let links: Int
        let apps: Int
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary
        case lastSeenAt = "last_seen_at"
        case profileUpdatedAt = "profile_updated_at"
    }
}

struct ProfileEnvelope: Decodable {
    let profile: Profile
    let profileUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case profile
        case profileUpdatedAt = "profile_updated_at"
    }
}
