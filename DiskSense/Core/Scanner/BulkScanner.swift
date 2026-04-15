import Foundation
import Darwin

/// `getattrlistbulk(2)` 기반 고속 디렉토리 순회 엔진.
/// 한 syscall 당 수십~수백 엔트리의 size/mtime/objtype 을 한꺼번에 가져온다.
/// `FileManager.enumerator` 대비 단독으로 5~10배.
enum BulkScanner {
    struct Entry {
        var path: String          // 절대 경로
        var size: Int64           // allocated size (file) or 0 (dir)
        var isDir: Bool
        var modified: Date
    }

    /// 단일 디렉토리를 재귀 순회. 각 엔트리에 대해 `handle` 호출.
    /// `shouldContinue` 가 false 면 즉시 중단.
    static func walk(
        root: String,
        shouldContinue: () -> Bool,
        handle: (Entry) -> Void
    ) {
        var stack: [String] = [root]
        while let dir = stack.popLast() {
            if !shouldContinue() { return }
            walkOne(dir: dir, stack: &stack, shouldContinue: shouldContinue, handle: handle)
        }
    }

    private struct AttrList {
        var bitmapCount: UInt16 = UInt16(ATTR_BIT_MAP_COUNT)
        var reserved: UInt16 = 0
        var commonattr: attrgroup_t = 0
        var volattr: attrgroup_t = 0
        var dirattr: attrgroup_t = 0
        var fileattr: attrgroup_t = 0
        var forkattr: attrgroup_t = 0
    }

    private static func walkOne(
        dir: String,
        stack: inout [String],
        shouldContinue: () -> Bool,
        handle: (Entry) -> Void
    ) {
        let fd = open(dir, O_RDONLY | O_DIRECTORY, 0)
        if fd < 0 { return }
        defer { close(fd) }

        var attrList = AttrList()
        attrList.commonattr =
            UInt32(ATTR_CMN_RETURNED_ATTRS) |
            UInt32(ATTR_CMN_NAME) |
            UInt32(ATTR_CMN_OBJTYPE) |
            UInt32(ATTR_CMN_MODTIME)
        attrList.fileattr = UInt32(ATTR_FILE_ALLOCSIZE)

        let bufSize = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buffer.deallocate() }

        while shouldContinue() {
            let count: Int32 = withUnsafeMutablePointer(to: &attrList) { listPtr -> Int32 in
                getattrlistbulk(fd, listPtr, buffer, bufSize, 0)
            }
            if count <= 0 { break }

            var cursor = buffer
            for _ in 0..<count {
                let entryStart = cursor
                let entryLen = cursor.loadUnaligned(as: UInt32.self)
                cursor = cursor.advanced(by: MemoryLayout<UInt32>.size)

                let returned = cursor.loadUnaligned(as: attribute_set_t.self)
                cursor = cursor.advanced(by: MemoryLayout<attribute_set_t>.size)

                var name: String = ""
                var objType: fsobj_type_t = 0
                var modTime = timespec()
                var allocSize: off_t = 0

                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = cursor.loadUnaligned(as: attrreference_t.self)
                    let namePtr = cursor.advanced(by: Int(ref.attr_dataoffset))
                        .assumingMemoryBound(to: CChar.self)
                    name = String(cString: namePtr)
                    cursor = cursor.advanced(by: MemoryLayout<attrreference_t>.size)
                }
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    objType = cursor.loadUnaligned(as: fsobj_type_t.self)
                    cursor = cursor.advanced(by: MemoryLayout<fsobj_type_t>.size)
                }
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    modTime = cursor.loadUnaligned(as: timespec.self)
                    cursor = cursor.advanced(by: MemoryLayout<timespec>.size)
                }
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocSize = cursor.loadUnaligned(as: off_t.self)
                    cursor = cursor.advanced(by: MemoryLayout<off_t>.size)
                }

                // 다음 엔트리로 점프
                cursor = entryStart.advanced(by: Int(entryLen))

                if name.isEmpty || name == "." || name == ".." { continue }
                let isDir = (objType == fsobj_type_t(VDIR.rawValue))
                let isReg = (objType == fsobj_type_t(VREG.rawValue))
                if !isDir && !isReg { continue }  // 심볼릭/디바이스 스킵

                let fullPath = dir.hasSuffix("/") ? (dir + name) : (dir + "/" + name)

                // .Trashes, .Spotlight-V100 등 시스템 메타 디렉터리는 스킵
                if isDir && shouldSkipDir(name: name) {
                    handle(Entry(
                        path: fullPath, size: 0, isDir: true,
                        modified: Date(timeIntervalSince1970: TimeInterval(modTime.tv_sec))
                    ))
                    continue
                }

                let entry = Entry(
                    path: fullPath,
                    size: isReg ? Int64(allocSize) : 0,
                    isDir: isDir,
                    modified: Date(timeIntervalSince1970: TimeInterval(modTime.tv_sec))
                )
                handle(entry)

                if isDir {
                    stack.append(fullPath)
                }
            }
        }
    }

    private static let skipDirs: Set<String> = [
        ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        ".TemporaryItems", ".MobileBackups", ".vol",
    ]
    private static func shouldSkipDir(name: String) -> Bool {
        skipDirs.contains(name)
    }
}
