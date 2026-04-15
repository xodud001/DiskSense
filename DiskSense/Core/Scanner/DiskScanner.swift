import Foundation
import Darwin

enum ScanError: Error {
    case accessDenied
    case cancelled
}

struct ScanProgress: Sendable {
    var itemsScanned: Int
    var bytesScanned: Int64
    var currentPath: String
    var partialItems: [DiskItem]
    var partialBreakdown: [StorageCategory: Int64]
    var totalUsed: Int64
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _v = false
    func cancel() { lock.lock(); _v = true; lock.unlock() }
    func reset()  { lock.lock(); _v = false; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _v }
}

/// top-level 자식 디렉토리별로 `BulkScanner` 워커를 병렬 실행.
/// 단일 스레드 `FileManager.enumerator` 대비 10배+ 목표.
actor DiskScanner {
    let cancellation = CancellationFlag()
    nonisolated func cancel() { cancellation.cancel() }

    func scan(
        rootPath: String,
        minItemBytes: Int64 = 1_000_000,
        progress: @Sendable @escaping (ScanProgress) -> Void
    ) async throws -> ScanResult {
        cancellation.reset()
        let expandedRoot = (rootPath as NSString).expandingTildeInPath
        let fm = FileManager.default

        // top-level 자식 목록 (병렬 작업 단위).
        guard let children = try? fm.contentsOfDirectory(atPath: expandedRoot) else {
            throw ScanError.accessDenied
        }
        let topChildren: [String] = children
            .filter { !$0.hasPrefix(".") || $0 == ".Trash" }
            .map { expandedRoot + "/" + $0 }

        let aggregator = ScanAggregator(
            rootPath: expandedRoot,
            minItemBytes: minItemBytes,
            progress: progress
        )
        let flag = cancellation

        await withTaskGroup(of: Void.self) { group in
            for child in topChildren {
                group.addTask(priority: .userInitiated) { [flag] in
                    await Self.scanChild(path: child, flag: flag, aggregator: aggregator)
                }
            }
            await group.waitForAll()
        }

        if cancellation.isCancelled { throw ScanError.cancelled }

        let (items, breakdown, totalUsed, processed) = await aggregator.finalize()
        progress(ScanProgress(
            itemsScanned: processed,
            bytesScanned: totalUsed,
            currentPath: "완료",
            partialItems: items,
            partialBreakdown: breakdown,
            totalUsed: totalUsed
        ))

        return ScanResult(
            scannedAt: .now,
            totalCapacity: Int64(VolumeInfo.usage(for: URL(fileURLWithPath: expandedRoot))?.total ?? 0),
            totalUsed: totalUsed,
            items: items,
            breakdown: breakdown
        )
    }

    private static func scanChild(
        path: String,
        flag: CancellationFlag,
        aggregator: ScanAggregator
    ) async {
        // 디렉토리가 아니면 단일 파일만 반영.
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        if !isDir {
            let size = Int64(st.st_size)
            let mod = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            await aggregator.ingestSingleFile(childPath: path, size: size, modified: mod)
            return
        }

        // 워커 로컬 누적 (actor hop 최소화).
        var localSize: Int64 = 0
        var localCount = 0
        var localBreakdown: [StorageCategory: Int64] = [:]
        var localCatBytes: [StorageCategory: Int64] = [:]
        var localLastModified = Date.distantPast
        let childPath = path

        BulkScanner.walk(
            root: path,
            shouldContinue: { !flag.isCancelled }
        ) { entry in
            localCount += 1
            if !entry.isDir {
                let category = CategoryClassifier.classify(path: entry.path)
                localSize += entry.size
                localBreakdown[category, default: 0] += entry.size
                localCatBytes[category, default: 0] += entry.size
                if entry.modified > localLastModified { localLastModified = entry.modified }
            }
            // 250ms throttle는 aggregator 쪽에서.
            if localCount % 2000 == 0 {
                let snapshotSize = localSize
                let snapshotCount = localCount
                let snapshotBreakdown = localBreakdown
                Task { await aggregator.reportPartial(
                    childPath: childPath,
                    bytes: snapshotSize,
                    count: snapshotCount,
                    breakdown: snapshotBreakdown,
                    currentPath: entry.path
                )}
            }
        }

        await aggregator.completeChild(
            childPath: childPath,
            size: localSize,
            count: localCount,
            breakdown: localBreakdown,
            catBytes: localCatBytes,
            modified: localLastModified
        )
    }
}

