import Foundation
import SwiftData

@Model
class AppInstaller: ObservableObject, Identifiable {
    var name: String
    var path: String

    init(name: String = "", path: String = "") {
        self.name = name
        self.path = path
    }
}
