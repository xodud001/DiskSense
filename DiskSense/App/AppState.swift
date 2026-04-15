import Foundation
import Observation
import CoreServices

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard, analysis, history, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "대시보드"
        case .analysis:  return "AI 분석"
        case .history:   return "히스토리"
        case .settings:  return "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .analysis:  return "sparkles"
        case .history:   return "clock.arrow.circlepath"
        case .settings:  return "gearshape.fill"
        }
    }
}

@Observable
@MainActor
final class AppState {
    var scanResult: ScanResult?
    var suggestions: [AISuggestion] = []
    var isScanning = false
    var isAnalyzing = false
    var liveItems: [DiskItem] = []
    var liveBreakdown: [StorageCategory: Int64] = [:]
    var liveBytesScanned: Int64 = 0
    var liveItemsScanned: Int = 0
    var liveCurrentPath: String = ""
    var lastScanDuration: TimeInterval?
    var liveElapsed: TimeInterval = 0
    var devToolHits: [DevToolHit] = []
    var hasFullDiskAccess: Bool = PermissionChecker.hasFullDiskAccess()
    var volumeUsage: VolumeInfo.Usage? = VolumeInfo.startupVolume()
    var selectedTab: SidebarTab = .dashboard
    var pendingIncrementalPaths: Set<String> = []

    private let scanner = DiskScanner()
    private var rescanTimer: Timer?
    private var fsWatcher: FSEventsWatcher?
    private var debouncedRescanTask: Task<Void, Never>?

    @MainActor
    func bootstrap() {
        if let cached = ScanCache.load() {
            self.scanResult = cached
        }
        let ttl = SettingsStore.autoRescanHours
        if ScanCache.isStale(ttlHours: ttl) {
            Task { await self.startScan() }
        }
        scheduleBackgroundRescan()
        startFSEventsIfPossible()
    }

    @MainActor
    private func scheduleBackgroundRescan() {
        rescanTimer?.invalidate()
        let interval = max(3600, SettingsStore.autoRescanHours * 3600)
        rescanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isScanning else { return }
                await self.startScan()
            }
        }
    }

    /// Phase B: FSEvents로 변경 감지 → 디바운스된 증분 재스캔 트리거.
    @MainActor
    private func startFSEventsIfPossible() {
        fsWatcher?.stop()
        let home = NSHomeDirectory()
        let watcher = FSEventsWatcher { [weak self] paths in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingIncrementalPaths.formUnion(paths)
                self.debounceIncrementalRescan()
            }
        }
        watcher.start(paths: [home])
        fsWatcher = watcher
    }

    /// 변경 이벤트 후 2분 디바운스하여 한 번에 재스캔.
    @MainActor
    private func debounceIncrementalRescan() {
        debouncedRescanTask?.cancel()
        debouncedRescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000) // 2분
            guard !Task.isCancelled, let self, !self.isScanning else { return }
            await self.startScan()
            self.pendingIncrementalPaths.removeAll()
        }
    }

    @MainActor
    func cancelScan() {
        scanner.cancel()
    }

    @MainActor
    func startScan(rootPath: String? = nil) async {
        guard !isScanning else { return }
        let path = rootPath ?? NSHomeDirectory()
        isScanning = true
        liveItems = []
        liveBreakdown = [:]
        liveBytesScanned = 0
        liveItemsScanned = 0
        liveCurrentPath = "시작 중..."
        liveElapsed = 0
        let startedAt = Date()
        let tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.liveElapsed = Date().timeIntervalSince(startedAt)
            }
        }
        defer {
            isScanning = false
            tickTimer.invalidate()
        }

        do {
            let result = try await scanner.scan(rootPath: path) { [weak self] snap in
                Task { @MainActor in
                    guard let self else { return }
                    self.liveItems = snap.partialItems
                    self.liveBreakdown = snap.partialBreakdown
                    self.liveBytesScanned = snap.bytesScanned
                    self.liveItemsScanned = snap.itemsScanned
                    self.liveCurrentPath = snap.currentPath
                }
            }
            let homeScanElapsed = Date().timeIntervalSince(startedAt)
            print(String(format: "[DiskScanner] home scan finished in %.2fs (%d items, %.2f GB)",
                         homeScanElapsed,
                         result.items.count,
                         Double(result.totalUsed) / 1_073_741_824))
            self.volumeUsage = VolumeInfo.startupVolume()
            self.liveCurrentPath = "시스템 카테고리 분석 중..."
            let volumeUsed = self.volumeUsage?.used ?? result.totalUsed
            let systemResult = await SystemScanner.scan(
                volumeUsed: volumeUsed,
                homeScannedBytes: result.totalUsed
            )
            var merged = result
            merged.items.append(contentsOf: systemResult.items)
            merged.items.sort { $0.sizeBytes > $1.sizeBytes }
            for (cat, bytes) in systemResult.breakdown {
                merged.breakdown[cat, default: 0] += bytes
            }
            self.scanResult = merged
            let totalElapsed = Date().timeIntervalSince(startedAt)
            self.lastScanDuration = totalElapsed
            self.liveElapsed = totalElapsed
            print(String(format: "[DiskScanner] full scan (incl. system) %.2fs", totalElapsed))
            ScanCache.save(merged)
        } catch ScanError.cancelled {
            self.liveCurrentPath = "취소됨"
        } catch {
            self.liveCurrentPath = "실패: \(error)"
        }
    }

    @MainActor
    func scanDevTools(rootPath: String? = nil) async {
        let path = rootPath ?? NSHomeDirectory()
        devToolHits = await DevToolScanner.scan(rootPath: path)
    }
}
