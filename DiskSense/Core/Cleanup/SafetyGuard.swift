import Foundation

enum SafetyViolation: Error, LocalizedError {
    case protectedPath(String)
    case notExists(String)
    case outsideHome(String)

    var errorDescription: String? {
        switch self {
        case .protectedPath(let p): return "보호된 경로입니다: \(p)"
        case .notExists(let p):     return "존재하지 않는 경로: \(p)"
        case .outsideHome(let p):   return "홈 디렉토리 밖의 경로: \(p)"
        }
    }
}

enum SafetyGuard {
    /// 경로가 삭제 가능한지 검증. 실패 시 throw.
    static func validate(path: String) throws {
        if ProtectedPaths.isProtected(path) { throw SafetyViolation.protectedPath(path) }
        if !FileManager.default.fileExists(atPath: path) { throw SafetyViolation.notExists(path) }
        // 홈 디렉토리 외부는 기본적으로 금지 (v1)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let resolved = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        if !resolved.hasPrefix(home) && !resolved.hasPrefix("/Volumes/") {
            throw SafetyViolation.outsideHome(resolved)
        }
    }

    /// 한 번에 여러 경로 검증 — 실패한 것만 반환.
    static func filterValid(paths: [String]) -> (valid: [String], rejected: [(String, SafetyViolation)]) {
        var ok: [String] = []
        var bad: [(String, SafetyViolation)] = []
        for p in paths {
            do { try validate(path: p); ok.append(p) }
            catch let e as SafetyViolation { bad.append((p, e)) }
            catch { bad.append((p, .notExists(p))) }
        }
        return (ok, bad)
    }
}
