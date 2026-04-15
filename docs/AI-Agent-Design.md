# DiskSense AI Agent Design

## 현재 방식의 한계

- top 80개 항목을 한 번에 Claude에 전달 → 단순 룰북
- Claude는 폴더 **내부를 볼 수 없음** — 이름만으로 추측
- 증거 없는 제안 ("재생성 가능" 이라고 말은 하지만 실제로 .git 있는지 모름)
- 유저의 **과거 결정**을 반영 못 함
- 대화형 아님 — 사용자가 추가 가이드 못 줌

## 목표 — 에이전트 행동 특성

1. **Grounded**: 모든 제안에 툴 호출 → 증거 인용
2. **Iterative**: 의심 → 조사 → 확신 → 제안 (multi-step)
3. **Interactive**: 실시간으로 사용자에게 추론 과정 공개, 중간에 개입 가능
4. **Learning**: 과거 cleanup 히스토리를 컨텍스트로 사용
5. **Safe**: 파일 **내용은 절대 전송 X**. 메타데이터만.

---

## 아키텍처

```
┌────────────────────────────────────────────────────────┐
│                    AI Agent Loop                        │
├────────────────────────────────────────────────────────┤
│                                                         │
│   ┌─────────┐    tool_use     ┌─────────────────┐      │
│   │ Claude  │ ───────────────►│  Tool Executor  │      │
│   │ Sonnet  │                 │  (app-side)     │      │
│   │  4.6    │◄────────────────│                 │      │
│   └─────────┘   tool_result   └─────────────────┘      │
│       │                                                 │
│       ▼                                                 │
│   ┌──────────────────┐                                  │
│   │ Proposal buffer  │  제안 누적 (아직 UI 미표시)      │
│   └──────────────────┘                                  │
│                                                         │
└────────────────────────────────────────────────────────┘
```

### 1. Tool Layer (Claude가 호출 가능한 함수)

모든 툴은:
- 입력/출력 JSON
- 읽기 전용 (쓰기 X, 삭제 X)
- 경로는 home 이하로 제한
- ProtectedPaths 경로는 차단

| 툴 | 용도 | 리턴 |
|---|---|---|
| `list_directory(path, limit=50)` | 디렉토리 자식 목록 | `[{name, size, mtime, is_dir}]` |
| `get_item_details(path)` | 파일/폴더 상세 | `{size, mtime, atime, ext_breakdown?, file_count, git_tracked?, is_dev_project?}` |
| `sample_file_names(path, count=20)` | 랜덤 파일명 (내용 X) | `[string]` |
| `check_dev_project(path)` | 개발 프로젝트 마커 감지 | `{has_git, has_package_json, has_cargo_toml, build_dir_size, type}` |
| `get_last_opened(path)` | Spotlight `kMDItemLastUsedDate` | `date` 또는 `null` |
| `count_files_by_extension(path)` | 확장자별 집계 | `{ext: count}` |
| `get_cleanup_history(category?, limit=20)` | 과거 정리 기록 | `[{date, path, reason, user_approved}]` |
| `search_by_pattern(root, glob)` | 경로/이름 패턴 검색 | `[{path, size}]` |
| `propose_cleanup(suggestion)` | 제안 추가 (terminal output) | `ok` |
| `finish(summary)` | 에이전트 종료 | `ok` |

### 2. Agent Loop

```swift
actor AIAgent {
    func run(initialContext: ScanResult, history: [CleanupHistory]) async -> AgentRun {
        var messages: [Message] = [
            .system(systemPrompt),
            .user("Scan summary: \(serialize(initialContext))\n\n제안을 생성하려면 필요한 만큼 툴을 호출하고, 최종적으로 finish()를 호출해주세요.")
        ]
        var proposals: [AISuggestion] = []
        var steps = 0
        
        while steps < maxSteps {
            let response = try await client.messages(model, messages, tools)
            emit(.claudeTurn(response))  // UI 스트리밍
            
            let toolUses = response.content.filter { $0 is ToolUse }
            if toolUses.isEmpty { break }  // Claude가 텍스트만 반환 → 종료
            
            var toolResults: [ToolResult] = []
            for use in toolUses {
                emit(.toolCall(use.name, use.input))
                let result = try await executor.execute(use.name, use.input)
                emit(.toolResult(result))
                
                if use.name == "propose_cleanup" {
                    proposals.append(parseSuggestion(use.input))
                }
                if use.name == "finish" {
                    return AgentRun(proposals: proposals, summary: use.input.summary)
                }
                toolResults.append(ToolResult(id: use.id, content: result))
            }
            
            messages.append(.assistant(response.content))
            messages.append(.user(toolResults))
            steps += 1
        }
    }
}
```

### 3. 스트리밍 이벤트 (UI에 emit)

```swift
enum AgentEvent {
    case thinking(String)              // Claude의 텍스트 reasoning
    case toolCall(name: String, args: [String: Any])
    case toolResult(Any)               // 축약 표시
    case proposal(AISuggestion)        // 후보 추가
    case finished(summary: String)
    case error(String)
}
```

