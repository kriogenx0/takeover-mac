import Foundation
import Yams

struct MacDefaultCatalogEntry: Codable {
    let name: String
    let domain: String
    let key: String
    let type: String
    let hostFlag: String?
    let postCommand: String?
    let category: String?
    /// Inclusive macOS major-version range this default applies to; nil means
    /// no bound.
    let minMacOS: Int?
    let maxMacOS: Int?

    enum CodingKeys: String, CodingKey {
        case name, domain, key, type, category
        case hostFlag = "host_flag"
        case postCommand = "post_command"
        case minMacOS = "min_macos"
        case maxMacOS = "max_macos"
    }

    func supports(macOSMajorVersion version: Int) -> Bool {
        if let minMacOS, version < minMacOS { return false }
        if let maxMacOS, version > maxMacOS { return false }
        return true
    }
}

class MacDefaultCatalog {
    static let shared = MacDefaultCatalog()
    private(set) var entries: [MacDefaultCatalogEntry] = []

    private init() {}

    /// Loads the available defaults from takeover-api (cached, with the bundled
    /// catalog as the offline fallback), keeping only those for this macOS.
    func load() async throws {
        let all = try await RemoteCatalog.load(
            [MacDefaultCatalogEntry].self,
            sources: [RemoteCatalog.catalogURL("mac-defaults.yaml")],
            cacheName: "mac-defaults-catalog",
            bundled: Bundle.main.url(forResource: "mac-defaults-catalog", withExtension: "yaml")
        )
        let version = SystemInfo.macOSMajorVersion
        entries = all.filter { $0.supports(macOSMajorVersion: version) }
    }
}
