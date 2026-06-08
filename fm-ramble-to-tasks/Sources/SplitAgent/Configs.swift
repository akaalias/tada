import Foundation

/// The experiment registry — the mutable lever space the autoresearch loop edits.
/// One named entry = one experiment (a SplitConfig).
public enum Configs {
    public static let registry: [String: SplitConfig] = [
        "baseline": SplitConfig(topology: .singleShot, sampling: .greedy),
        // exp001: reasoning-first gated schema (analysis + hasActionableTasks gate)
        // to suppress invented tasks on venting/musing and honor retractions.
        "exp001": SplitConfig(topology: .singleShotReasoned, sampling: .greedy),
        // exp002: coverage-first — same gate, plus an exhaustive candidateIntentions
        // sweep before the final list, to recover tasks missed on interleaved
        // many-task rambles (the residual recall/coverage gap in exp001).
        "exp002": SplitConfig(topology: .singleShotCoverage, sampling: .greedy),
        // exp003: extract->coverage-audit. exp001 reasoned extract (precision 1.0),
        // then a scoped second call that sees the committed list and adds ONLY
        // genuinely-missing stated tasks. Audit skipped on zero-task (protects the
        // solved gate). Targets exp001's pure recall gap without exp002's dedup leak.
        "exp003": SplitConfig(topology: .extractAudit, sampling: .greedy),
        // exp004: extractAudit GATED to multi-task contexts. Same recovery audit as
        // exp003, but it only fires when the base extraction found >=2 tasks. exp003's
        // only regressions were two SINGLE-task cases where the audit re-added a
        // paraphrase dup; gating to base.count>=2 keeps the multi-task recall wins
        // (interleaved_deck, multi_errands -> 1.0) without that single-task cost.
        "exp004": SplitConfig(topology: .extractAuditGated, sampling: .greedy),
        // exp005: extractAuditGated, but the gated audit ENUMERATES every action in
        // the input (soft/hedged ones included) before diffing against the committed
        // list. exp004's only residual was long_monday (0.909): a softly-hedged task
        // buried among digressions that both base AND single-read audit dropped. The
        // forced enumerate-then-diff sweep aims to surface it without precision cost.
        "exp005": SplitConfig(topology: .extractAuditSweep, sampling: .greedy),
        // exp006: OVER-GENERATE -> FILTER. exp004's only residual (long_monday) is a
        // hedged task buried mid-ramble that the precise base drops and even exp005's
        // audit sweep missed (grabbing the wrong "someday" garage). Per the exp005
        // log, the fix must be EARLIER: call 1 over-lists exhaustively (grabbing the
        // insurance call AND the someday-garage and split-dups), then call 2 filters
        // to only genuinely-committed candidates and merges duplicates — separating
        // the kept softly-hedged action from the dropped explicit deferral.
        "exp006": SplitConfig(topology: .overGenerateFilter, sampling: .greedy),
        // exp007: build on the current best (exp002 singleShotCoverage). Same gate +
        // exhaustive-sweep topology, but add an explicit PHRASING/STYLE contract to the
        // prompt and the final-tasks schema guide. The dominant unsaturated gap is
        // phrasing (every config scores 2/5: terse all-lowercase fragments that drop
        // meaningful detail). The contract asks for capitalized, complete, conversational
        // one-liners that keep purpose/recipient/subject/deadline while trimming vague
        // filler timing — aiming to lift the rubric's phrasing without touching F1.
        "exp007": SplitConfig(topology: .singleShotCoveragePhrased, sampling: .greedy),
        // exp008: build on the current best (exp002 singleShotCoverage), UNCHANGED, then
        // add a DECOUPLED style-only rewrite pass. exp007 proved phrasing is a real lever
        // (rubric phrasing 2->4 in isolation) but bundling it into the extraction call
        // poisoned recall (F1 0.963->0.829). The exp007 log's prescribed fix: apply
        // phrasing as a style-only rewrite PASS over the already-extracted list, which
        // cannot change set membership. Call 1 = exp002 extractor; call 2 rewrites each
        // task 1:1 into Sonnet's capitalized/complete style, restoring dropped detail. A
        // deterministic count/order guard keeps the task SET identical -> F1 protected by
        // construction; only the phrasing rubric can move.
        "exp008": SplitConfig(topology: .singleShotCoverageRestyle, sampling: .greedy),
        // exp009: build on exp002 + exp008's DECOUPLED restyle pass, but HARDEN it against
        // the hallucination that sank exp008 (free "restore detail" rewrite invented absent
        // specifics -> F1 0.963->0.870 despite the 1:1 count guard). Per the exp008 log, the
        // rewrite may ONLY recase / re-tense / re-attach detail VERBATIM-present in the input
        // or base task. Enforced deterministically: a per-task TOKEN-SUBSET guard rejects any
        // restyled task that introduces a content word not stemming to a word in (input ∪ base
        // task) — a small function-word allowlist is free for conversational glue. Rejected
        // slots fall back to the base task; EITHER way the slot is deterministically
        // capitalized, so output is never all-lowercase. Set membership identical to exp002 by
        // construction -> F1 cannot regress; only the phrasing rubric can move.
        "exp009": SplitConfig(topology: .singleShotCoverageRestyleGuarded, sampling: .greedy),
        // exp010: build on exp009 (current best, guarded restyle). Attacks the two residuals
        // the exp009 log named — COMPLETENESS and PROPER-NOUN CASING — without touching F1.
        // (1) The restyle prompt+schema now demand the model restore dropped detail (deadline/
        // subject/recipient/location) using the user's EXACT words, so the fuller rewrite stays
        // inside exp009's token-subset guard instead of being rejected back to a terse fragment
        // (the over-suppression the log flagged). (2) A deterministic proper-noun re-casing pass
        // recases task tokens to the input's mid-sentence capitalization ("dana's" -> "Dana's").
        // 1:1 index mapping + subset guard unchanged -> set membership identical to exp002, F1
        // protected by construction; only the phrasing rubric can move.
        "exp010": SplitConfig(topology: .singleShotCoverageRestyleVerbatim, sampling: .greedy),
    ]

    public static func named(_ name: String) -> SplitConfig? { registry[name] }
}
