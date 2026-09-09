//
//  Item.swift
//  Takeover
//
//  Created by Alex Vaos on 2/12/25.
//

import Foundation
import SwiftData

@Model
class LinkItem: ObservableObject, Identifiable {
    var name: String
    var from: String
    var to: String
    var defaults: String

    init(name: String, from: String = "", to: String = "", defaults: String = "") {
        self.name = name
        self.from = from
        self.to = to
        self.defaults = defaults
    }

    static func empty() -> LinkItem {
        return LinkItem(
            name: "",
            from: "",
            to: "",
            defaults: ""
        )
    }
}

extension LinkItem {
    static let samples = [
        LinkItem(name: "Fonts"),
        LinkItem(name: "Audio Plugins")
    ]
}
