import Foundation

/// Apple의 "저장공간" 뷰처럼 시스템 레벨 카테고리를 계산한다.
/// - 응용 프로그램 (/Applications)
/// - macOS (read-only 시스템 볼륨)
/// - 다른 사용자 (/Users/* 제외 현재 유저)
/// - APFS 스냅샷 (tmutil 추정)
/// - 시스템 데이터 (나머지 = volumeUsed - 합산)
/// - 휴지통 (~/.Trash)
enum SystemScanner {
    struct Result {
        var items: [DiskItem]
        var breakdown: [StorageCategory: Int64]
    }

    static func scan(volumeUsed: Int64, homeScannedBytes: Int64) async -> Result {
        async let appsBytes = directorySize("/Applications")
        async let systemOSBytes = systemVolumeUsed()
        async let otherUsersBytes = otherUsersSize()

        let apps = await appsBytes
        let mac = await systemOSBytes
        let others = await otherUsersBytes
        let hasSnapshots = snapshotsPresent()

        var breakdown: [StorageCategory: Int64] = [:]
        var items: [DiskItem] = []

        func add(_ cat: StorageCategory, path: String, bytes: Int64) {
            guard bytes > 0 else { return }
            breakdown[cat, default: 0] += bytes
            items.append(DiskItem(
                path: path,
                name: cat.displayName,
                sizeBytes: bytes,
                modifiedDate: .now,
                isDirectory: true,
                category: cat
            ))
        }

        add(.apps, path: "/Applications", bytes: apps)
        add(.macOS, path: "/System", bytes: mac)
        add(.otherUsers, path: "/Users (다른 사용자)", bytes: others)

        // 나머지 = systemData + snapshots (APFS 스냅샷 정확 사이즈는 sudo 필요)
        let accountedFor = homeScannedBytes + apps + mac + others
        let remainder = max(0, volumeUsed - accountedFor)
        if remainder > 0 {
            if hasSnapshots {
                // 스냅샷이 있으면 보수적으로 절반을 스냅샷으로, 절반을 systemData로 추정
                let half = remainder / 2
                add(.snapshots, path: "APFS 로컬 스냅샷 (Time Machine)", bytes: half)
                add(.systemData, path: "시스템 데이터 (로그/캐시/스왑)", bytes: remainder - half)
            } else {
                add(.systemData, path: "시스템 데이터 (로그/캐시/스왑)", bytes: remainder)
            }
        }

        return Result(items: items, breakdown: breakdown)
    }

    private static func snapshotsPresent() -> Bool {
        guard let output = runShell("/usr/bin/tmutil", args: ["listlocalsnapshots", "/"]) else { return false }
        return output.contains("com.apple.TimeMachine")
    }

    // MARK: - Helpers

    private static func directorySize(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        // 중요: .skipsPackageDescendants 없음 — .app 번들 내부까지 포함해야 실제 용량 집계됨
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: []
        ) else { return 0 }
        var total: Int64 = 0
        while let next = e.nextObject() {
            guard let u = next as? URL,
                  let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }

    /// 읽기 전용 시스템 볼륨 사용량. `df -k /`로 kilobyte 단위 used 추출.
    private static func systemVolumeUsed() -> Int64 {
        runShell("/bin/df", args: ["-k", "/"])
            .map { parseDfUsedKb($0) * 1024 } ?? 0
    }

    private static func otherUsersSize() -> Int64 {
        let current = NSUserName()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/Users") else { return 0 }
        var total: Int64 = 0
        for entry in entries {
            if entry == current { continue }
            if entry == "Shared" || entry.hasPrefix(".") { continue }
            total += directorySize("/Users/\(entry)")
        }
        return total
    }

    private static func parseDfUsedKb(_ output: String) -> Int64 {
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { return 0 }
        let parts = lines[1].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3, let used = Int64(parts[2]) else { return 0 }
        return used
    }

    private static func runShell(_ path: String, args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
