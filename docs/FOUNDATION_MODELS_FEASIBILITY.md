# Feasibility: Replacing the Claude API with Apple Foundation Models

Research note — 2026-05-26. Scope: can Tada drop its remote Claude API dependency
and run entirely (or partly) on Apple's on-device Foundation Models framework
(`import FoundationModels`, macOS 26+)?

## TL;DR

**Full replacement is not viable today.** Three of the app's AI calls — Executive UI
generation, the Coach, and knowledge-base link discovery — exceed the on-device model's
**4,096-token context window**, need capabilities the on-device model is weak at
(agentic multi-tool reasoning), or need **image input the public framework doesn't
expose**. A naive swap would degrade the product's core experience.

**A hybrid is viable and worthwhile.** The app's architecture (each AI call is an
`actor` service behind a protocol, wired through DI) already supports swapping
implementations per service. The small, text-only, single-shot calls (discovery
questions, execution plan, subtask/overview notes, learnings) fit the on-device model's
budget and play to its strengths (summarization, extraction, short structured output).
Moving those on-device buys privacy, offline support, and zero API cost on the common
path while keeping the heavy/multimodal/agentic calls on the remote API.

**Recommended first step:** a one-service spike (discovery questions) behind the
existing protocol to measure real token usage and output quality before committing.

---

## 1. How Tada uses remote AI today

All AI goes through `ClaudeAPIClient` (an `actor`). Structured output uses Anthropic's
`tool_use` + forced `tool_choice` mechanism — the JSON shape is guaranteed by a
hand-written `input_schema` per response type (`getToolSchema`). Model is
`claude-sonnet-4-6` (user-selectable via `ModelCatalog` / `ModelPreference`).

| Service · method | Mechanism | Approx. prompt budget | Image? | Notes |
|---|---|---|---|---|
| `PlannerAIService.generateDiscoveryQuestions` | structured `TaskPlan` | ~700 tok sys + tiny input | no | most-frequent planner call |
| `PlannerAIService.createExecutionPlan` | structured `TaskPlan` | ~680 tok sys + answers + learnings | no | |
| `PlannerAIService.revisePlan` | structured `PlanRevision` | medium | no | |
| `PlannerAIService.breakDownStep` | structured `MicroStepsResponse` | medium | no | |
| `PlannerAIService.generateLearning` | plain text, `maxTokens: 100` | tiny | no | |
| `ExecutiveAIService.generateActionUI` | structured `ActionSchema` (nested, 14 field types) | **~2,900 tok fixed** (sys ~2,300 + schema ~600) | passes drawings as **text only** | **runs on every sub-task** |
| `KnowledgeAIService.generateSubtaskNote` | structured note, `maxTokens: 1024` | small | **YES** — sketch PNG uploaded | only real image upload in the app |
| `KnowledgeAIService.discoverLinksForNote` | structured links, **`maxTokens: 8192`** | **large** (many candidate notes @ 800 chars) | no | |
| `KnowledgeAIService.extractEntitiesAndLink` | structured entities, `maxTokens: 2048` | note body + growing entity list | no | |
| `KnowledgeAIService.generateTaskOverviewNote` | structured note, `maxTokens: 1024` | medium | no | |
| `CoachService.chat` | **agentic tool calling**, 17 tools, `maxTokens: 1024` | sys ~700 + tools ~1,200 + 10-msg history + context | no | multi-turn `tool_result` loop |
| `ModelCatalog.fetchModels` | `GET /v1/models` | — | — | model picker; no on-device analog |

Gating: `APIKeyManager` (key in UserDefaults), `APIKeyBanner`, settings tab, `APILog`
console. All of this exists only because the AI is remote.

## 2. What Apple Foundation Models offers (and its hard limits)

Confirmed against Apple docs + developer reports, current as of early 2026:

- **On-device model: ~3B params, 2-bit quantized.** Tuned for summarization, entity
  extraction, classification, tagging, short dialog, and creative-text generation.
  Apple explicitly states it is **not a general world-knowledge chatbot** and **not for
  reasoning/logic-heavy or agentic tasks**. Training cutoff ~Oct 2023.
- **Context window: 4,096 tokens, hard limit** (input + output combined, ~3,000 words).
  Throws `.exceededContextWindowSize`. macOS/iOS 26.4 added `SystemLanguageModel.contextSize`
  and `tokenCount(for:)` (back-deployed) to budget against it.
- **Guided generation** via the `@Generable` / `@Guide` macros — type-safe structured
  output through constrained decoding. This is the clean replacement for the hand-written
  `tool_use` schemas and is arguably *better* (compile-checked Swift types, no JSON
  plumbing).
- **Tool calling** via the `Tool` protocol — covers the Coach's needs mechanically.
- **No image input in the public framework.** The underlying model has vision, but the
  `FoundationModels` API is **text-only** for third-party apps as of early 2026. (Apple's
  own system features use vision; third parties cannot send images through
  `LanguageModelSession`.)
