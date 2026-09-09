import Foundation
import Yams

private struct SettingsFile: Codable {
    var links: [LinkConfig]
}

func loadSettings() throws -> [LinkConfig] {
    let path = Config.settingsPath
    guard let data = FileManager.default.contents(atPath: path),
          let yaml = String(data: data, encoding: .utf8) else {
        throw SettingsError.notFound(path)
    }
    return try YAMLDecoder().decode(SettingsFile.self, from: yaml).links
}

enum SettingsError: LocalizedError {
    case notFound(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let path): return "Settings file not found at: \(path)"
        }
    }
}
