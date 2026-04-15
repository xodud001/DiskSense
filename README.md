# DiskSense

**AI-powered storage cleanup for macOS.** Analyzes your disk, explains *why* files can be safely removed, and cleans up after your approval.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)
![License MIT](https://img.shields.io/badge/License-MIT-green)

---

## Why DiskSense?

Existing disk-cleanup tools show you *what* is big. DiskSense tells you *why* it's safe to remove — and lets you approve every action.

Unlike black-box "one-click cleaners," DiskSense runs an **AI agent** that actively investigates your folders with tools (directory listing, dev-project detection, last-opened timestamps, etc.) and produces **evidence-grounded suggestions**. Nothing is deleted without your explicit approval.

## Features

### Fast disk scanning
- Custom `getattrlistbulk(2)`-based bulk scanner (5–10× faster than `FileManager.enumerator`)
- Parallel per-top-level-child workers with live streaming progress
- Accurate volume-level usage (matches Finder's "Used" value)
- Category breakdown: Applications, Developer, Documents, Media, Cache, Mail, Trash, macOS, Other Users, System Data, Snapshots

### AI agent for cleanup suggestions
- **Multi-step reasoning loop** — the model investigates, hypothesizes, verifies, then proposes
- Tool-use with **10 scoped tools**: `list_directory`, `get_item_details`, `sample_file_names`, `check_dev_project`, `get_last_opened`, `count_files_by_extension`, `search_by_pattern`, `get_cleanup_history`, `propose_cleanup`, `finish`
- **Evidence chain** — every suggestion cites the tool calls that justified it
- Past cleanup history is surfaced as context so the agent respects your patterns

### Multi-provider AI support
| Provider | Models |
|----------|--------|
| Anthropic | Claude Opus 4.6, Sonnet 4.6, Opus 4.5, Sonnet 4.5, Haiku 4.5 |
| OpenAI | GPT-5, GPT-5 Mini, GPT-4.1 |
| Google | Gemini 2.5 Pro, Gemini 2.5 Flash |

Each provider has a separate API-key slot (stored in macOS Keychain). Switch models from a picker in the Analysis tab.

### Privacy-first
- **File contents are never sent** to any AI provider. Only metadata (path, size, mtime, category).
- System-critical paths (`/System`, `/Library`, `~/Library/Keychains`, `~/.ssh`, TCC database, etc.) are hard-blocked from both scanning suggestions and tool access.
- Full Disk Access permission is requested once and verified at runtime.

### Safe execution
- Every suggestion requires explicit user approval (per-item checkbox)
- Pre-execution JSON snapshot saved to Application Support for audit
- Default action is **move to Trash** (permanent delete is opt-in)
- Cleanup history stored in SwiftData

### Storage visualization
- Single capsule progress bar with per-category color segments
- Hover any segment for exact bytes + percentage
- Category chips with filter-on-click
- Top 30 large items list with Finder shortcut + path-copy context menu
- Menu-bar mini gauge with live updates

### Incremental rescan
- **FSEvents**-based change detection with 2-minute debounce
- 6-hour scheduled auto-rescan timer
- JSON scan cache in Application Support so the app opens instantly with last results

---

## Screenshots

> Screenshots coming soon.

---

## Getting Started

### Prerequisites
- macOS 14 (Sonoma) or later
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Build & Run
```bash
git clone https://github.com/xodud001/DiskSense.git
cd DiskSense
xcodegen generate
open DiskSense.xcodeproj
# Product → Run (⌘R)
```

### Grant Full Disk Access
On first launch, DiskSense needs Full Disk Access to scan `~/Library`, `/Applications`, and other protected paths:
1. System Settings → Privacy & Security → Full Disk Access
2. Add `DiskSense.app` (from `/Applications` or DerivedData build output)
3. Toggle it on, relaunch the app

### Register an AI provider
1. Settings tab → pick a provider (Anthropic / OpenAI / Google)
2. Paste API key → Save
3. The Analysis tab's model picker will light up

Without a key, DiskSense still runs a **rule-based local analyzer** (no network, no AI) for baseline suggestions.

---

## Architecture

```
DiskSense/
├── App/                  # DiskSenseApp, AppState, ContentView
├── Core/
│   ├── Scanner/          # BulkScanner (getattrlistbulk), DiskScanner (actor),
│   │                     # CategoryClassifier, SystemScanner, FSEventsWatcher,
│   │                     # PermissionChecker, VolumeInfo
│   ├── AI/
│   │   ├── Provider/     # AIProvider, AIModel, AnthropicClient, OpenAIClient,
│   │   │                 # GoogleClient, ModelRegistry
│   │   ├── Tools/        # Agent tool implementations (file system, history, proposal)
│   │   ├── AIAgent       # Agent loop (multi-turn, max 25 steps, cancellable)
│   │   ├── AgentEvent    # Streaming events (thinking, tool call/result, proposal)
│   │   └── AnalysisPromptBuilder, SuggestionParser, OfflineFallback
│   ├── Cleanup/          # CleanupExecutor, SafetyGuard, SnapshotManager
│   └── Storage/          # ScanCache (JSON), SettingsStore (UserDefaults), HistoryStore (SwiftData)
├── Features/
│   ├── Dashboard/        # DashboardView, StorageGaugeView, SegmentLegend, TopItemsView
│   ├── Analysis/         # AnalysisView, AgentFeedView, SuggestionCard, ApprovalSheet
│   ├── History/          # HistoryView with detail pane
│   ├── MenuBar/          # MenuBarView, StorageMiniGauge
│   └── Settings/         # Per-provider key input, model picker, thresholds
├── Models/               # ScanResult, DiskItem, AISuggestion, CleanupHistory, StorageCategory
└── Utilities/            # ProtectedPaths, ByteFormatter
```

### AI agent loop
```
User clicks "Start Analysis"
  ↓
AIAgent created with selected AIModel
  ↓
Initial context sent (top 40 items + volume usage + category breakdown)
  ↓
Loop (max 25 steps):
  ┌─ Claude/GPT/Gemini responds with tool_use or text
  │    ├─ if text only  → finish
  │    ├─ if tool_use   → execute locally, stream result back
  │    └─ if propose_cleanup → add to accumulated proposals
  └─
  ↓
finish() tool or text-only response → Run complete
  ↓
User reviews proposals in right pane → selects → approves → executes (Trash/permanent)
  ↓
Result saved to SwiftData history
```

### Provider abstraction
Each provider has its own wire format:

|                   | Anthropic            | OpenAI                 | Google                           |
|-------------------|----------------------|------------------------|----------------------------------|
| Endpoint          | `/v1/messages`       | `/v1/chat/completions` | `models/{id}:generateContent`    |
| Tools             | `tools[{input_schema}]` | `tools[{function}]` | `tools[{functionDeclarations}]`  |
| Tool call         | `content:[{tool_use}]` | `tool_calls[]`      | `parts:[{functionCall}]`         |
| Tool result       | `content:[{tool_result}]` | `role:"tool"`    | `parts:[{functionResponse}]`     |
| Auth              | `x-api-key`          | `Authorization: Bearer` | `?key=`                         |

The `AIProviderClient` protocol normalizes these into a common `start() / continueConversation()` interface. The agent loop itself is provider-agnostic.

---

## Roadmap

- [ ] App icon & About window
- [ ] Developer ID signing + Notarization for public distribution
- [ ] Interactive chat mid-run ("ignore Downloads folder")
- [ ] Duplicate file detection tool
- [ ] Token-budget cap per run, visible to user
- [ ] Better Snapshot / macOS volume accounting (right now approximate)

---

## Contributing

Issues and PRs welcome. For major changes, open an issue first to discuss.

## License

MIT © 2026 김태영
