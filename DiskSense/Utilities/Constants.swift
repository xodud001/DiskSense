import Foundation

enum ProtectedPaths {
    static let never: Set<String> = [
        "/System",
        "/Library",
        "/usr",
        "~/Library/Preferences",
        "~/Library/Keychains",
        "~/Library/Application Support/com.apple.TCC",
        "~/.ssh",
        "~/.gnupg",
    ]

    static func isProtected(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return never.contains { rule in
            let expandedRule = (rule as NSString).expandingTildeInPath
            return expanded == expandedRule || expanded.hasPrefix(expandedRule + "/")
        }
    }
}

enum AppInfo {
    static let bundleID = "com.yourname.DiskSense"
    static let minMacOS = "14.0"
}
