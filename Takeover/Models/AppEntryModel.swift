import Foundation
import SwiftData

/// One app in the "restore list" — what gets synced in the profile and
/// (re)installed on another Mac. Distinct from `AppInstaller`, which is just the
/// local folder the Applications tab scans.
@Model
final class AppEntryModel: Identifiable {
    var name: String
    /// `Profile.AppSource` raw value: "brew" | "local" | "mas".
    var source: String
    /// Homebrew cask id, when source == "brew".
    var cask: String
    /// App Store id, when source == "mas" (reserved; not acted on yet).
    var masID: String

    init(name: String = "", source: String = "brew", cask: String = "", masID: String = "") {
        self.name = name
        self.source = source
        self.cask = cask
        self.masID = masID
    }
}
