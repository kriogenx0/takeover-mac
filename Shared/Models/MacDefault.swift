import Foundation
import SwiftData

@Model
class MacDefault: ObservableObject, Identifiable {
    var name: String
    var domain: String
    var key: String
    var type: String
    var value: String
    var hostFlag: String
    var postCommand: String
    var capturedOSMajorVersion: Int = 0

    init(name: String, domain: String = "", key: String = "", type: String = "string", value: String = "", hostFlag: String = "", postCommand: String = "", capturedOSMajorVersion: Int = 0) {
        self.name = name
        self.domain = domain
        self.key = key
        self.type = type
        self.value = value
        self.hostFlag = hostFlag
        self.postCommand = postCommand
        self.capturedOSMajorVersion = capturedOSMajorVersion
    }

    /// Human-readable form shown in the UI. Not used for execution.
    var readCommand: String {
        let flag = hostFlag.isEmpty ? "" : "\(hostFlag) "
        return "defaults \(flag)read \(domain) \(key)"
    }

    /// Human-readable form shown in the UI. Not used for execution.
    var writeCommand: String {
        guard !value.isEmpty else { return "" }
        let flag = hostFlag.isEmpty ? "" : "\(hostFlag) "
        return "defaults \(flag)write \(domain) \(key) -\(type) \(value)"
    }

    /// Argument vector for `/usr/bin/defaults` — no shell, so `value` may contain
    /// spaces and the `domain` may be a bare `-g`.
    var readArguments: [String] {
        (hostFlag.isEmpty ? [] : [hostFlag]) + ["read", domain, key]
    }

    /// nil when there's no value to write.
    var writeArguments: [String]? {
        guard !value.isEmpty else { return nil }
        return (hostFlag.isEmpty ? [] : [hostFlag]) + ["write", domain, key, "-\(type)", value]
    }
}
