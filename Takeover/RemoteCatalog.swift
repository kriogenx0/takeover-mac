import Foundation
import Yams

/// Fetches a static catalog file published by takeover-api (served from its
/// `public/catalog/` folder), caching it for a day and falling back to the
/// stale cache and then a bundled copy when offline.
enum RemoteCatalog {
    static let cacheDuration: TimeInterval = 86400 // 1 day

    static func catalogURL(_ fileName: String) -> URL {
        Config.apiBaseURL.appendingPathComponent("catalog").appendingPathComponent(fileName)
    }

    /// - Parameters:
    ///   - sources: tried in order; YAML or JSON, detected from the content.
    ///   - cacheName: file name under the app's Caches folder.
    ///   - bundled: last-resort copy shipped in the app bundle.
    static func load<T: Decodable>(
        _ type: T.Type,
        sources: [URL],
        cacheName: String,
        bundled: URL? = nil
    ) async throws -> T {
        let cacheURL = cacheDirectory.appendingPathComponent(cacheName)

        if isFresh(cacheURL), let data = try? Data(contentsOf: cacheURL),
           let cached = try? decode(type, from: data) {
            return cached
        }

        var lastError: Error?
        for url in sources {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let decoded = try decode(type, from: data)
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try? data.write(to: cacheURL)
                return decoded
            } catch {
                print("Catalog fetch failed for \(url): \(error)")
                lastError = error
            }
        }

        if let data = try? Data(contentsOf: cacheURL), let stale = try? decode(type, from: data) {
            return stale
        }
        if let bundled, let data = try? Data(contentsOf: bundled) {
            return try decode(type, from: data)
        }
        throw lastError ?? URLError(.resourceUnavailable)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let text = String(data: data, encoding: .utf8) ?? ""
        let first = text.first { !$0.isWhitespace }
        if first == "{" || first == "[" {
            return try JSONDecoder().decode(type, from: data)
        }
        return try YAMLDecoder().decode(type, from: text)
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Takeover", isDirectory: true)
    }

    private static func isFresh(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modified) < cacheDuration
    }
}
