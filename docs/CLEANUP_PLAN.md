# Cleanup & De-duplication Plan (Session: 2026-05-18)

A cleanup pass over the codebase. Each step is its own commit, verified by build/tests.
Branch: `cleanup/dedup-pass`. Status: complete (step 8 skipped, see below).

## Correctness bugs (do first)

- [x] **1. Fix integration test target.** `Tests/TadaIntegrationTests/MockServices.swift` was stale:
  `MockExecutiveAIService.generateActionUI` lacked the `phase:` parameter; `MockKnowledgeBaseService`
  implemented only 8 of 21 protocol members and lacked `@MainActor`. Also repaired the `TadaTests`
  target, which was likewise non-compiling (`BrainstormBoard.addLabel` color param,
  `KnowledgeGraphBuilder.NoteInput.isUserNote`) and had one pre-existing failing test
  (`extractBodyRegion` empty-body contract).
- [x] **2. Fix AI schema field-type enum.** `ClaudeAPIClient` omitted `countSelector` and
  `rangeSlider` even though `ExecutiveAIService` instructs the model to emit them.

## De-duplication

- [x] **3. Dead code sweep.** Removed `PreviousInputsSummary`/`PreviousInputRow` (~167 lines),
  `CoachTool.displayName`, 7 unused `AppConstants`, both `loadNoteContent` copies,
  `revisePlan`'s `latestResponse` param, `DIError`, `ClaudeAPIError.missingAPIKey`,
  `TodoTask.isActive`, `ActionUIRenderer`'s `isValid`/`showingFieldTypePicker`,
  `KnowledgeBaseView.cleanupResult` dead write.
  Kept: `KnowledgeBaseLinkDiscovery.addRelatedBullets` (has 4 dedicated tests — not dead),
  `APIKeyManager.hasValidAPIKey` (actually used in ContentView/SettingsView — agent was wrong).
- [x] **4. ClaudeAPIClient HTTP boilerplate.** Extracted `makeRequest`, `apiErrorMessage`,
  `throwIfAPIError`, `validateStatus`; centralized the `anthropic-version` literal.
- [x] **5. Consolidate `slugify`.** One `KnowledgeBaseFilesystem.slug(from:)`; removed 5 other copies.
- [x] **6. KB link-mutation duplication.** Extracted `mutateNote` + `entityWikilink`.
- [x] **7. `fieldChrome` ViewModifier.** Replaced duplicated input-field chrome across 6 renderers;
  collapsed `DateFieldRenderer`'s 3 repeated Menu blocks into `pickerMenu`.
- [ ] **8. Planner prompt fragments.** SKIPPED. The four prompts share concepts but are each
  hand-tuned and worded differently — not verbatim duplicates. Extracting shared constants would
  mean rewording prompts in a system with no test coverage for prompt content. Low value, real
  risk; left as-is.
- [x] **9. Consolidate `phaseColor`.** Added `Theme.discovery`/`.execution` + `TodoTask.phaseColor`.
- [x] **10. Discovery-subtask creation loop.** Extracted `TodoTask.addDiscoverySubTasks(from:into:)`;
  also fixed the cap inconsistency (planWithAI capped at 7, coach paths at `maxDiscoveryQuestions`).
- [x] **11. `ActionSchema` Codable decoders.** Added a `decode(_:default:)` container extension.
- [x] **12. `ResponseFormatter.actionResponseToDict`.** Now routes through `formatResponseValue`.

## Follow-up (deferred)

- UI tests (`TadaUITests`) are stale against a recent UI revision. Deferred deliberately — the
  UI may change further before being codified in tests. Update last.

## Verification

`./scripts/test` runs unit + integration + UI tests. Unit (222) and integration (33) tests pass
after every step; UI tests not run (see follow-up).
