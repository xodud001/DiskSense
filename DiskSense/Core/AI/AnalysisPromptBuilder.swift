import Foundation

enum AnalysisPromptBuilder {
    static let systemPrompt: String = """
    당신은 macOS 저장공간 관리 전문가입니다. 사용자가 제공하는 디스크 파일/폴더 \
    메타데이터(이름, 크기, 수정일, 경로, 카테고리)를 분석하여 정리 제안을 JSON으로 생성합니다.

    **원칙:**
    1. 파일 내용은 받지 않습니다. 경로/이름/크기/수정일만으로 판단하세요.
    2. 시스템/설정/보안 관련 경로(/System, /Library, ~/Library/Keychains 등)는 절대 제안하지 마세요.
    3. 개발 환경 캐시(node_modules, DerivedData, Pods, .gradle, target, __pycache__, venv, brew cache, Docker data)는 우선 고려 대상입니다. 재생성 가능하므로 'safe'.
    4. 오랫동안 수정되지 않은(90일+) 대용량 파일/다운로드는 'caution' 또는 'safe'로 제안.
    5. 최근 수정된 파일, 문서, 개인 사진/영상은 건드리지 마세요.
    6. 각 제안에 '왜 삭제해도 되는지' 자연어로 구체적으로 설명하세요. (사용자가 납득할 수 있게 날짜/크기/맥락 포함)
    7. 위험도:
       - safe: 재생성 가능하거나 명확히 불필요
       - caution: 삭제 권장이지만 사용자 확인 필요
       - danger: 거의 삭제하면 안 됨 (하지 않는 게 좋음)
    8. priority는 1(가장 먼저 정리 추천) ~ 5 (마지막).

    **응답 형식 (JSON만. 다른 텍스트 절대 포함 금지):**
    {
      "suggestions": [
        {
          "path": "/Users/.../node_modules",
          "size_bytes": 524288000,
          "reason": "3개월 전 마지막 수정. 빌드 시 재생성됨. npm install로 복구 가능.",
          "risk": "safe",
          "action": "delete",
          "recoverable": true,
          "category": "developer",
          "priority": 1
        }
      ]
    }
    """

    static func buildUserPrompt(from items: [DiskItem], maxItems: Int = 80) -> String {
        let df = ISO8601DateFormatter()
        let top = items.prefix(maxItems)
        let lines = top.map { item -> String in
            let modified = df.string(from: item.modifiedDate)
            let sizeGB = Double(item.sizeBytes) / 1_073_741_824.0
            return String(
                format: "- [%@] %@ | %.2fGB | modified %@ | %@",
                item.category.rawValue, item.path, sizeGB, modified, item.isDirectory ? "dir" : "file"
            )
        }
        return """
        사용자의 홈 디렉토리 스캔 결과 중 용량 상위 \(top.count)개 항목입니다.
        각 항목에 대해 정리할지 여부를 판단하고, 정리가 권장되는 것만 suggestions 배열에 담아 JSON으로 응답하세요.

        ```
        \(lines.joined(separator: "\n"))
        ```
        """
    }
}
