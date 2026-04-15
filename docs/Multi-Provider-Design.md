# Multi-Provider AI 지원 설계

## 목표

- Claude (Anthropic) / OpenAI / Google Gemini 등 여러 AI 프로바이더 지원
- 프로바이더별 여러 모델 선택 가능
- 프로바이더별 API 키 **별도** 관리
- 분석 시작 전 현재 선택된 모델 명확히 표시
- 에이전트 루프는 공통 (툴 호출 방식만 각 프로바이더에 맞게 번역)

---

## 프로바이더 & 모델 매트릭스

| 프로바이더 | 모델 | Tool Use | 비용 (input/output per MTok) | 비고 |
|---|---|---|---|---|
| Anthropic | `claude-opus-4-5` | ✅ | $15 / $75 | 최상급 |
| Anthropic | `claude-sonnet-4-5` | ✅ | $3 / $15 | **기본값** |
| Anthropic | `claude-haiku-4-5` | ✅ | $1 / $5 | 빠름 |
| OpenAI | `gpt-5` | ✅ | $1.25 / $10 | Tool call 지원 |
| OpenAI | `gpt-5-mini` | ✅ | $0.25 / $2 | 가성비 |
| OpenAI | `o4` | ✅ | $1.10 / $4.40 | Reasoning |
| Google | `gemini-2.5-pro` | ✅ | $1.25 / $10 | 큰 context |
| Google | `gemini-2.5-flash` | ✅ | $0.15 / $0.60 | 빠름/저렴 |

(구체적 모델 이름/가격은 implementation 시점에 최신화 필요.)

---

## 아키텍처

### 1. 추상화 계층

```swift
protocol AIProviderClient {
    var provider: AIProvider { get }
    func sendMessagesWithTools(
        systemPrompt: String,
        messages: [AIMessage],
        tools: [AITool],
        model: String,
        maxTokens: Int
    ) async throws -> AIProviderResponse
}

enum AIProvider: String, CaseIterable {
    case anthropic = "Anthropic"
    case openai    = "OpenAI"
    case google    = "Google"
    
    var keychainKey: String {
        switch self {
        case .anthropic: return "anthropic-api-key"
        case .openai:    return "openai-api-key"
        case .google:    return "google-api-key"
        }
    }
    
    var apiKeyHelpURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .google:    return URL(string: "https://aistudio.google.com/apikey")!
        }
    }
}

struct AIModel: Identifiable, Hashable {
    let id: String           // 예: "claude-sonnet-4-5"
    let displayName: String  // "Claude Sonnet 4.5"
    let provider: AIProvider
    let supportsTools: Bool
    let inputCostPerMTok: Double
    let outputCostPerMTok: Double
}
```

### 2. 공통 메시지/툴 포맷

내부적으로는 통일된 포맷 사용 → 각 프로바이더 클라이언트가 변환.

```swift
enum AIMessage: Sendable {
    case user(String)
    case userTool(results: [(toolCallId: String, content: String, isError: Bool)])
    case assistant(content: [AIContentBlock])  // 프로바이더별 raw 포함 가능
}

enum AIContentBlock: Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
}

struct AITool: Sendable {
    let name: String
    let description: String
    let inputSchema: [String: Any]
}

struct AIProviderResponse: Sendable {
    let stopReason: String
    let text: String
    let toolUses: [AIContentBlock.ToolUse]
    let rawAssistantContent: Any  // 다음 턴에 assistant 메시지로 재주입
    let inputTokens: Int
    let outputTokens: Int
}
```

### 3. 프로바이더별 변환

| 요소 | Anthropic | OpenAI | Google |
|---|---|---|---|
| Endpoint | `/v1/messages` | `/v1/chat/completions` | `/v1beta/models/{model}:generateContent` |
| System prompt | top-level `system` field | first `message` with `role: "system"` | `systemInstruction` field |
| Tools | `tools: [{name, input_schema}]` | `tools: [{type:"function", function:{...}}]` | `tools: [{functionDeclarations:[...]}]` |
| Tool call | `content: [{type:"tool_use", ...}]` | `tool_calls: [{id, function:{name, arguments}}]` | `content.parts: [{functionCall:{name, args}}]` |
| Tool result | user msg with `content: [{type:"tool_result", tool_use_id, content}]` | user msg with `role:"tool", tool_call_id, content` | `parts: [{functionResponse:{name, response}}]` |
| Auth header | `x-api-key: <key>` | `Authorization: Bearer <key>` | query param `?key=<key>` |

각 프로바이더 클라이언트가 이 변환 담당.

### 4. 모델 레지스트리

```swift
enum ModelRegistry {
    static let models: [AIModel] = [
        // Anthropic
        AIModel(id: "claude-opus-4-5", displayName: "Claude Opus 4.5", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 15, outputCostPerMTok: 75),
        AIModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 3, outputCostPerMTok: 15),
        AIModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", provider: .anthropic,
                supportsTools: true, inputCostPerMTok: 1, outputCostPerMTok: 5),
        // OpenAI
        AIModel(id: "gpt-5", displayName: "GPT-5", provider: .openai,
                supportsTools: true, inputCostPerMTok: 1.25, outputCostPerMTok: 10),
        AIModel(id: "gpt-5-mini", displayName: "GPT-5 Mini", provider: .openai,
                supportsTools: true, inputCostPerMTok: 0.25, outputCostPerMTok: 2),
        // Google
        AIModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", provider: .google,
                supportsTools: true, inputCostPerMTok: 1.25, outputCostPerMTok: 10),
        AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", provider: .google,
                supportsTools: true, inputCostPerMTok: 0.15, outputCostPerMTok: 0.6),
    ]
    
    static let `default`: AIModel = models.first { $0.id == "claude-sonnet-4-5" }!
    
    static func find(_ id: String) -> AIModel? { models.first { $0.id == id } }
    static func forProvider(_ p: AIProvider) -> [AIModel] { models.filter { $0.provider == p } }
}
```

