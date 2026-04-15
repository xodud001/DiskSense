import Foundation
import CoreServices

/// FSEvents 기반 디렉토리 변경 감지. Phase B 증분 스캔용.
/// 마지막 스캔 이후 변경된 디렉토리 목록을 비동기로 콜백한다.
final class FSEventsWatcher {
    typealias ChangeHandler = @Sendable ([String]) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.yourname.DiskSense.fsevents")
    private let handler: ChangeHandler

    init(handler: @escaping ChangeHandler) {
        self.handler = handler
    }

    deinit { stop() }

    func start(paths: [String], since eventId: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency: CFTimeInterval = 2.0) {
        stop()

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(version: 0, info: selfPtr, retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, numEvents, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes: paths is CFArray of CFString
            let cfArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue()
            var list: [String] = []
            for i in 0..<numEvents {
                let idx = CFIndex(i)
                if let cfStr = CFArrayGetValueAtIndex(cfArray, idx) {
                    let str = Unmanaged<CFString>.fromOpaque(cfStr).takeUnretainedValue()
                    list.append(str as String)
                }
            }
            me.handler(list)
        }

        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray, eventId, latency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}
