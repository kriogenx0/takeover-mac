import Foundation

struct MacDefaultInstaller {

    @MainActor
    private static func readSystemValue(macDefault: MacDefault) -> String {
        let result = Linker.shell(macDefault.readCommand)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notFound = result.isEmpty
            || result.contains("does not exist")
            || result.contains("The domain/defaults pair")
        return notFound ? "" : result
    }

    @discardableResult
    @MainActor
    static func capture(macDefault: MacDefault) -> String {
        let result = readSystemValue(macDefault: macDefault)
        if !result.isEmpty {
            macDefault.value = result
            macDefault.capturedOSMajorVersion = SystemInfo.macOSMajorVersion
        }
        return result
    }

    /// Reads the current system value without modifying `macDefault.value`, for comparison against the stored value.
    @MainActor
    static func peekSystemValue(macDefault: MacDefault) -> String {
        readSystemValue(macDefault: macDefault)
    }

    @MainActor
    static func apply(macDefault: MacDefault) {
        guard !macDefault.value.isEmpty else { return }
        let result = Linker.shell(macDefault.writeCommand)
        print("Apply defaults result: \(result)")
        if !macDefault.postCommand.isEmpty {
            let postResult = Linker.shell(macDefault.postCommand)
            print("Post command result: \(postResult)")
        }
    }

    @MainActor
    static func captureAll(_ items: [MacDefault]) {
        for item in items { capture(macDefault: item) }
    }

    @MainActor
    static func applyAll(_ items: [MacDefault]) {
        for item in items { apply(macDefault: item) }
    }
}