### 5. 선택 모델 저장

```swift
extension SettingsStore {
    static var selectedModelId: String {
        get { UserDefaults.standard.string(forKey: "selectedModelId") ?? ModelRegistry.default.id }
        set { UserDefaults.standard.set(newValue, forKey: "selectedModelId") }
    }
    
    static var selectedModel: AIModel {
        ModelRegistry.find(selectedModelId) ?? ModelRegistry.default
    }
}
```

### 6. AIAgent 수정

기존 `ClaudeAPIClient` 직접 호출 → `AIProviderClient` 프로토콜 사용.

```swift
actor AIAgent {
    private let client: AIProviderClient
    private let model: AIModel
    
    init(model: AIModel) {
        self.model = model
        self.client = ProviderFactory.make(for: model.provider)
    }
    
    func run(...) async throws -> RunResult {
        // 기존 로직 그대로, client.sendMessagesWithTools 호출만 교체
    }
}

enum ProviderFactory {
    static func make(for provider: AIProvider) -> AIProviderClient {
        switch provider {
        case .anthropic: return AnthropicClient()
        case .openai:    return OpenAIClient()
        case .google:    return GoogleClient()
        }
    }
}
```

---

## UI 변경

### 1. 설정 탭 — 프로바이더별 섹션

```
┌─────────────────────────────────────────────┐
│ AI 모델 & API 키                             │
├─────────────────────────────────────────────┤
│                                               │
│ 현재 선택된 모델                              │
│ [Claude Sonnet 4.5 ▾]                        │
│                                               │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━              │
│                                               │
│ 🟠 Anthropic (Claude)              [저장됨]  │
│    ┌────────────────────────────────────┐   │
│    │ sk-ant-...                          │   │
│    └────────────────────────────────────┘   │
│    [저장]  [삭제]  [API 키 발급]            │
│                                               │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━              │
│                                               │
│ 🟢 OpenAI                          [미설정]  │
│    [키 입력 필드...]                         │
│                                               │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━              │
│                                               │
│ 🔵 Google (Gemini)                 [미설정]  │
│    [키 입력 필드...]                         │
│                                               │
└─────────────────────────────────────────────┘
```

### 2. 분석 탭 — 상단 모델 표시 + 변경

```
┌─────────────────────────────────────────────┐
│ AI 분석                       [분석 시작]   │
│ 🟠 Claude Sonnet 4.5  [변경 ▾]              │
│    에이전트 모드 · 툴 10개                    │
└─────────────────────────────────────────────┘
```

Picker는 프로바이더별로 그룹화, API 키 없는 프로바이더는 disabled 또는 "API 키 등록 필요" 표시.

### 3. 메뉴바 — 현재 모델 부기 (선택)

```
DiskSense · Claude Sonnet 4.5
─────────────────────────────
(기존 내용)
```

---

## 구현 단계

| Phase | 작업 | 예상 |
|---|---|---|
| A | `AIProvider`, `AIModel`, `AIProviderClient` 프로토콜 + 공통 타입 정의 | 1h |
| B | `AnthropicClient` 구현 (기존 ClaudeAPIClient 리팩터) | 1h |
| C | `OpenAIClient` 구현 (chat/completions + tool calls + tool messages) | 2h |
| D | `GoogleClient` 구현 (generateContent + functionCalls) | 2h |
| E | `ModelRegistry`, `SettingsStore.selectedModel` | 0.5h |
| F | `SettingsView` 재구성 — 프로바이더별 섹션 3개 | 1.5h |
| G | `AnalysisView` 헤더 업데이트 — 모델 표시 + Picker | 1h |
| H | `AIAgent` 가 선택 모델 사용하도록 변경 | 0.5h |
| I | 에러 처리 — API 키 없을 때 / 키 오류 / quota 초과 | 1h |
| J | 비용 예측 표시 (선택적) | 1h |

**총 ~11-12h.**

---

## 안전/프라이버시 (변함없음)

- 파일 **내용** 전송 X, 메타데이터만
- ProtectedPaths 차단
- 각 프로바이더 키는 Keychain에 별도 저장 (service: `com.yourname.DiskSense`, account: `anthropic-api-key` 등)
- 네트워크는 선택된 프로바이더의 공식 endpoint로만

## 열려있는 질문

1. **모델 선호도 memory**: 유저가 자주 쓰는 모델별 스타일 차이 학습? v2로.
2. **Fallback 체인**: API 에러 시 다른 프로바이더로 자동 전환? 복잡도 ↑ — v1은 단일 프로바이더 사용.
3. **비용 표시**: 분석 후 "이번 실행에 약 $0.15 소요" 표시? 각 프로바이더의 usage 필드에서 입력/출력 토큰 받을 수 있음.
4. **Tool schema 호환**: OpenAI/Google은 JSON Schema subset 요구. 현재 우리 inputSchema는 JSON Schema 표준이라 대부분 호환될 것. 차이점(예: Gemini의 `"type": "OBJECT"` 대문자) 처리 필요.

---

## 기본 선택 (first-run)

- 키 하나라도 등록하면 그 프로바이더의 **가장 저렴한 모델**을 기본값으로 자동 선택 (예: OpenAI 키만 있으면 gpt-5-mini)
- 여러 프로바이더 키가 있으면 Claude Sonnet 4.5 기본

---

이대로 진행할까요?
