import Foundation

enum AgentPromptBuilder {
    static let systemPrompt: String = """
    당신은 DiskSense 앱에 내장된 macOS 저장공간 정리 에이전트입니다.
    사용자의 홈 디렉토리를 분석하고, 정리해도 안전한 항목을 제안하는 것이 목표입니다.

    **당신의 원칙:**
    1. 파일 **내용**은 절대 접근할 수 없습니다. 메타데이터(이름/크기/날짜/구조)만 사용합니다.
    2. 제안하기 전에 **반드시 툴로 조사**하세요. 추측 금지. 각 제안의 reason에 툴 호출 결과를 인용하세요.
    3. 의심스러운 폴더는 list_directory, check_dev_project, count_files_by_extension 등으로 조사 후 결정.
    4. 개발 캐시(node_modules, DerivedData, Pods, .gradle, target, __pycache__, venv, brew cache, Docker 볼륨)는 재생성 가능하므로 우선 후보. risk: safe.
    5. 오랫동안 수정/접근되지 않은(90일+) 대용량 항목은 caution으로 제안.
    6. 개인 문서, 최근 수정된 파일, 사진/영상 원본, 시스템 설정은 절대 제안하지 마세요.
    7. 과거 cleanup 히스토리를 먼저 조회해서 유저의 선호 패턴을 파악하세요 (get_cleanup_history).
    8. 모든 조사와 제안을 마치면 반드시 **finish** 툴을 호출하세요. 그전엔 끝나지 않습니다.
    9. danger 위험도는 제안하지 마세요. safe 또는 caution만.
    10. 제안하는 경로는 반드시 사용자 홈(~/) 하위. 시스템 경로(/System, /Library)는 제외.

    **흐름 예시:**
    1. get_cleanup_history로 과거 패턴 확인
    2. 초기 컨텍스트에서 가장 큰 항목부터 list_directory로 내부 구조 파악
    3. 개발 프로젝트인지 check_dev_project로 확인
    4. 확신이 들면 propose_cleanup 호출 (증거 인용한 reason과 함께)
    5. 다른 큰 항목들도 반복
    6. finish(summary: "5개 제안, 약 47 GB 정리 가능")
    """

    /// 스캔 결과 + 볼륨 정보를 에이전트 초기 컨텍스트로 직렬화.
    static func buildInitialContext(
        scanResult: ScanResult,
        volumeUsage: VolumeInfo.Usage?
    ) -> String {
        let df = ISO8601DateFormatter()
        let topItems = scanResult.items.prefix(40)
        var lines: [String] = []
        lines.append("=== 볼륨 사용량 ===")
        if let u = volumeUsage {
            lines.append("total=\(u.total), used=\(u.used), available=\(u.available)")
        } else {
            lines.append("total=\(scanResult.totalCapacity), used=\(scanResult.totalUsed)")
        }
        lines.append("")
        lines.append("=== 카테고리별 (bytes) ===")
        for (cat, bytes) in scanResult.breakdown.sorted(by: { $0.value > $1.value }) {
            lines.append("\(cat.rawValue): \(bytes)")
        }
        lines.append("")
        lines.append("=== 홈 디렉토리 최상위 용량 Top 40 ===")
        for item in topItems {
            lines.append("- [\(item.category.rawValue)] \(item.path) | \(item.sizeBytes) bytes | mtime=\(df.string(from: item.modifiedDate))")
        }
        lines.append("")
        lines.append("이제 조사를 시작하세요. 먼저 get_cleanup_history로 유저 선호를 확인한 후, 의심스러운 폴더들을 툴로 조사하고, 근거 있는 제안들을 propose_cleanup으로 추가하고, 마지막에 finish를 호출하세요.")
        return lines.joined(separator: "\n")
    }
}
