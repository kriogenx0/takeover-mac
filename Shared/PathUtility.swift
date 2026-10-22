import Darwin
import Foundation

struct PathUtility {
    static func expandTildeToRealHome(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return path.replacingOccurrences(of: "~", with: getRealHomeDirectory(), options: .anchored)
    }

    /// The inverse of `expandTildeToRealHome`: `/Users/me/x` -> `~/x`.
    static func abbreviateRealHome(_ path: String) -> String {
        let home = getRealHomeDirectory()
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func getRealHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return "/Users/\(ProcessInfo.processInfo.userName)"
    }
}
