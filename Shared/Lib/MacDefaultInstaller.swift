import Foundation

struct MacDefaultInstaller {

    @MainActor
    private static func readSystemValue(macDefault: MacDefault) -> String {
        let result = Proc.run("/usr/bin/defaults", macDefault.readArguments)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let notFound = !result.ok
            || output.isEmpty
            || output.contains("does not exist")
            || output.contains("The domain/defaults pair")
        return notFound ? "" : output
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
        guard let args = macDefault.writeArguments else { return }

        let write = Proc.run("/usr/bin/defaults", args)
        if write.ok {
            print("Applied \(macDefault.domain) \(macDefault.key) = \(macDefault.value)")
        } else {
            print("⚠️ Failed to write \(macDefault.domain) \(macDefault.key): \(write.combined)")
            return
        }

        if !macDefault.postCommand.isEmpty {
            let post = Shell.runTrusted(macDefault.postCommand)
            if !post.ok {
                print("⚠️ Post-command '\(macDefault.postCommand)' failed: \(post.text)")
            }
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
