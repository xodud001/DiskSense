import Foundation
import AppKit

enum PermissionChecker {
    /// Full Disk Access 권한 상태를 TCC 보호 경로 읽기 시도로 추정한다.
    /// 샌드박스 환경이 아닐 때만 의미 있음.
    static func hasFullDiskAccess() -> Bool {
        let probePaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Safari/Bookmarks.plist"),
        ]
        let fm = FileManager.default
        for path in probePaths where fm.fileExists(atPath: path) {
            if fm.isReadableFile(atPath: path) { return true }
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
