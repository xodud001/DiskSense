# DiskSense

AI 기반 macOS 저장공간 정리 앱. Claude API로 파일 컨텍스트를 분석하고, 자연어로 삭제 이유를 설명한 뒤, 유저 승인 후 안전하게 정리한다. 개발 환경(node_modules, DerivedData, Docker, brew 캐시 등) 특화.

## Tech Stack

- **UI**: SwiftUI (macOS 14.0 Sonoma+)
- **상태 관리**: `@Observable` (Observation framework, Swift 5.9+)
- **로컬 DB**: SwiftData (히스토리, 설정)
- **네트워크**: URLSession + async/await (Anthropic REST API)
- **파일 시스템**: FileManager + POSIX stat
- **차트**: Swift Charts
- **메뉴바**: MenuBarExtra
- **알림**: UserNotifications
- **패키지 관리**: SwiftPM (외부 의존성 최소화)

Bundle ID: `com.yourname.DiskSense`

## 프로젝트 구조

```
DiskSense/
├── App/                    # DiskSenseApp, AppState, AppDelegate
├── Core/
│   ├── Scanner/            # DiskScanner, CategoryClassifier, DevToolScanner, PermissionChecker
│   ├── AI/                 # ClaudeAPIClient, AnalysisPromptBuilder, OfflineFallback
│   ├── Cleanup/            # CleanupExecutor, SafetyGuard, SnapshotManager
│   └── Storage/            # HistoryStore (SwiftData), SettingsStore
├── Features/
│   ├── Dashboard/          # DashboardView, StorageGaugeView, CategoryBreakdownView
│   ├── Analysis/           # AnalysisView, SuggestionCard, ApprovalSheet
│   ├── DevTools/           # DevToolsView, NodeModulesListView
│   ├── History/            # HistoryView, HistoryDetailView
│   ├── MenuBar/            # MenuBarView, StorageMiniGauge
│   └── Settings/           # SettingsView
├── Models/                 # DiskItem, ScanResult, AISuggestion, CleanupHistory, StorageCategory
└── Utilities/              # Constants (ProtectedPaths), ByteFormatter
```

## 핵심 원칙

1. **Privacy-first**: Claude API에는 파일 **이름/크기/수정일/경로만** 전송. 파일 **내용은 절대 전송하지 않음**.
2. **승인 기반 삭제**: AI는 제안만, 실행은 유저 체크 후 최종 확인 다이얼로그 거쳐야 함.
3. **보호 경로 하드코딩**: `ProtectedPaths.never` (`/System`, `/Library`, `~/.ssh`, Keychains, TCC 등)은 절대 삭제 후보로 올리지 않음.
4. **기본 휴지통 이동**: 영구삭제는 별도 옵션. 실행 전 JSON 스냅샷 저장.
5. **백그라운드 스캔**: `Task.detached` + actor isolation, 진행률 콜백으로 UI 업데이트.

## 데이터 모델 요약

- `StorageCategory`: `.apps, .documents, .photos, .developer, .system, .cache, .mail, .trash, .other`
- `RiskLevel`: `.safe, .caution, .danger`
- `DiskItem`: 경로/크기/수정일/카테고리
- `AISuggestion`: 대상/예상 절약/이유/위험도/복구 가능 여부
- `CleanupHistory` (SwiftData): 실행 시각/절약 용량/제안 목록/스냅샷 경로

## Entitlements & Info.plist

- `com.apple.security.files.user-selected.read-write = true`
- Info.plist: `NSFullDiskAccessUsageDescription` 필수

## Implementation Chunks

Chunk 1~3 (Core)은 **순차 진행**. Chunk 4~8 (Features)는 **병렬 가능**.

1. **Chunk 1** — 프로젝트 셋업 & 기본 구조 (2-3h)
2. **Chunk 2** — 디스크 스캐너 (3-4h)
3. **Chunk 3** — Claude API 연동 & AI 분석 (3-4h)
4. **Chunk 4** — 대시보드 UI (4-5h)
5. **Chunk 5** — AI 분석 결과 & 승인 UI (4-5h)
6. **Chunk 6** — 실행 엔진 & 안전 장치 (3-4h)
7. **Chunk 7** — 개발 환경 전용 탭 (2-3h)
8. **Chunk 8** — 메뉴바 & 히스토리 & 설정 (3-4h)

Spec 원본: `DiskSense-Design-Spec.docx`

## Build / Deploy / Test Loop

코드 수정 후 반영 표준 파이프라인:

```bash
# 1) Swift 파일 추가/삭제한 경우에만 프로젝트 재생성
cd /Users/taeyoung/personal-project/disk-sense
USER=$(id -un) xcodegen generate

# 2) 빌드
xcodebuild -project DiskSense.xcodeproj -scheme DiskSense \
  -configuration Debug build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -10

# 3) /Applications 로 재배포 + stable identifier 서명 (FDA 권한 유지 핵심)
pkill -x DiskSense 2>/dev/null
rm -rf /Applications/DiskSense.app
cp -R ~/Library/Developer/Xcode/DerivedData/DiskSense-*/Build/Products/Debug/DiskSense.app /Applications/
codesign --force --deep --sign - --identifier com.yourname.DiskSense /Applications/DiskSense.app

# 4) 실행
open /Applications/DiskSense.app
```

**중요**: `codesign --identifier com.yourname.DiskSense` 가 누락되면 재빌드마다 TCC가 다른 앱으로 인식 → Full Disk Access / Documents / Downloads 권한이 리셋되고 수많은 프롬프트가 다시 뜸.

## 메모리 / 세션 연속성

- `.claude/memory/learnings.md` — 세션 간 학습/삽질 기록. **새 세션 시작 시 이 파일을 먼저 읽고 작업**.
- `.claude/settings.local.json` — Stop / PreCompact 훅 등록.
- 이전 세션에서 발견된 함정 (enum 플래그, 취소 동기화, gh 다중 계정 등)은 learnings.md 에 누적되어 있음.

## UI 구조

Sidebar: 📊 대시보드 / 🤖 AI 분석 / 🔧 개발환경 / 📋 히스토리 / ⚙️ 설정

## Claude API

- Model: `claude-sonnet-4-6`
- max_tokens: 4096
- 시스템 프롬프트는 `AnalysisPromptBuilder.systemPrompt`에서 관리
- 오프라인 시 `OfflineFallback`이 룰 기반 제안 제공
