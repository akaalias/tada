# Apple Foundation Model — on-device internals & extensibility

Reference notes from a read-only investigation (2026-06-01, macOS 26 / Apple Silicon)
into where the on-device Foundation Model lives, how it's gated, and whether a
**customized base model** can be loaded. Context: the FMDiscovery project is
capacity-bound on the ~3B base, so the question is whether the base itself can be
replaced/edited rather than only adapted with LoRA.

TL;DR — **No supported (or practically achievable) path to a custom base model.**
The only sanctioned knob is a LoRA `.fmadapter`, version-locked to Apple's base.
A private base-selection SPI exists but is triple-gated (SPI + an un-grantable Apple
entitlement + an undocumented signed/quantized asset format). Distribution channel
(App Store vs Developer ID) is irrelevant to the gate.

---

## 1. Where the model lives (two copies)

### Inference copy — what the app actually calls (sealed)
- Path: `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels/`
  - Flagged **`restricted`** (SIP); cannot even be listed (`ls` → "Operation not permitted").
  - On the **Signed System Volume (SSV)** — cryptographically sealed; any change breaks
    the seal and boot.
- Related assets: `…UAF_FM_Overrides`, `…UAF_FM_CodeLM`, `…UAF_FM_Visual`.
- Served **out of process** by daemons, reached via XPC:
  - `/usr/libexec/modelmanagerd` (catalog + lifecycle)
  - inference extensions: `BlackPowderInferenceExtension`, `TGOnDeviceInferenceProviderService`
- The app's address space never holds the weights.

### Training copy — Apple's adapter toolkit (present, in the clear)
`research/FMDiscovery/adapter_training_toolkit_v26_0_0/assets/`:
| file | size | what |
|---|---|---|
| `base-model.pt` | **12.7 GB** | full base weights, fp32 PyTorch, `load_state_dict(strict=True)` |
| `base-model-config.json` | 315 B | `__tamm_type__: models:AFMTextV7Config`, LoRA `rank 32 / alpha 16`, `KVQuantArchOptimizer` |
| `draft-model.pt` / `draft.mil` | 195 MB / 8 MB | speculative-decoding draft model |
| `tokenizer.model` | 2.7 MB | tokenizer |
| `checkpoint_spec.yaml` | 29 KB | full layer spec |

- Model identity: **AFM-Text v7** (Apple Foundation Model, text, version 7).
- `examples/utils.py:load_base_model` loads the full base, then **freezes everything
  except `adapter` params** (`requires_grad = "adapter" in name`) → toolkit is LoRA-only
  by default, though the full base is technically trainable if you unfreeze it.
- The training base is fp32; the on-device build is KV-quantized + ANE-compiled. The
  toolkit has **no base-export path** — it only emits `.fmadapter`.

### The adapter format (the one editable surface)
`adapter/exports/*.fmadapter/` is just two files:
- `metadata.json` — e.g. `{ "loraRank": 32, "baseModelSignature": "9799725ff8…",
  "speculativeDecodingDraftTokenCount": 5, "author": "3P developer" }`
- `adapter_weights.bin` — ~133 MB at rank 32.
- `baseModelSignature` **version-locks** the adapter to a specific base build.

---

## 2. FoundationModels Swift API surface

Source of truth (readable): the SDK textual interface
`…/MacOSX.sdk/System/Library/Frameworks/FoundationModels.framework/Versions/A/Modules/FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface`
Binary symbols (incl. private): `dyld_info -exports … | xcrun swift-demangle`.

### `SystemLanguageModel` (the model handle)
- `@_hasMissingDesignatedInitializers` — designated inits are hidden.
- Public: `static let default`; `init(useCase:guardrails:)`; `init(adapter:guardrails:)`;
  `availability`, `isAvailable`, `supportedLanguages`, `supportsLocale(_:)`.
- `UseCase` is a **closed set**: `.general`, `.contentTagging`. No custom-model field.
- `Guardrails`: `.default`, `.permissiveContentTransformations`.
- `Availability.UnavailableReason`: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`.

### `SystemLanguageModel.Adapter` (the ONLY behavior-injection point)
- `init(fileURL: URL) throws` — load a `.fmadapter` from disk (what FMDiscovery uses).
- `init(name: String) throws` — load a named adapter from the catalog / BackgroundAssets.
- `compile() async throws`, `isCompiled`
- `static compatibleAdapterIdentifiers(name:)`, `static removeObsoleteAdapters()`,
  `static isCompatible(_: BackgroundAssets.AssetPack)`, `creatorDefinedMetadata`.
- `AssetError`: `.invalidAsset`, `.invalidAdapterName`, `.compatibleAdapterNotFound`.

### `LanguageModelSession`
- `respond(...)` / `streamResponse(...)` (String, `GenerationSchema`, or typed `Generable`).
- `Response.usedDraftModel: Bool` (speculative-decoding telemetry).
- `GenerationOptions` / `SamplingMode` (temperature, top-p, greedy), `Tool`, `Transcript`,
  `Generable` / `GenerationSchema`, `GenerationGuide`.

Nothing public accepts weights, a model URL, an architecture, or a base identifier.

---

## 3. The hidden base-selection SPI

The binary has **four** `SystemLanguageModel` initializers. Three correspond to the
public ones; one is **SPI, absent from the public interface**:

```swift
SystemLanguageModel.init(modelCatalogAssetBundleID: String,
                         modelManagerUseCaseID: String,
                         guardrails: Guardrails)
