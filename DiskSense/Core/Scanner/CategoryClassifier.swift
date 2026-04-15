import Foundation

enum CategoryClassifier {
    static func classify(_ url: URL) -> StorageCategory {
        classify(path: url.path)
    }

    /// 경로 문자열만으로 분류 (URL 할당 회피용 hot path).
    static func classify(path: String) -> StorageCategory {
        let name: String = {
            if let slash = path.lastIndex(of: "/") {
                return String(path[path.index(after: slash)...])
            }
            return path
        }()
        let ext: String = {
            if let dot = name.lastIndex(of: ".") {
                return name[name.index(after: dot)...].lowercased()
            }
            return ""
        }()

        if pathContains(path, any: devToolPathMarkers) { return .developer }
        if ext == "app" || path.hasPrefix("/Applications") { return .apps }
        if path.hasPrefix("/System") || path.hasPrefix("/Library") || path.hasPrefix("/usr") { return .system }
        if pathContains(path, any: cachePathMarkers) { return .cache }
        if pathContains(path, any: mailPathMarkers) { return .mail }
        if name == ".Trash" || path.contains("/.Trash") { return .trash }
        if photoExts.contains(ext) { return .photos }
        if documentExts.contains(ext) { return .documents }
        return .other
    }

    private static let devToolPathMarkers: [String] = [
        "/node_modules", "/DerivedData", "/.build", "/build",
        "/Pods", "/.gradle", "/target/debug", "/target/release",
        "/vendor/bundle", "/__pycache__", "/.venv", "/venv",
        "/Library/Developer/Xcode", "/Library/Caches/CocoaPods",
        "/Library/Application Support/Docker", "/homebrew/Cellar",
        "/opt/homebrew/Cellar",
    ]

    private static let cachePathMarkers: [String] = [
        "/Library/Caches/", "/Caches/", "/.cache/",
    ]

    private static let mailPathMarkers: [String] = [
        "/Library/Mail/", "/Mail Downloads/",
    ]

    private static let photoExts: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "raw", "cr2", "nef",
        "tiff", "bmp", "webp", "mov", "mp4", "m4v", "avi", "mkv",
    ]

    private static let documentExts: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages",
        "numbers", "key", "txt", "md", "rtf", "csv", "json", "xml",
    ]

    private static func pathContains(_ path: String, any markers: [String]) -> Bool {
        markers.contains { path.contains($0) }
    }
}
