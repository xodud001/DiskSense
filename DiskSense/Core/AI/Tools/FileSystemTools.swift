import Foundation

// MARK: - list_directory

struct ListDirectoryTool: AgentTool {
    let name = "list_directory"
    let description = "지정된 경로의 직계 자식 항목(파일+폴더)을 용량 순으로 반환합니다. 파일 내용은 반환하지 않고 이름/크기/수정일/폴더 여부만 제공합니다."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "절대경로 또는 ~ 포함 경로"],
                "limit": ["type": "integer", "description": "최대 반환 항목 수 (기본 50)"]
            ],
            "required": ["path"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let pathIn = input["path"] as? String else { throw AgentToolError.invalidArgument("path 필요") }
        let limit = (input["limit"] as? Int) ?? 50
        let path = try PathGuard.validate(pathIn)
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { throw AgentToolError.notFound(path) }

        let keys: [URLResourceKey] = [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey, .contentModificationDateKey]
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) else {
            throw AgentToolError.accessDenied(path)
        }

        struct Entry: Codable {
            let name: String
            let path: String
            let size_bytes: Int64
            let mtime_iso: String
            let is_dir: Bool
        }

        let df = ISO8601DateFormatter()
        var entries: [Entry] = []
        for child in contents {
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let size: Int64
            if isDir {
                size = Int64(directorySizeFast(at: child.path, maxDepth: 3))
            } else {
                size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
            entries.append(Entry(
                name: child.lastPathComponent,
                path: child.path,
                size_bytes: size,
                mtime_iso: df.string(from: values?.contentModificationDate ?? .distantPast),
                is_dir: isDir
            ))
        }
        entries.sort { $0.size_bytes > $1.size_bytes }
        return [
            "path": path,
            "count": entries.count,
            "entries": Array(entries.prefix(limit)).map { [
                "name": $0.name, "path": $0.path,
                "size_bytes": $0.size_bytes, "mtime": $0.mtime_iso, "is_dir": $0.is_dir
            ] }
        ]
    }

    /// 깊이 제한 directory size (너무 느린 스캔 방지).
    private func directorySizeFast(at path: String, maxDepth: Int) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        func walk(_ p: String, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let entries = try? fm.contentsOfDirectory(atPath: p) else { return }
            for e in entries {
                let full = (p as NSString).appendingPathComponent(e)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir) {
                    if isDir.boolValue {
                        walk(full, depth: depth + 1)
                    } else {
                        let attrs = try? fm.attributesOfItem(atPath: full)
                        total += Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
                    }
                }
            }
        }
        walk(path, depth: 0)
        return total
    }
}

// MARK: - get_item_details

struct GetItemDetailsTool: AgentTool {
    let name = "get_item_details"
    let description = "파일 또는 폴더의 상세 메타데이터를 반환합니다 (크기, 수정일, 생성일, 접근일, 폴더 경우 하위 파일 수)."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["path": ["type": "string"]],
            "required": ["path"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let pathIn = input["path"] as? String else { throw AgentToolError.invalidArgument("path 필요") }
        let path = try PathGuard.validate(pathIn)
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey,
            .contentModificationDateKey, .creationDateKey, .contentAccessDateKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else {
            throw AgentToolError.notFound(path)
        }
        let isDir = v.isDirectory ?? false
        let df = ISO8601DateFormatter()
        var result: [String: Any] = [
            "path": path,
            "is_dir": isDir,
            "mtime": df.string(from: v.contentModificationDate ?? .distantPast),
            "ctime": df.string(from: v.creationDate ?? .distantPast),
            "atime": df.string(from: v.contentAccessDate ?? .distantPast),
        ]
        if isDir {
            let (totalSize, fileCount) = dirSizeAndCount(at: path, maxFiles: 5000)
            result["size_bytes"] = totalSize
            result["file_count"] = fileCount
        } else {
            result["size_bytes"] = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
        }
        return result
    }

    private func dirSizeAndCount(at path: String, maxFiles: Int) -> (Int64, Int) {
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return (0, 0) }
        var total: Int64 = 0
        var count = 0
        while let next = e.nextObject() {
            guard let u = next as? URL else { continue }
            let vs = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(vs?.totalFileAllocatedSize ?? vs?.fileSize ?? 0)
            count += 1
            if count >= maxFiles { break }
        }
        return (total, count)
    }
}

// MARK: - sample_file_names

struct SampleFileNamesTool: AgentTool {
    let name = "sample_file_names"
    let description = "폴더 하위의 랜덤 파일명 샘플을 반환합니다 (확장자별 분포 파악용). 파일 내용은 전송되지 않습니다."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string"],
                "count": ["type": "integer", "description": "기본 20, 최대 100"]
            ],
            "required": ["path"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let pathIn = input["path"] as? String else { throw AgentToolError.invalidArgument("path 필요") }
        let count = min((input["count"] as? Int) ?? 20, 100)
        let path = try PathGuard.validate(pathIn)
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { throw AgentToolError.accessDenied(path) }

        var names: [String] = []
        while let next = e.nextObject(), names.count < count * 5 {
            guard let u = next as? URL else { continue }
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                names.append(u.lastPathComponent)
            }
        }
        let sampled = names.shuffled().prefix(count)
        return ["path": path, "sample_count": sampled.count, "names": Array(sampled)]
    }
}

// MARK: - check_dev_project