```
(mangled: `…SystemLanguageModelC25modelCatalogAssetBundleID0f14ManagerUseCaseJ010guardrails…`)

This is the *real* base-selection mechanism: it asks `modelmanagerd` to serve a specific
**model-catalog asset bundle** by ID under a use-case ID — i.e. how Apple's own features
pick different model variants. It lines up with:
- catalog root: `/var/db/com.apple.modelcatalog/` (has `tokenStore/`)
- **`/var/db/com.apple.modelcatalog/sideload/{assets,resources}`** — root-owned, empty by
  default. Note: on `/var` (writable **data** volume), NOT the sealed SSV.

So the plumbing for swappable/sideloaded base assets exists.

---

## 4. The gates (from `modelmanagerd` strings)

`modelmanagerd` enforces **per-client entitlements** (`"Client %d missing entitlement %s"`,
`verifiedEntitlements`). Relevant entitlements:

| entitlement | grants | third-party? |
|---|---|---|
| `com.apple.developer.foundation-model-adapter` | load **LoRA adapters** | ✅ public (the documented one) |
| `com.apple.modelmanager.loadBundle` | load a model asset **bundle** (the base) | ❌ Apple-only |
| `com.apple.modelmanager.inference` / `.query` / `.inferenceprovider[.safety]` | run/serve inference | ❌ Apple-only |
| `com.apple.modelmanager.forceAssetVersionSwitch` | switch asset versions | ❌ Apple-only |

Other notes from strings:
- `ModelCatalogAssetVersionLocking` — assets are version-locked (matches `baseModelSignature`).
- Fallback/test path: `"falling back to test assets"`, `"builtin test assets"`,
  `CallbackToEchoFallbackModelBundleID` (an echo stub).
- modelmanagerd's own security check is **entitlement-based** (`verifiedEntitlements`); it does
  not appear to re-verify an asset signature at load time — asset integrity is enforced
  **upstream** (signed MobileAsset install + SIP-restricted placement in `AssetsV2`).

### How macOS gates restricted entitlements (the key mechanism)
- Restricted `com.apple.*` entitlements are honored only via an **Apple-issued provisioning
  profile** or **Apple platform code-signing**, enforced by **AMFI** at process launch.
- Apple does not issue `com.apple.modelmanager.loadBundle` in any third-party profile
  (App Store, Developer ID, TestFlight, Enterprise). A Developer ID cert cannot self-assert it.
- **⇒ Distribution channel is irrelevant.** Not shipping via the App Store changes nothing.

---

## 5. Can we load a customized base model?

**No viable path.** Layered analysis:

1. **Channel (App Store → Developer ID): no effect.** The gate is the Apple-only entitlement
   + AMFI, not store policy.
2. **Defeat the entitlement on your own machine: possible but only a research config.**
   Disable SIP + AMFI (`csrutil disable`, boot-arg `amfi_get_out_of_my_way=1`). Then a
   self/ad-hoc-signed binary can carry `com.apple.modelmanager.loadBundle`, and
   modelmanagerd's `verifiedEntitlements` check (reads the entitlement off the signature)
   would pass. This unlocks the *call*, not the capability.
3. **The real walls (unchanged by #2):**
   - **Producing a loadable base asset.** The inference provider needs Apple's runtime format
     (KV-quantized, ANE-compiled `.mil` + weights + manifest, version-locked). The public
     toolkit can't emit a base — only LoRA. Building one = reverse-engineering Apple's
     quantization + ANE compilation + packaging, from license-restricted weights. This is the
     actual moat.
   - **Distribution.** A product requiring users to disable SIP+AMFI is not shippable,
     notarizable, or safe. Lab-only.
   - (The `/var` sideload dir means you would NOT need to break SSV to *register* an asset —
     but that doesn't help without a producible asset.)

### Practical implication for the project
- On-device, the **only** sanctioned key is the LoRA `.fmadapter` already in use. The base is
  immutable by design.
- To *test* "does a bigger/custom base clear the coverage notch?", skip modelmanagerd entirely:
  run the 12.7 GB base (or a larger model) in your own MLX/PyTorch harness against the same
  frozen ruler. Measures the hypothesis directly; just can't ship on-device — the same
  constraint the report's verdict already names.
- One untried in-bounds model lever remains: **higher LoRA rank** (currently 32) — cheap,
  fully sanctioned; capacity argument predicts it won't move coverage, but it's a clean
  final capacity check.

### Licensing / ethics
- `base-model.pt` is provided to **produce `.fmadapter` files for Apple's runtime**; using it
  in a custom runtime almost certainly violates Apple's license.
- All findings above are from read-only inspection of one's own machine (SDK interface,
  `dyld_info`/`swift-demangle` symbol tables, `strings` on system binaries). No SIP/AMFI bypass
  was performed.

---

## Repro commands
```sh
# public API surface
SI=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/FoundationModels.framework/Versions/A/Modules/FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface
grep -nE "public (struct|class|enum|func|init)" "$SI"

# hidden initializers (note the modelCatalogAssetBundleID SPI)
for s in $(dyld_info -exports /System/Library/Frameworks/FoundationModels.framework/FoundationModels | awk '{print $NF}' | grep -E '19SystemLanguageModelC.*fC$'); do xcrun swift-demangle "$s"; done | sort -u

# entitlement gates
strings -a /usr/libexec/modelmanagerd | grep -iE "entitlement|loadBundle|modelmanager\.|sideload|test asset"

# base model location (restricted) + writable sideload catalog
ls -lO /System/Library/AssetsV2/ | grep -i generativemodels
ls -laR /var/db/com.apple.modelcatalog/sideload
```
