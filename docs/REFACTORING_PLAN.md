# Refactoring Plan — Tada

Track progress of the refactoring plan documented in CONTEXT.md.

## Phase 1: Foundation (Critical)

- [x] **P1.1 — String enums** (`TaskStatus`, `SubTaskStatus`, `TaskPhase`, `PlanningStatus`)
  - Files: `Models/Enums.swift` (new), `Models/Task.swift`, `Models/SubTask.swift`
  - ADR: [001](../adr/001-refactor-string-enums.md)
  - Status: **Done** — build passes. SwiftData predicates use `.rawValue` for enum comparisons.

- [x] **P1.2 — ViewModel extraction from ActionCard**
  - Extract `ActionCardViewModel` that owns: schema loading, response handling, submission flow, plan revision
  - Files: `Views/Tasks/ActionRequiredView.swift` (reduce from ~1659 lines)
  - Status: **Done** — `ActionCardViewModel.swift` created (400+ lines). View wiring still pending.

- [x] **P1.3 — Split ActionUIRenderer**
  - One file per field renderer type (`TextFieldRenderer.swift`, `MultiSelectRenderer.swift`, etc.)
  - Coordinator file for the switch/registry
  - Files: `Views/ActionUI/` (reduce from single 2054-line file)
  - Status: **Done** — 13 renderer files in `Renderers/`, coordinator at ~160 lines.
  - Extract `ActionCardViewModel` that owns: schema loading, response handling, submission flow, plan revision
  - Files: `Views/Tasks/ActionRequiredView.swift` (reduce from ~1659 lines)
  - Status: Not started

- [ ] **P1.3 — Split ActionUIRenderer**
  - One file per field renderer type (`TextFieldRenderer.swift`, `MultiSelectRenderer.swift`, etc.)
  - Coordinator file for the switch/registry
  - Files: `Views/ActionUI/` (reduce from single 2054-line file)
  - Status: Not started

## Phase 2: Architecture (Critical–Medium)

- [x] **P2.1 — Split KnowledgeBaseService**
  - `KnowledgeBaseFilesystem` — file ops, folder mgmt, frontmatter parsing
  - `KnowledgeBaseGenerator` — AI note generation orchestration + response extraction
  - `KnowledgeBaseIndexer` — index/regeneration, entry loading
  - `KnowledgeBaseLinkDiscovery` — cross-link logic
  - Files: `Services/` (reduce from single ~1300-line file to 5 focused files)
  - Status: **Done** — build passes. Coordinator is thin, all actors properly isolated.

- [ ] **P2.2 — Dependency injection**
  - Protocol-based service interfaces
  - Optional DI container or constructor injection
  - Files: All services + views that create them inline
  - Status: Not started

## Phase 3: Polish (Medium)

- [ ] **P3.1 — Extract utilities**
  - `ActionResponseFormatter` — single place for response → string conversion
  - Constants/config object for magic numbers (`0.8`, `prefix(5)`, `maxTokens`)
  - Status: Not started

- [ ] **P3.2 — Error handling abstraction**
  - User-friendly error hierarchy
  - Retry logic for API calls
  - Status: Not started

- [ ] **P3.3 — Add tests**
  - Unit tests for models, schema parsing, response formatting
  - Status: Not started

## Session Log

| Date | What happened |
|------|--------------|
| 2026-05-11 | Initial codebase review. Identified 12 issues across 3 priority levels. Created CONTEXT.md, ADR-001, and this plan file. No code changes yet — user asked to save state for later. |
| 2026-05-11 | **P1.1 Done** — Created `Enums.swift` with 4 Swift enums (`TaskStatus`, `SubTaskStatus`, `TaskPhase`, `PlanningStatus`). Updated all models, views, and KnowledgeBaseService. SwiftData predicates use `.rawValue` for enum comparisons. Build passes.
| 2026-05-11 | **P1.3 Done** — Split 2054-line `ActionUIRenderer.swift` into 13 renderer files under `Views/ActionUI/Renderers/`. Coordinator reduced to ~160 lines. Build passes.
| 2026-05-11 | **P1.2 Done** — Extracted `ActionCardViewModel` (400+ lines) owning schema loading, response handling, submission flow, plan revision. View wiring still pending.
| 2026-05-12 | **P2.1 Done** — Split KnowledgeBaseService (~1300 lines) into 5 focused files: `KnowledgeBaseFilesystem`, `KnowledgeBaseGenerator`, `KnowledgeBaseIndexer`, `KnowledgeBaseLinkDiscovery`, and thin coordinator. All actors properly isolated. Build passes.