struct CheckDevProjectTool: AgentTool {
    let name = "check_dev_project"
    let description = "경로가 개발 프로젝트인지 감지하고, 빌드 아티팩트/캐시 디렉토리 크기를 알려줍니다."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["path": ["type": "string"]],
            "required": ["path"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let pathIn = input["path"] as? String else { throw AgentToolError.invalidArgument("path 필요") }
        let path = try PathGuard.validate(pathIn)
        let fm = FileManager.default
        func exists(_ rel: String) -> Bool {
            fm.fileExists(atPath: (path as NSString).appendingPathComponent(rel))
        }
        func dirSize(_ rel: String) -> Int64 {
            let p = (path as NSString).appendingPathComponent(rel)
            guard fm.fileExists(atPath: p) else { return 0 }
            return dirSizeSync(p)
        }

        let hasGit = exists(".git")
        let hasPackageJson = exists("package.json")
        let hasCargoToml = exists("Cargo.toml")
        let hasGradle = exists("build.gradle") || exists("build.gradle.kts")
        let hasXcodeProj: Bool = {
            guard let files = try? fm.contentsOfDirectory(atPath: path) else { return false }
            return files.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
        }()
        let hasPodfile = exists("Podfile")
        let hasPyproject = exists("pyproject.toml") || exists("requirements.txt")

        let type: String
        switch true {
        case hasPackageJson: type = "node"
        case hasCargoToml:   type = "rust"
        case hasGradle:      type = "jvm"
        case hasXcodeProj:   type = "xcode"
        case hasPyproject:   type = "python"
        default:             type = "unknown"
        }

        return [
            "path": path,
            "is_dev_project": hasGit || hasPackageJson || hasCargoToml || hasGradle || hasXcodeProj,
            "type": type,
            "has_git": hasGit,
            "has_package_json": hasPackageJson,
            "has_cargo_toml": hasCargoToml,
            "has_gradle": hasGradle,
            "has_xcode_project": hasXcodeProj,
            "has_podfile": hasPodfile,
            "build_artifacts": [
                "node_modules_bytes": dirSize("node_modules"),
                "derived_data_bytes": dirSize("DerivedData"),
                "build_bytes": dirSize("build"),
                "dot_build_bytes": dirSize(".build"),
                "target_bytes": dirSize("target"),
                "pods_bytes": dirSize("Pods"),
                "gradle_cache_bytes": dirSize(".gradle"),
                "pycache_bytes": dirSize("__pycache__"),
            ]
        ]
    }

    private func dirSizeSync(_ path: String) -> Int64 {
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey], options: []
        ) else { return 0 }
        var total: Int64 = 0
        while let next = e.nextObject() {
            guard let u = next as? URL else { continue }
            let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}

// MARK: - get_last_opened

struct GetLastOpenedTool: AgentTool {
    let name = "get_last_opened"
    let description = "Spotlight의 kMDItemLastUsedDate를 조회해 파일/폴더를 마지막으로 연 날짜를 반환합니다 (없으면 null)."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["path": ["type": "string"]],
            "required": ["path"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let pathIn = input["path"] as? String else { throw AgentToolError.invalidArgument("path 필요") }
        let path = try PathGuard.validate(pathIn)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        task.arguments = ["-raw", "-name", "kMDItemLastUsedDate", path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "(null)" || trimmed.isEmpty {
            return ["path": path, "last_opened": NSNull()]
        }
        return ["path": path, "last_opened": trimmed]
    }
}

// MARK: - count_files_by_extension

struct CountFilesByExtensionTool: AgentTool {
    let name = "count_files_by_extension"
    let description = "폴더 하위 파일들을 확장자별로 카운트합니다. 콘텐츠 종류 파악용."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": ["type": "string"],
                "top": ["type": "integer", "description": "상위 N개만 반환 (기본 15)"]
            ],
            "required": ["path"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let pathIn = input["path"] as? String else { throw AgentToolError.invalidArgument("path 필요") }
        let top = (input["top"] as? Int) ?? 15
        let path = try PathGuard.validate(pathIn)
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { throw AgentToolError.accessDenied(path) }

        var counts: [String: Int] = [:]
        var totalFiles = 0
        while let next = e.nextObject() {
            guard let u = next as? URL else { continue }
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                let ext = u.pathExtension.lowercased()
                let key = ext.isEmpty ? "(no ext)" : ext
                counts[key, default: 0] += 1
                totalFiles += 1
                if totalFiles > 50000 { break }
            }
        }
        let sorted = counts.sorted { $0.value > $1.value }.prefix(top)
        return [
            "path": path,
            "total_files": totalFiles,
            "top_extensions": sorted.map { ["ext": $0.key, "count": $0.value] }
        ]
    }
}

// MARK: - search_by_pattern

struct SearchByPatternTool: AgentTool {
    let name = "search_by_pattern"
    let description = "홈 하위에서 glob/정규식 패턴으로 파일 경로를 검색합니다 (최대 100개)."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "root": ["type": "string"],
                "name_pattern": ["type": "string", "description": "파일/폴더 이름에 포함될 substring (case-insensitive)"],
                "limit": ["type": "integer"]
            ],
            "required": ["root", "name_pattern"]
        ]
    }

    func execute(input: [String: Any], context: AgentContext) async throws -> Any {
        guard let rootIn = input["root"] as? String,
              let pattern = input["name_pattern"] as? String
        else { throw AgentToolError.invalidArgument("root, name_pattern 필요") }
        let limit = min((input["limit"] as? Int) ?? 100, 500)
        let root = try PathGuard.validate(rootIn)
        let needle = pattern.lowercased()

        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
            options: []
        ) else { throw AgentToolError.accessDenied(root) }

        var hits: [[String: Any]] = []
        while let next = e.nextObject(), hits.count < limit {
            guard let u = next as? URL else { continue }
            if u.lastPathComponent.lowercased().contains(needle) {
                let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey])
                hits.append([
                    "path": u.path,
                    "size_bytes": Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0),
                    "is_dir": v?.isDirectory ?? false
                ])
            }
        }
        return ["root": root, "pattern": pattern, "count": hits.count, "hits": hits]
    }
}
