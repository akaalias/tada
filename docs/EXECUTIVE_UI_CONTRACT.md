# Executive UI Generation — Feature Contract & On-Device Design

The Executive call ("given a sub-task, produce ONE UI control") is the app's hardest AI
call. This is its full feature contract (from the original Claude implementation) and how
each part is delivered on the local model, so we stop losing features one at a time.

## 1. The contract (what a generated Action UI guarantees)

**Schema level**
- `type` = `form`
- `title` — the EXACT sub-task title (never invented)
- `description` — optional one-line context
- `submitLabel` — Confirm (yesNo) / Save (entering info) / Continue (selection) / Complete (final)
- `requiresExternalAction` — true for real-world actions outside the app
- exactly ONE field

**Field level — every field type and the data it requires to render correctly**

| Field type | Required payload | Notes |
|---|---|---|
| `text` | label, **placeholder** | placeholder = a gray HINT in the empty field (what to type), never pre-filled content |
| `textarea` | label, **placeholder** | same |
| `number` | label, **placeholder** | example value |
| `date` | label | single calendar date |
| `countSelector` | label | small whole-number count |
| `slider` | label, **validation.min/max** | single value on a scale |
| `rangeSlider` | label, **validation.min/max** | budgets/prices |
| `yesNo` | label, **options** (2: yes/no) | external-action confirmation |
| `singleSelect` | label, **options** (3–6) | pick one |
| `multiSelect` | label, **options** (3–6) | pick several |
| `orderedList` | label, **options** (rows to reorder) | arrange/sort/prioritize |
| `hierarchicalList` | label, **prefillRows** `{item, depth}` | seeded starter tree |
| `itemTable` | label, **columns** via options; `option.description` = `currency` / `select:A,B,C` / text | max 3 columns |

**Behavioral**
- Correct type selection for the question (the judgment).
- yesNo always has two descriptive options.
- Prefill uses the user's EXACT words from previous responses; never invent items.
- No emojis. Focus on THIS sub-task — don't let a prior question's topic bleed into the label.

## 2. Local-model constraints

- **4,096-token context window** — instructions + schema + prompt + output must fit.
- **No image input** — `drawing` can't be AI-described (PNG still saved/embedded).
- **Weaker judgment** — the 3B model picks valid-but-wrong *types* and can be inconsistent.
- **Guided generation** — output shape is guaranteed by the `@Generable` type; behavior is not.

## 3. The design (how each contract item is delivered)

**Structure — `GenField` is a `@Generable` enum with associated values.** Each case carries
ONLY its valid payload, so the model literally cannot produce a contradictory field (options
on a text box, a slider with choices). This makes every "wrong shape" bug unrepresentable and
restores every per-type payload:

- `text`/`textarea(label, placeholder)`, `number(label, placeholder)` — placeholder is a
  gray hint only; the weak model can't reliably tell prefill from hint, so model-generated
  `defaultValue` is intentionally NOT produced (it kept landing as content). Real prefill of
  the user's prior answer is deferred to a deterministic app-side step.
- `slider`/`rangeSlider(label, minValue, maxValue)`
- `yesNo`/`singleSelect`/`multiSelect`/`orderedList(label, options)`
- `hierarchicalList(label, items: [GenTreeItem{label, depth}])` → mapped to `prefillRows`
- `itemTable(label, columns: [GenFieldOption])` where `option.description` carries the column type

**Type selection — reasoning first.** `GenActionSchema` decodes `typeReasoning` before `field`,
so the model commits to a reasoned choice (chain-of-thought) rather than an afterthought.

**Behavior — lean instructions + `@Guide`.** Per-type "when to use" guidance lives on the
`typeReasoning` guide; placeholder/defaultValue/options/column-typing rules live in the
instructions. Kept small to fit the window.

**Reliability — what's guaranteed vs best-effort.**
- *Guaranteed (structural):* valid form, exactly one field, payload always consistent with the
  type, all properties available, never a broken/empty control for a known type.
- *Best-effort (model judgment):* picking the single most apt type. Reasoning-first maximizes
  this; the user's existing **"Change input type"** control is the human fallback for misses.
  On a 3B model this is the honest ceiling — we do not silently override the model's choice.
- *Failure fallback:* if guided generation can't decode at all, a deterministic single field is
  produced from the title so the step is never blocked.

## 4. Out of scope on-device (documented gaps)

- `drawing` AI description (no image input) — sketch is still saved/embedded.
- `itemTable` pre-filled rows (only columns are generated; the user fills the table).
- `defaultValue` prefill of text/textarea from the user's prior answers — the on-device
  model conflated it with the placeholder hint, so it's not model-generated; a future
  deterministic app-side prefill can fill it from the actual previous response.
- Per-call exact token counts in the Console use a ~4 chars/token approximation until the
  toolchain ships Apple's `SystemLanguageModel.tokenCount` (26.4 SDK).
