import Darwin
import Foundation

struct PathUtility {
    static func expandTildeToRealHome(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return path.replacingOccurrences(of: "~", with: getRealHomeDirectory(), options: .anchored)
    }

    static func getRealHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return "/Users/\(ProcessInfo.processInfo.userName)"
    }
}
