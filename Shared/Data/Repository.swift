//
//  Repository.swift
//  Takeover
//
//  Created by Alex Vaos on 11/7/25.
//

import Foundation
import Observation

struct RepositoryResponse: Decodable {
    let version: Int
    let os_recipies: [OSRecipe]?
    let apps: [AppConfig]

    enum CodingKeys: String, CodingKey {
        case version
        case os_recipies
        case apps
    }
}

struct OSRecipe: Decodable, Identifiable {
    let id = UUID()
    let name: String
    let defaults: String

    enum CodingKeys: String, CodingKey {
        case name
        case defaults
    }
}

struct AppConfig: Decodable, Identifiable {
    let id = UUID()
    let name: String
    let files: [FileConfig]
    let defaults: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case files
        case defaults
    }
}

struct FileConfig: Decodable {
    let path: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let pathString = try? container.decode(String.self) {
            // Handle string format: "/Library/Audio/Plug-Ins"
            self.path = pathString
        } else {
            // Handle object format: {"path": "~/.ssh"}
            let fileObject = try decoder.container(keyedBy: CodingKeys.self)
            self.path = try fileObject.decode(String.self, forKey: .path)
        }
    }

    enum CodingKeys: String, CodingKey {
        case path
    }
}

@Observable
class Repository {
    static let shared = Repository()

    private(set) var response: RepositoryResponse?
    private(set) var isLoading = false
    private(set) var error: Error?

    /// App catalog published by takeover-api; the old JSON in this repo is kept
    /// as a fallback until the API serves the file.
    private let sources = [
        RemoteCatalog.catalogURL("apps.yaml"),
        URL(string: "https://raw.githubusercontent.com/kriogenx0/takeover/main/api/repository.json")!,
    ]

    private init() {}

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            response = try await RemoteCatalog.load(RepositoryResponse.self, sources: sources, cacheName: "apps-catalog")
        } catch let fetchError {
            error = fetchError
        }
    }
}
