import Foundation

/// The synced snapshot of a Mac's Takeover setup. Wire-compatible with
/// takeover-api's profile schema (see its README). Self-contained: a restoring
/// Mac needs nothing from its local catalog.
struct Profile: Codable, Equatable {
    var version = 1
    var macDefaults: [MacDefaultEntry] = []
    var links: [LinkEntry] = []
    var apps: [AppEntry] = []

    enum CodingKeys: String, CodingKey {
        case version
        case macDefaults = "mac_defaults"
        case links
        case apps
    }

    struct MacDefaultEntry: Codable, Equatable, Identifiable, Hashable {
        var name: String
        var domain: String
        var key: String
        var type: String
        var value: String
        var hostFlag: String = ""
        var postCommand: String = ""

        var id: String { "\(domain)|\(key)|\(name)" }

        enum CodingKeys: String, CodingKey {
            case name, domain, key, type, value
            case hostFlag = "host_flag"
            case postCommand = "post_command"
        }
    }

    struct LinkEntry: Codable, Equatable, Identifiable, Hashable {
        var name: String
        var from: String
        var to: String
        var defaults: String = ""

        var id: String { "\(name)|\(from)" }
    }

    enum AppSource: String, Codable, CaseIterable {
        case brew, local, mas
    }

    struct AppEntry: Codable, Equatable, Identifiable, Hashable {
        var name: String
        var source: AppSource = .brew
        var cask: String?
        var masID: String?

        var id: String { name }

        enum CodingKeys: String, CodingKey {
            case name, source, cask
            case masID = "mas_id"
        }
    }
}

// MARK: - Build from the local model

extension Profile {
    /// `defaults` should already be filtered to rows with a non-empty value.
    static func snapshot(defaults: [MacDefault], links: [LinkItem], apps: [AppEntryModel]) -> Profile {
        Profile(
            version: 1,
            macDefaults: defaults.map {
                MacDefaultEntry(name: $0.name, domain: $0.domain, key: $0.key, type: $0.type,
                                value: $0.value, hostFlag: $0.hostFlag, postCommand: $0.postCommand)
            },
            links: links.map {
                LinkEntry(name: $0.name, from: $0.from, to: $0.to, defaults: $0.defaults)
            },
            apps: apps.map {
                AppEntry(name: $0.name,
                         source: AppSource(rawValue: $0.source) ?? .brew,
                         cask: $0.cask.isEmpty ? nil : $0.cask,
                         masID: $0.masID.isEmpty ? nil : $0.masID)
            }
        )
    }
}
