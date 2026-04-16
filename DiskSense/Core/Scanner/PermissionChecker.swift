import Foundation
import AppKit

enum PermissionChecker {
    /// Full Disk Access 권한 상태를 TCC 보호 경로 읽기 시도로 추정한다.
    /// 여러 TCC 보호 경로를 프로빙하여 하나라도 읽기 가능하면 FDA 활성으로 판단.
    static func hasFullDiskAccess() -> Bool {
        let home = NSHomeDirectory() as NSString
        let probePaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages"),
            home.appendingPathComponent("Library/Cookies"),
            home.appendingPathComponent("Library/HomeKit"),
        ]
        let fm = FileManager.default
        for path in probePaths {
            // 디렉토리인 경우 내용 열거 가능 여부로 판단
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if (try? fm.contentsOfDirectory(atPath: path)) != nil { return true }
                } else {
                    if fm.isReadableFile(atPath: path) { return true }
                }
            }
        }
        return false
    }

    static func openFullDiskAccessPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// NSOpenPanel로 유저가 루트를 선택하도록 요청. 선택된 URL은 security-scoped bookmark 대체 경로.
    @MainActor
    static func promptForDirectory(message: String = "스캔할 폴더를 선택하세요 (홈 디렉토리 권장)") -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url : nil
    }
}
