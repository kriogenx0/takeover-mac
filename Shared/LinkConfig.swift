import Foundation

struct LinkConfig: Codable {
    var name: String
    var from: String
    var to: String
    var defaults: String?
}

/// One macOS default the user has set. Domain/key/type are stored alongside
/// the value so the file stands on its own, including custom defaults that
/// aren't in the catalog.
struct MacDefaultConfig: Codable {
    var name: String
    var domain: String?
    var key: String?
    var type: String?
    var value: String?
    var hostFlag: String?
    var postCommand: String?
    var capturedOSMajorVersion: Int?

    enum CodingKeys: String, CodingKey {
        case name, domain, key, type, value
        case hostFlag = "host_flag"
        case postCommand = "post_command"
        case capturedOSMajorVersion = "captured_os_major_version"
    }
}

/// Contents of `mac-defaults.yaml` in the user's settings folder.
struct MacDefaultsYaml: Codable {
    var version: Int? = 1
    var macDefaults: [MacDefaultConfig]

    enum CodingKeys: String, CodingKey {
        case version
        case macDefaults = "mac_defaults"
    }
}

struct AppInstallerConfig: Codable {
    var name: String
    var path: String
}