/// 여러 워커의 중간/최종 결과를 병합하고 progress 콜백을 throttle.
actor ScanAggregator {
    private let rootPath: String
    private let minItemBytes: Int64
    private let progress: @Sendable (ScanProgress) -> Void

    private var childSize: [String: Int64] = [:]
    private var childCount: [String: Int] = [:]
    private var childBreakdown: [String: [StorageCategory: Int64]] = [:]
    private var childCatBytes: [String: [StorageCategory: Int64]] = [:]
    private var childModified: [String: Date] = [:]

    private var totalBreakdown: [StorageCategory: Int64] = [:]
    private var totalUsed: Int64 = 0
    private var totalCount: Int = 0

    private var lastEmit = Date.distantPast
    private let emitInterval: TimeInterval = 0.5

    init(
        rootPath: String,
        minItemBytes: Int64,
        progress: @Sendable @escaping (ScanProgress) -> Void
    ) {
        self.rootPath = rootPath
        self.minItemBytes = minItemBytes
        self.progress = progress
    }

    func ingestSingleFile(childPath: String, size: Int64, modified: Date) {
        let category = CategoryClassifier.classify(path: childPath)
        childSize[childPath] = size
        childCount[childPath] = 1
        childBreakdown[childPath] = [category: size]
        childCatBytes[childPath] = [category: size]
        childModified[childPath] = modified
        totalBreakdown[category, default: 0] += size
        totalUsed += size
        totalCount += 1
    }

    func reportPartial(
        childPath: String,
        bytes: Int64,
        count: Int,
        breakdown: [StorageCategory: Int64],
        currentPath: String
    ) {
        // delta 계산.
        let prevBytes = childSize[childPath] ?? 0
        let prevCount = childCount[childPath] ?? 0
        let prevBD = childBreakdown[childPath] ?? [:]

        childSize[childPath] = bytes
        childCount[childPath] = count
        childBreakdown[childPath] = breakdown

        totalUsed += (bytes - prevBytes)
        totalCount += (count - prevCount)
        for (k, v) in breakdown {
            totalBreakdown[k, default: 0] += v - (prevBD[k] ?? 0)
        }
        for (k, v) in prevBD where breakdown[k] == nil {
            totalBreakdown[k, default: 0] -= v
        }

        maybeEmit(currentPath: currentPath)
    }

    func completeChild(
        childPath: String,
        size: Int64,
        count: Int,
        breakdown: [StorageCategory: Int64],
        catBytes: [StorageCategory: Int64],
        modified: Date
    ) {
        let prevBytes = childSize[childPath] ?? 0
        let prevCount = childCount[childPath] ?? 0
        let prevBD = childBreakdown[childPath] ?? [:]

        childSize[childPath] = size
        childCount[childPath] = count
        childBreakdown[childPath] = breakdown
        childCatBytes[childPath] = catBytes
        childModified[childPath] = modified

        totalUsed += (size - prevBytes)
        totalCount += (count - prevCount)
        for (k, v) in breakdown {
            totalBreakdown[k, default: 0] += v - (prevBD[k] ?? 0)
        }
        for (k, v) in prevBD where breakdown[k] == nil {
            totalBreakdown[k, default: 0] -= v
        }
        maybeEmit(currentPath: childPath)
    }

    func finalize() -> ([DiskItem], [StorageCategory: Int64], Int64, Int) {
        (makeItems(), totalBreakdown, totalUsed, totalCount)
    }

    private func maybeEmit(currentPath: String) {
        let now = Date()
        if now.timeIntervalSince(lastEmit) < emitInterval { return }
        lastEmit = now
        progress(ScanProgress(
            itemsScanned: totalCount,
            bytesScanned: totalUsed,
            currentPath: currentPath,
            partialItems: makeItems(),
            partialBreakdown: totalBreakdown,
            totalUsed: totalUsed
        ))
    }

    private func makeItems() -> [DiskItem] {
        childSize.compactMap { (path, size) -> DiskItem? in
            guard size >= minItemBytes else { return nil }
            let catMap = childCatBytes[path] ?? childBreakdown[path] ?? [:]
            let dominant = catMap.max(by: { $0.value < $1.value })?.key
                ?? CategoryClassifier.classify(path: path)
            let name: String = {
                if let slash = path.lastIndex(of: "/") {
                    return String(path[path.index(after: slash)...])
                }
                return path
            }()
            var st = stat()
            let isDir = (lstat(path, &st) == 0) && ((st.st_mode & S_IFMT) == S_IFDIR)
            return DiskItem(
                path: path,
                name: name,
                sizeBytes: size,
                modifiedDate: childModified[path] ?? .now,
                isDirectory: isDir,
                category: dominant
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
