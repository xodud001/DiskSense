import Foundation

struct DevToolHit: Identifiable, Hashable {
    let id = UUID()
    let kind: Kind
    let path: String
    let sizeBytes: Int64
    let modifiedDate: Date

    enum Kind: String, CaseIterable {
        case nodeModules = "node_modules"
        case xcodeDerivedData = "DerivedData"
        case swiftBuild = ".build / build"
        case cocoapods = "Pods"
        case gradle = ".gradle"
        case rustTarget = "target/"
        case rubyVendor = "vendor/bundle"
        case pythonVenv = "venv / .venv / __pycache__"
        case brewCache = "brew cache"
        case dockerData = "Docker data"
    }
}

enum DevToolScanner {
    /// 확정된 개발 캐시 루트 + 재귀로 찾아낼 패턴들.
    static func scan(rootPath: String) async -> [DevToolHit] {
        let root = (rootPath as NSString).expandingTildeInPath
        var hits: [DevToolHit] = []

        let knownRoots: [(DevToolHit.Kind, String)] = [
            (.xcodeDerivedData, "~/Library/Developer/Xcode/DerivedData"),
            (.cocoapods, "~/Library/Caches/CocoaPods"),
            (.brewCache, "~/Library/Caches/Homebrew"),
            (.dockerData, "~/Library/Containers/com.docker.docker/Data/vms"),
        ]
        for (kind, p) in knownRoots {
            let expanded = (p as NSString).expandingTildeInPath
            if let hit = makeHit(kind: kind, path: expanded) { hits.append(hit) }
        }

        let patterns: [(DevToolHit.Kind, String)] = [
            (.nodeModules, "node_modules"),
            (.swiftBuild, ".build"),
            (.swiftBuild, "build"),
            (.gradle, ".gradle"),
            (.rustTarget, "target"),
            (.rubyVendor, "vendor"),
            (.pythonVenv, "venv"),
            (.pythonVenv, ".venv"),
            (.pythonVenv, "__pycache__"),
        ]

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return hits }

        while let next = enumerator.nextObject() {
            guard let url = next as? URL else { continue }
            let name = url.lastPathComponent
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            if let match = patterns.first(where: { $0.1 == name }) {
                enumerator.skipDescendants()
                if let hit = makeHit(kind: match.0, path: url.path) {
                    hits.append(hit)
                }
            }
        }

        return hits.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func makeHit(kind: DevToolHit.Kind, path: String) -> DevToolHit? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let size = directorySize(path: path)
        let modified = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        return DevToolHit(kind: kind, path: path, sizeBytes: size, modifiedDate: modified)
    }

    private static func directorySize(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in enumerator {
            let v = try? f.resourceValues(forKeys: Set(keys))
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}
