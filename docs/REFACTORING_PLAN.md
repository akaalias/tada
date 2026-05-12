# Refactoring Plan — Tada

Track progress of the refactoring plan documented in CONTEXT.md.

## Phase 1: Foundation (Critical)

- [x] **P1.1 — String enums** (`TaskStatus`, `SubTaskStatus`, `TaskPhase`, `PlanningStatus`)
  - Files: `Models/Enums.swift` (new), `Models/Task.swift`, `Models/SubTask.swift`
  - ADR: [001](../adr/001-refactor-string-enums.md)
  - Status: **Done** — build passes. SwiftData predicates use `.rawValue` for enum comparisons.

- [ ] **P1.2 — ViewModel extraction from ActionCard**
  - Extract `ActionCardViewModel` that owns: schema loading, response handling, submission flow, plan revision
  - Files: `Views/Tasks/ActionRequiredView.swift` (reduce from ~1659 lines)
  - Status: Not started

- [ ] **P1.3 — Split ActionUIRenderer**
  - One file per field renderer type (`TextFieldRenderer.swift`, `MultiSelectRenderer.swift`, etc.)
  - Coordinator file for the switch/registry
  - Files: `Views/ActionUI/` (reduce from single 2054-line file)
  - Status: Not started

## Phase 2: Architecture (Critical–Medium)

- [ ] **P2.1 — Split KnowledgeBaseService**
  - `KnowledgeBaseFilesystem` — file ops, folder mgmt, frontmatter parsing
  - `KnowledgeBaseGenerator` — AI note generation orchestration
  - `KnowledgeBaseIndexer` — index/regeneration
  - `KnowledgeBaseLinkDiscovery` — cross-link logic
  - Files: `Services/KnowledgeBaseService.swift` (reduce from ~1300 lines)
  - Status: Not started

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