### 4. UI — 투명한 에이전트 피드

```
┌─ AI 분석 (에이전트 모드) ─────────────────── [■ 중지] ─┐
│                                                        │
│  🤔 홈 디렉토리 173 GB 중 의심스러운 큰 폴더부터        │
│     살펴보겠습니다                                      │
│                                                        │
│  🔧 list_directory("~/Documents")                      │
│     └ 12 entries · 94.6 GB                             │
│                                                        │
│  🤔 Documents 하위에 "old-projects" 폴더가 38 GB.      │
│     개발 프로젝트인지 확인하겠습니다                     │
│                                                        │
│  🔧 check_dev_project("~/Documents/old-projects")      │
│     └ has_git=true, has_node_modules=true,            │
│       build_dir_size=24 GB, last_commit=147일 전       │
│                                                        │
│  💡 제안 추가: old-projects/node_modules (24 GB)       │
│     위험도: 안전 · 재생성 가능                          │
│                                                        │
│  🔧 get_cleanup_history(category: "developer")         │
│     └ 지난 2주간 node_modules 3회 정리 (모두 승인됨)   │
│                                                        │
│  🤔 유저가 node_modules 정리에 긍정적. 적극 제안.       │
│                                                        │
│  (...계속...)                                          │
│                                                        │
├────────────────────────────────────────────────────────┤
│ 누적 제안 (5개 · 47 GB)                                │
│  ☑ 🟢 old-projects/node_modules      24.0 GB          │
│  ☑ 🟢 DerivedData                     8.1 GB          │
│  ☐ 🟡 Downloads/old-builds           14.0 GB          │
│  ...                                                   │
│                                                        │
│ [선택 실행 (3/5 · 32 GB)]  [에이전트 재실행]           │
└────────────────────────────────────────────────────────┘
```

### 5. 상호작용 (v2)

- 사용자가 채팅 입력 → 에이전트 중에 추가 지시 (예: "Downloads는 건드리지 마")
- Claude가 "이 폴더 내용을 더 확인해도 될까요?" 같은 질문 가능
- 실행 후 "잘했나요?" 피드백으로 다음 번 학습

### 6. 안전장치

| 경계 | 처리 |
|---|---|
| 파일 내용 | Claude에 절대 전달 X. Sampling도 파일명만 |
| 민감 경로 | ProtectedPaths는 모든 툴에서 차단 |
| 홈 외부 | 툴 인자가 home 이하가 아니면 error |
| 최대 step 수 | 기본 25, 유저 설정 가능 |
| 최대 token | 예산 표시 + 한도 도달 시 finish 강제 |
| 모든 삭제 | 에이전트 종료 후 유저 승인 필수 (자동 실행 X) |

### 7. 히스토리 기반 학습 (간단 버전)

에이전트 시작 시 컨텍스트에 포함:
- 지난 30일 cleanup 목록 (카테고리별 카운트)
- 사용자가 최근 거부한 제안 경로 (예: "~/Desktop/ideas" 는 건드리지 말라는 신호)
- 선호 카테고리 (유저가 자주 승인한 카테고리 가중치)

### 8. 구현 단계

| Phase | 작업 | 예상 |
|---|---|---|
| A | Tool layer 5개 핵심 툴 구현 + 타입 정의 | 2h |
| B | `ClaudeAPIClient` 를 tool use 지원으로 확장 (system + tools 배열) | 1.5h |
| C | `AIAgent` actor 루프 + 이벤트 스트림 | 2h |
| D | `AnalysisView` 재구성 — 에이전트 피드 + 누적 제안 카드 | 3h |
| E | 히스토리 컨텍스트 주입 | 1h |
| F | 안전장치 + 스텝 제한 + 에러 처리 | 1h |

**총 ~10-11h.**

### 9. 비용 감각

- Sonnet 4.6: input ~$3/M, output ~$15/M (참고)
- 평균 run: 입력 20k tokens (툴 결과 포함) + 출력 5k = $0.06 + $0.075 ≈ **$0.15/run**
- 유저가 하루 2번 돌리면 월 $9. 대다수 유저는 주 1회 → 월 $0.60
- 비용 표시 UI 있어야 함 (설정에서 토큰 사용량 확인 가능)

---

## 대안: Lightweight 에이전트 (v1.0용)

전체 agent loop 구현이 무겁다면 **제한된 2-step 버전**으로 시작 가능:

**Step 1**: 현재처럼 top 80개 항목 전달 → Claude가 "더 조사할 경로 목록" 반환  
**Step 2**: 해당 경로들의 `list_directory` + `check_dev_project` 결과 묶어서 재전달 → 최종 제안 생성

2번만 API 호출하면 되므로 latency + 비용 예측 가능. v2에서 full agent loop로 진화.

---

## 선택지

- **A**: Full agent loop (위 설계대로) — 10-11h, 제대로 된 "AI 에이전트"
- **B**: Lightweight 2-step — 3-4h, 실용적 업그레이드
- **C**: Full agent loop + v2 상호작용(채팅) — 15h+

어떤 쪽으로 갈까요?
