# Tada — Project Context

## What is this?

Tada is a native macOS task management app (SwiftUI + SwiftData) that uses two AI agents to re-imagine how people complete tasks:

1. **Planner AI** — takes a vague user input and structures it into clarifying questions (discovery phase), then creates an action plan (execution phase)
2. **Executive AI** — generates a custom UI schema for each sub-task, so the user completes work *inside* the app via forms, selects, sliders, drawings, etc.

A secondary feature auto-generates a personal wiki (markdown notes on disk) from completed sub-tasks, with AI-generated cross-links.

## Tech Stack

- **Platform:** macOS 14+ (Sonoma), SwiftUI, SwiftData
- **AI:** Claude API (Anthropic) — `claude-sonnet-4-6`
- **API Key:** stored in macOS Keychain via `APIKeyManager`
- **Persistence:** SwiftData models (`TodoTask`, `SubTask`) + on-disk markdown wiki

## Source Layout

```
Tada/Sources/
├── Models/
│   ├── Task.swift          → TodoTask (SwiftData model)
│   ├── SubTask.swift       → SubTask (SwiftData model)
│   └── ActionSchema.swift  → ActionSchema, ActionField, ResponseValue (Codable)
├── Services/
│   ├── ClaudeAPIClient.swift      → HTTP client, tool_use for structured output
│   ├── PlannerAIService.swift     → Discovery questions + execution plan generation
│   ├── ExecutiveAIService.swift   → Dynamic UI schema generation
│   ├── KnowledgeBaseService.swift → On-disk wiki: note gen, cross-links, index
│   ├── KnowledgeAIService.swift   → AI calls for wiki note generation
│   └── PlanningMemoryService.swift→ Persists "learnings" from bad planning decisions
├── Utilities/
│   └── APIKeyManager.swift
└── Views/
    ├── TadaApp.swift
    ├── ContentView.swift          → Navigation + sidebar
    ├── NewTaskSheet.swift         → Task creation modal
    ├── ActionUI/ActionUIRenderer.swift  → Dynamic form rendering (12+ field types)
    └── Tasks/
        ├── ActionRequiredView.swift     → Execution + discovery action cards (1659 lines)
        ├── AllTasksView.swift           → Task list with context menus
        ├── CompletedTasksView.swift
        ├── KnowledgeBaseView.swift
        ├── TaskCardComponents.swift     → Reusable card + header components
        └── AddSubTasksSheet.swift
```

## Key Domain Concepts

### Two-Phase Task Lifecycle

1. **Discovery Phase** — Planner asks 1–7 clarifying questions. User answers each via generated UI.
2. **Execution Phase** — Planner creates 3–7 action steps based on discovery answers. User completes each via generated UI. After each step, the plan may be revised.

### State Machine (per task)

```
idle → planningDiscovery → idle(discovery questions) → 
  [all answered] → planningExecution → idle(execution steps) →
  [all done] → completed
```

### State Machine (per sub-task)

```
pending ↔ current → completed
           ↓
         skipped
```

### External Actions

Some steps require real-world action outside the app (making calls, sending emails, going somewhere). These are flagged `requiresExternalAction: true` and use a yesNo confirmation UI. If the user says "No", they can select a blocker (needs breaking down, overwhelming, doesn't make sense, etc.).

### Knowledge Base

Every completed sub-task triggers AI-generated markdown notes on disk (`~/Application Support/Tada/knowledge/`). Notes are organized per task folder. A global `index.md` is maintained. Cross-link discovery runs ~6s after note writes, suggesting Obsidian-style wikilinks between related notes.

---

## Current Refactoring Plan (Session: 2026-05-11)

### Critical Issues

| # | Issue | Impact | Effort |
|---|-------|--------|--------|
| 1 | **String enums instead of Swift enums** — `status`, `phase`, `planningStatus` are all `String` | Bugs slip through, no exhaustive switches | Low |
| 2 | **Giant files** — `ActionUIRenderer.swift` (2054 lines), `ActionRequiredView.swift` (1659 lines), `KnowledgeBaseService.swift` (1300+ lines) | Hard to navigate, hard to test | Medium |
| 3 | **No ViewModels** — views do everything (AI calls, persistence, business logic) | Tight coupling, no testability | Medium |
| 4 | **No dependency injection** — services created inline, singleton `KnowledgeBaseService.shared` | Hard to mock, hard to change implementations | Low |
| 5 | **Field types hardcoded in multiple places** — switch statements duplicated across renderers and menus | Add a type = update N files | Low |

### Medium Priority

| # | Issue |
|---|-------|
| 6 | KnowledgeBaseService is a god object (filesystem + AI + parsing + discovery) |
| 7 | Duplicate response formatting logic in 4+ places |
| 8 | Magic numbers and timers scattered (`0.8`, `prefix(5)`, `maxTokens: 2048`) |
| 9 | No error handling abstraction — views show `.localizedDescription` directly |
| 10 | Zero tests |
| 11 | `actionSchemaData` / `actionResponseData` stored as raw `Data?`, no computed properties |
| 12 | Thread safety — `KnowledgeBaseService` uses detached tasks without clear ownership |

### Recommended Order

1. ~~**String enums**~~ — `TaskStatus`, `SubTaskStatus`, `TaskPhase`, `PlanningStatus` ✅
2. ~~**ViewModel extraction**~~ from `ActionCard` — biggest single improvement ✅ (model extracted, view wiring pending)
3. ~~**Split ActionUIRenderer**~~ — one file per field renderer type + coordinator ✅
4. ~~**Split KnowledgeBaseService**~~ — filesystem / AI orchestration / indexing / link discovery ✅
5. **Dependency injection** — protocols + optional container
6. **Extract utilities** — response formatting, constants, error handling
7. **Add tests** for models and services

---

## Working Process

- After completion of each step/phase, make a commit before moving on to the next one.

## Decisions Made

- Using Claude's `tool_use` / tool_choice mechanism for guaranteed structured JSON output (not prompt-parsing)
- Wiki notes stored on disk as markdown with Obsidian-style wikilinks (`[[path|title]]`)
- Planning learnings persisted to `planning_learnings.json` (last 20, fed into future prompts)
- Action schemas cached on `SubTask.actionSchemaData` to avoid regenerating

## Open Questions (from PRD)

1. Regeneration UX — how do users regenerate an action UI if it doesn't fit?
2. Undo/Edit — can users edit submitted responses after the fact?
3. Skip Actions — should users be able to skip/defer an action item? (partially implemented)
4. AI Transparency — how much of the AI's reasoning should be shown?
5. Offline Support — should the app work without internet?