- **Languages:** EN, FR, DE, IT, PT-BR, ES, JA, KO, ZH-Hans (+ more rolling out). German
  is covered — relevant given the app's tax-filing example task.
- **Availability:** Apple-Intelligence-capable device (Apple Silicon) on macOS 26+, with
  Apple Intelligence enabled. Check via `SystemLanguageModel.availability`.
- **Cost/privacy:** free, fully offline, on-device. Streaming via `PartiallyGenerated`.

## 3. Feasibility per call

| Call | On-device verdict | Why |
|---|---|---|
| `generateDiscoveryQuestions` | ✅ **Good fit** | ~700-tok prompt + small input, structured short output — squarely in the model's wheelhouse |
| `createExecutionPlan` | ✅ Fits (watch budget) | fits under 4,096 unless discovery answers + learnings grow large |
| `revisePlan` / `breakDownStep` | ⚠️ Fits, quality risk | fits the window, but these are *judgment* calls (split compounds, don't invent items) where a 3B model is weaker |
| `generateLearning` | ✅ Trivial fit | tiny in/out |
| `generateSubtaskNote` (text) | ✅ Good fit | summarization/extraction — the model's core strength |
| `generateSubtaskNote` (with sketch) | ❌ **Blocked** | needs image input; not exposed by the framework |
| `generateTaskOverviewNote` | ✅ Fits | medium, summarization |
| `extractEntitiesAndLink` | ⚠️ Borderline | note body is small, but the **existing-entities list grows unbounded** with the wiki → will eventually exceed 4,096 |
| `discoverLinksForNote` | ❌ **Blocked** | `maxTokens: 8192` alone > full window; input is many candidate notes by design |
| `generateActionUI` | ❌ **Blocked / severe risk** | ~2,900-tok fixed overhead + context routinely pushes past 4,096; also the highest-stakes *quality* call (14 field types, dense rules) — runs on **every sub-task** |
| `CoachService.chat` | ❌ **Blocked** | system + 17 tools + 10-msg history blows the window; agentic multi-tool loop is exactly what Apple flags the model as weak at |

## 4. The four blockers, ranked

1. **4,096-token context window.** Dominant constraint. It kills Executive UI generation
   (the most-used call), the Coach, and link discovery. The app's prompt style — long,
   rule-dense system prompts with many negative examples — is the opposite of what fits.
   Adopting on-device means **aggressively rewriting prompts** to be terse, which itself
   risks the behavioral quality those rules were added to enforce.
2. **No image input.** Confined to exactly one call (`generateSubtaskNote` with a sketch).
   Everywhere else drawings are already reduced to text before the AI sees them. Workable
   via a separate on-device Vision pass (`VNRecognizeTextRequest` / image classification)
   or by keeping just this call remote — but it cannot go through Foundation Models.
3. **Model capability ceiling (3B, 2-bit).** Guided generation guarantees output *shape*,
   not *decision quality*. The Executive ("pick the best of 14 field types") and Planner
   revision ("split compound steps, never invent items") encode a lot of judgment. Expect
   regression vs. Sonnet; needs side-by-side eval, not assumption.
4. **OS / hardware floor.** App currently targets **macOS 14.0**. Foundation Models needs
   **macOS 26 + Apple Silicon + Apple Intelligence on**. Going on-device-only drops Intel
   Macs and every pre-Apple-Intelligence machine — a product decision, not just an
   engineering one. (A hybrid keeps the remote path as the fallback for those devices.)

## 5. Migration effort (mechanics)

The architecture is favorable — this is the good news.

**Low effort / clean:**
- New `FoundationModelsClient` (or per-service `LanguageModelSession` impls) behind the
  **existing service protocols** (`AppServices` DI). No call-site churn.
- Rewrite Codable response types (`TaskPlan`, `ActionSchema`, `GeneratedKnowledgeNote`,
  …) as `@Generable` with `@Guide` annotations. Replaces the entire `getToolSchema`
  dictionary-building block — net code *reduction*, and type-safe.
- Delete the remote-only scaffolding for migrated services: API-key UI/storage,
  `ModelCatalog`, HTTP logging.
- Availability gating: swap `APIKeyManager.hasValidAPIKey` checks for
  `SystemLanguageModel.availability`.

**Medium / real work:**
- `ActionSchema` as a `@Generable` type is non-trivial (nested fields, 14-case enum,
  optionals, prefill rows) — but mostly mechanical.
- Coach: rewrite 17 `CoachTool` cases as `Tool` conformances; rebuild the agentic loop on
  `LanguageModelSession`'s tool mechanism.
- Token budgeting: instrument every prompt with `tokenCount(for:)`, add
  `.exceededContextWindowSize` handling + truncation/summarization fallbacks.

**Hard / not mechanical (the actual cost):**
- Rewriting the long rule-laden prompts to fit 4,096 tokens **without losing behavior**.
- Re-architecting link discovery to a windowed/iterative scheme (score candidates in
  batches) instead of one big-context call.
- A real **quality eval harness** comparing on-device vs. Sonnet output for plans and UI
  schemas — the only way to know if the regression is acceptable.

## 6. Recommendation

**Adopt a hybrid, gated behind `SystemLanguageModel.availability`, and prove it one
service at a time.**

1. **Spike (small):** implement `FoundationModelsPlannerService.generateDiscoveryQuestions`
   behind the existing protocol. Measure `tokenCount`, latency, and output quality vs.
   Sonnet on ~20 real tasks. This validates the `@Generable` path and the token math with
   minimal code.
2. **If the spike holds:** migrate the other text-only, single-shot calls — execution
   plan, learnings, subtask/overview notes — to on-device, with the remote client as
   automatic fallback when the device is ineligible or a call overflows the window.
3. **Keep remote (for now):** Executive `generateActionUI`, the Coach, `discoverLinksForNote`,
   and the sketch variant of `generateSubtaskNote`. Revisit Executive only after a prompt
   diet + eval; revisit link discovery only after a windowed redesign.

This closes PRD Open Question #5 (offline support) for the planning/notes path, cuts API
cost on the common flow, and improves privacy — without betting the core UX-generation
and coach experiences on a 3B model that can't yet hold their context or their images.

## 7. What's coming (outlook as of 2026-05-26)

Separating **confirmed** from **rumored**, and **Siri/Apple-Intelligence features** from
the **third-party `FoundationModels` framework** — only the latter affects Tada.

**Confirmed:**
- **Apple ↔ Google Gemini deal** (Jan 2026, ~$1B/yr, multiyear). The *next generation* of
  Apple Foundation Models will be **based on Google's Gemini**, powering a "more
  personalized Siri" due in 2026 (Apple's deadline is Dec 31, 2026). Architecture
  (on-device vs. Private Cloud Compute vs. Google servers) is **still unclear**. Reporting
  is about **Siri / Apple Intelligence features** — there is **no confirmation** that
  third-party developers get the Gemini-based model through the `FoundationModels`
  framework. Do not assume the framework inherits it.
- **macOS/iOS 26.4** (RC as of Mar 2026): context-window *management*, not expansion —
  `SystemLanguageModel.contextSize` (back-deployed) + `tokenCount(for:)`. The **4,096-token
  limit is not increasing** in the near term (Apple dev-forum guidance). Nuance:
  `contextSize` is now a *property*, not a hardcoded constant — a forward-looking hint the
  window could vary by model/device later, but no number is announced.
- **On-device image input still doesn't work** for third parties: the Shortcuts "Use
  Model" action returns "I can't describe images directly" on the on-device model; only
  the server model does vision.

**Rumored — WWDC 2026 (June 8, 2026, ~2 weeks out):**
- **"Core AI" framework** replacing Core ML — Bloomberg *Power On* (moderate confidence);
  could be a substantive overhaul or just a rename.
- A **significantly larger on-device model** (medium confidence).
- Gemini-trained foundation models front-and-center; better fine-tuning; possibly
  expanded context windows (lower confidence, aggregated rumor).

**Implication for Tada:** the dominant blocker (4,096-token window) is **not being lifted
on the current timeline** — only better tooling to live within it. So the §6 hybrid
recommendation stands unchanged. **But WWDC 2026 is imminent**: a larger or Gemini-based
on-device model (± a bigger window) could materially change the verdict for the Executive
and Coach calls. Highest-leverage move: **watch the June 8 keynote before investing**, and
confirm whether any new model/window reaches the third-party framework rather than just
Siri.

## Sources

- [TN3193: Managing the on-device foundation model's context window — Apple](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Apple Improves Context Window Management for its Foundation Models — InfoQ](https://www.infoq.com/news/2026/03/apple-foundation-models-context/)
- [Foundation Models — Apple Developer Documentation](https://developer.apple.com/documentation/FoundationModels)
- [LanguageModelSession — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
- [Meet the Foundation Models framework — WWDC25 (286)](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Updates to Apple's On-Device and Server Foundation Language Models — Apple ML Research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [Introducing Apple's On-Device and Server Foundation Models — Apple ML Research](https://machinelearning.apple.com/research/introducing-apple-foundation-models)
- [Introduction to Apple's FoundationModels: Limitations, Capabilities, Tools — Natasha The Robot](https://www.natashatherobot.com/p/apple-foundation-models)
- [Apple's Foundation Models framework unlocks new intelligent app experiences — Apple Newsroom](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [Apple picks Google's Gemini to run AI-powered Siri — CNBC](https://www.cnbc.com/2026/01/12/apple-google-ai-siri-gemini.html)
- [Google Confirms Gemini-Powered Siri Coming Later This Year — MacRumors](https://www.macrumors.com/2026/04/22/google-gemini-powered-siri-2026/)
- [WWDC 2026 to introduce Core AI as replacement for Core ML — AppleInsider](https://appleinsider.com/articles/26/03/01/wwdc-2026-to-introduce-core-ai-as-replacement-for-core-ml)
- [Counting / tracking tokens in Foundation Models (contextSize, tokenCount) — zats.io](https://zats.io/blog/counting-tokens-in-foundation-models/)
</content>
</invoke>
