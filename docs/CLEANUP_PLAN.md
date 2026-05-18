# Cleanup & De-duplication Plan (Session: 2026-05-18)

A cleanup pass over the codebase. Each step is its own commit, verified by build/tests.
Branch: `cleanup/dedup-pass`.

## Correctness bugs (do first)

- [ ] **1. Fix integration test target.** `Tests/TadaIntegrationTests/MockServices.swift` is stale:
  `MockExecutiveAIService.generateActionUI` lacks the `phase:` parameter; `MockKnowledgeBaseService`
  implements only 8 of 21 protocol members and lacks `@MainActor`. Target does not compile.
  Done first so the test suite can act as a safety net for the rest.
- [ ] **2. Fix AI schema field-type enum.** `ClaudeAPIClient.swift:240` omits `countSelector` and
  `rangeSlider` even though `ExecutiveAIService` instructs the model to emit them. Update the enum
  and the stale description string.

## De-duplication

- [ ] **3. Dead code sweep.** Delete: `PreviousInputsSummary`/`PreviousInputRow` (~167 lines),
  `CoachTool.displayName`, 7 unused `AppConstants`, `KnowledgeBaseService.loadNoteContent` +
  `KnowledgeBaseIndexer.loadNoteContent`, `KnowledgeBaseLinkDiscovery.addRelatedBullets`,
  `revisePlan`'s `latestResponse` param, `DIError`, `ClaudeAPIClient.missingAPIKey`,
  `TodoTask.isActive`, `APIKeyManager.hasValidAPIKey`, `ActionUIRenderer`'s `isValid` /
  `showingFieldTypePicker`, `KnowledgeBaseView.cleanupResult` dead write.
- [ ] **4. ClaudeAPIClient HTTP boilerplate.** Extract `makeRequest()` + `parseAPIError(in:)`;
  centralize the `anthropic-version` literal.
- [ ] **5. Consolidate `slugify`.** One `KnowledgeBaseFilesystem.slug(from:)`; remove 5 other copies.
- [ ] **6. KB link-mutation duplication.** Extract a `mutateNote` wrapper shared by
  `addLinkToNote` / `replaceTextWithLink`.
- [ ] **7. `fieldChrome` ViewModifier.** Replace the ~16 duplicated input-field background/stroke
  blocks; collapse `DateFieldRenderer`'s 3 repeated Menu blocks.
- [ ] **8. Planner prompt fragments.** Extract repeated prompt rules into `static let` constants.
- [ ] **9. Consolidate `phaseColor`.** `Theme.discovery`/`.execution` + `TodoTask.phaseColor`;
  drop the 4 copies and the `Color` in `ActionCardViewModel`.
- [ ] **10. Discovery-subtask creation loop.** Extract one helper used by both view models.
- [ ] **11. `ActionSchema` Codable decoders.** Replace 3 hand-written `init(from:)` with a
  `decode(_:default:)` container extension.
- [ ] **12. `ResponseFormatter.actionResponseToDict`.** Call `formatResponseValue` instead of
  re-implementing the switch.

## Verification

`./scripts/test` runs unit + integration + UI tests. Tests must pass before and after each step.
