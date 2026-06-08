import Foundation
import FoundationModels
import Contract

/// The single mutable artifact: a ramble-split agent driven entirely by a
/// SplitConfig. Topology, decoding, and (later) retrieval / post-processing are
/// all config. New experiments add named configs in Configs.swift.
public struct ConfiguredAgent: Sendable {
    let config: SplitConfig
    public init(_ config: SplitConfig) { self.config = config }

    public func generate(_ input: String) async throws -> RambleResult {
        switch config.topology {
        case .singleShot: return try await singleShot(input)
        case .singleShotReasoned: return try await singleShotReasoned(input)
        case .singleShotCoverage: return try await singleShotCoverage(input)
        case .singleShotCoveragePhrased: return try await singleShotCoveragePhrased(input)
        case .singleShotCoverageRestyle: return try await singleShotCoverageRestyle(input)
        case .singleShotCoverageRestyleGuarded: return try await singleShotCoverageRestyleGuarded(input)
        case .extractAudit: return try await extractAudit(input)
        case .extractAuditGated: return try await extractAudit(input, minBaseTasks: 2)
        case .extractAuditSweep: return try await extractAuditSweep(input, minBaseTasks: 2)
        case .overGenerateFilter: return try await overGenerateFilter(input)
        }
    }

    /// exp006: OVER-GENERATE -> FILTER. exp004's only residual is a hedged task
    /// ("call the insurance company about that claim") buried mid-ramble in a long
    /// many-task input that the PRECISE base extraction glosses over — and which
    /// even exp005's audit sweep missed (it grabbed the wrong "someday" garage and
    /// over-split elsewhere). The exp005 log concluded the fix must come EARLIER in
    /// the pipeline, not in a louder audit. So:
    ///   Call 1 (over-generate): an exhaustive candidate sweep, gated by the proven
    ///     hasActionableTasks zero-task gate. It deliberately OVER-lists — it grabs
    ///     the buried insurance call, but also the "someday/not urgent" garage and any
    ///     split/paraphrase variants. Precision is intentionally sacrificed here.
    ///   Call 2 (filter): sees the input + the candidate list and returns the FINAL
    ///     list, keeping ONLY candidates the user genuinely commits to (dropping ones
    ///     flagged as someday / not urgent / vague wish / retracted) and MERGING
    ///     duplicate or split variants of the same intention. This is where precision
    ///     is recovered — directly distinguishing the kept insurance call from the
    ///     dropped garage, the failure exp005 could not separate.
    /// Single-candidate (simple) inputs skip the filter and keep the precise path, so
    /// the 8-9 already-perfect short cases are not put at risk.
    private func overGenerateFilter(_ input: String) async throws -> RambleResult {
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.coverage }
        let prompt = """
        Here is what the user brain-dumped:

        "\(input)"

        First analyze what is and isn't actionable and decide whether any real task remains. Then sweep the whole input and list every distinct intention you find, even ones buried mid-sentence or returned to after a digression. Be exhaustive — over-list rather than miss something. Then give your best merged list (it will be filtered next).
        """
        let over = try await session.respond(
            to: prompt,
            generating: FMRambleSplitCoverage.self,
            options: config.options()
        )
        // Zero-task gate (proven, generalizes): nothing actionable -> empty, no filter.
        guard over.content.hasActionableTasks else { return RambleResult(tasks: []) }

        // The exhaustive candidate pool: prefer the over-listed candidateIntentions
        // (that is where buried/hedged items survive); fall back to the merged tasks.
        let candidates = over.content.candidateIntentions.isEmpty
            ? over.content.tasks
            : over.content.candidateIntentions
        let cleaned = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Simple inputs (0-1 candidate) skip the filter and keep the precise path.
        guard cleaned.count >= 2 else { return RambleResult(tasks: cleaned) }

        let listed = cleaned.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let filterSession = LanguageModelSession(model: try resolveModel()) { Prompts.filter }
        let filterPrompt = """
        The user brain-dumped:

        "\(input)"

        A first pass over-generated this candidate list (it may include things the user did NOT really commit to, and may list the same intention more than once):
        \(listed)

        Return the FINAL task list: keep only candidates the user genuinely commits to doing, drop the ones they flagged as someday / not urgent / a vague wish / retracted, and merge any duplicates or split variants of the same intention into ONE task.
        """
        let r = try await filterSession.respond(
            to: filterPrompt,
            generating: FMRambleFilter.self,
            options: config.options()
        )
        // Deterministic dedup safety net only (no base list to merge against).
        return RambleResult(tasks: mergeDedup([], r.content.finalTasks))
    }

    /// exp005: like extractAuditGated, but the audit ENUMERATES every action in the
    /// input (hedged ones included) before diffing against the committed list. The
    /// forced sweep targets exp004's only residual: a softly-hedged task buried among
    /// digressions in a long many-task ramble that a single read-and-diff drops.
    private func extractAuditSweep(_ input: String, minBaseTasks: Int) async throws -> RambleResult {
        let base = try await singleShotReasoned(input)
        guard base.tasks.count >= minBaseTasks, !base.tasks.isEmpty else { return base }

        let listed = base.tasks.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.auditSweep }
        let prompt = """
        The user brain-dumped:

        "\(input)"

        Tasks already extracted from it:
        \(listed)

        First list EVERY action in the input (allActions), then return ONLY the ones MISSING from the list above (missingTasks). Return an empty missingTasks list if the list already covers everything.
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleAuditSweep.self,
            options: config.options()
        )
        return RambleResult(tasks: mergeDedup(base.tasks, r.content.missingTasks))
    }

    /// Two-call EXTRACT -> COVERAGE-AUDIT. Call 1 is the proven exp001 reasoned
    /// extraction (precision 1.0). Call 2 runs ONLY when call 1 found >=1 task —
    /// this protects the solved zero-task gate (we never let the audit invent a
    /// task on venting/musing). The auditor sees the committed list, so unlike
    /// exp002's blind over-generate it won't re-add a paraphrase. Recovers buried
    /// / prerequisite tasks (the entire residual recall gap in exp001).
    /// `minBaseTasks` gates the audit to contexts where it pays off. exp003 showed
    /// the audit recovers buried/prereq tasks on MULTI-task inputs (interleaved_deck
    /// 0.8->1.0, multi_errands 0.8->1.0) but over-fires on SINGLE-task inputs,
    /// re-emitting a paraphrase of the lone task (dedup_groceries, mixed_weekend each
    /// gained a spurious dup). Requiring base.count >= 2 keeps the recall wins while
    /// skipping the single-task cases the audit can only hurt. (exp003 used 1.)
    private func extractAudit(_ input: String, minBaseTasks: Int = 1) async throws -> RambleResult {
        let base = try await singleShotReasoned(input)
        // Zero-task gate already decided there is nothing to do — do not audit.
        // Also skip below the multi-task threshold: a coverage audit can only add
        // duplicates on a single-task input, never recover a genuinely missing one.
        guard base.tasks.count >= minBaseTasks, !base.tasks.isEmpty else { return base }

        let listed = base.tasks.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.audit }
        let prompt = """
        The user brain-dumped:

        "\(input)"

        Tasks already extracted from it:
        \(listed)

        List ONLY distinct actionable tasks that are stated in the input but MISSING from the list above. Return an empty list if the list already covers everything.
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleAudit.self,
            options: config.options()
        )
        return RambleResult(tasks: mergeDedup(base.tasks, r.content.missingTasks))
    }

    /// Append audited additions to the base list, dropping any that normalize to
    /// an item already present (cheap safety net against exact/near duplicates;
    /// the auditor is the primary dedup, this just guarantees no leak).
    private func mergeDedup(_ base: [String], _ additions: [String]) -> [String] {
        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                .filter { !$0.isPunctuation }
        }
        var seen = Set(base.map(norm))
        var out = base
        for a in additions {
            let trimmed = a.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = norm(a)
            if seen.insert(key).inserted { out.append(trimmed) }
        }
        return out
    }

    /// exp009: exp008's DECOUPLED restyle pass, hardened against the failure that sank
    /// exp008 — a FREE "restore the meaningful detail" rewrite let the model HALLUCINATE
    /// plausible-but-absent specifics ("Sarah", "3 PM", "milk supplier"), so the 1:1 count
    /// guard preserved cardinality but semantic drift WITHIN a slot still broke F1
    /// (0.963->0.870). The exp008 log's prescribed fix: the rewrite may ONLY recase /
    /// re-tense / re-attach detail that is VERBATIM present in the input or the base task —
    /// no free generation. This is enforced deterministically with a per-task TOKEN-SUBSET
    /// guard: a restyled task is accepted only if every CONTENT word in it stems to a word
    /// present in (input ∪ that base task); a small function-word allowlist (the/a/to/for/
    /// with/and...) is free so the model can add conversational glue. Any restyled task that
    /// introduces a novel content word is REJECTED and the slot falls back to the base task.
    /// EITHER way the slot is then deterministically capitalized, so the output is never an
    /// all-lowercase fragment even when a restyle is rejected. Set membership is identical to
    /// exp002 by construction (1:1 by index), so F1 is protected; only phrasing can move.
    private func singleShotCoverageRestyleGuarded(_ input: String) async throws -> RambleResult {
        let base = try await singleShotCoverage(input)
        guard !base.tasks.isEmpty else { return base }

        let listed = base.tasks.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.restyle }
        let prompt = """
        The user's original brain-dump:

        "\(input)"

        Tasks extracted from it (rewrite each one, same order, same set):
        \(listed)

        Return the styled list: exactly one rewritten task per task above, in the same order, each a complete capitalized one-liner that keeps the meaningful detail.
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleRestyle.self,
            options: config.options()
        )
        let styled = r.content.styled.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // 1:1 mapping guard (same as exp008): any count mismatch -> keep the base set,
        // but still recased so the phrasing rubric is not stuck at all-lowercase.
        guard styled.count == base.tasks.count else {
            return RambleResult(tasks: base.tasks.map(capitalizeFirst))
        }
        let inputVocab = vocab(input)
        let merged = zip(base.tasks, styled).map { original, restyled -> String in
            // Accept the restyle ONLY if it adds no new content word (anti-hallucination).
            // Allowed source = the original input PLUS this task's own words.
            let allowed = inputVocab.union(vocab(original))
            if !restyled.isEmpty && contentTokensSubset(restyled, of: allowed) {
                return capitalizeFirst(restyled)
            }
            return capitalizeFirst(original)
        }
        return RambleResult(tasks: merged)
    }

    /// Function/glue words a restyle may introduce freely (they carry no task content,
    /// only conversational/grammatical completeness — capital + verb + natural phrasing).
    private static let freeWords: Set<String> = [
        "a", "an", "the", "to", "for", "with", "and", "or", "of", "on", "in", "at",
        "by", "about", "regarding", "re", "your", "my", "our", "their", "his", "her",
        "its", "that", "this", "these", "those", "it", "them", "up", "out", "off",
        "into", "from", "as", "so", "then", "back", "over", "before", "after", "is",
        "are", "be", "get", "make", "do", "have"
    ]

    /// Lowercased alphanumeric tokens of a string.
    private func vocab(_ s: String) -> Set<String> {
        Set(tokenize(s))
    }

    private func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Light suffix stemmer so tense/number changes (call/calling, truck/trucks,
    /// reschedule/rescheduling) don't falsely trip the guard.
    private func stem(_ t: String) -> String {
        for suffix in ["ing", "ed", "es", "s", "d"] {
            if t.count > suffix.count + 2, t.hasSuffix(suffix) {
                return String(t.dropLast(suffix.count))
            }
        }
        return t
    }

    /// True iff every CONTENT token of `phrase` (non-free words) stems to a token
    /// present (by stem) in `allowed`. Free function words are always permitted.
    private func contentTokensSubset(_ phrase: String, of allowed: Set<String>) -> Bool {
        let allowedStems = Set(allowed.map(stem))
        for tok in tokenize(phrase) {
            if Self.freeWords.contains(tok) { continue }
            let s = stem(tok)
            if allowedStems.contains(s) { continue }
            // Tolerate short prefix overlaps (e.g. rescheduling vs reschedule).
            if allowedStems.contains(where: { $0.hasPrefix(s) || s.hasPrefix($0) }) && s.count >= 4 { continue }
            return false
        }
        return true
    }

    /// Capitalize the first alphabetic character; leave the rest untouched.
    private func capitalizeFirst(_ s: String) -> String {
        guard let idx = s.firstIndex(where: { $0.isLetter }) else { return s }
        return String(s[..<idx]) + s[idx].uppercased() + String(s[s.index(after: idx)...])
    }

    /// exp008: exp002 base (singleShotCoverage) UNCHANGED, then a DECOUPLED style-only
    /// rewrite pass. exp007 proved the phrasing contract works in isolation (rubric
    /// phrasing 2->4) but bundling it into the SAME extraction call poisoned recall
    /// (F1 0.963->0.829 — the heavier prompt shifted the greedy decode and the model
    /// spent capacity styling instead of extracting). The exp007 log's prescribed fix:
    /// apply phrasing as a style-only rewrite PASS over the already-extracted list,
    /// which cannot change set membership. Call 1 is the proven exp002 extractor. Call 2
    /// sees the input + the extracted tasks and rewrites EACH into Sonnet's capitalized,
    /// complete style, restoring dropped detail. A deterministic 1:1 guard (styled.count
    /// must equal base.count, mapped by index, empty styled slots fall back to base)
    /// guarantees the set of tasks is IDENTICAL to exp002 — so F1 is protected by
    /// construction and only the phrasing rubric can move. Empty base -> no rewrite
    /// (protects the solved zero-task gate).
    private func singleShotCoverageRestyle(_ input: String) async throws -> RambleResult {
        let base = try await singleShotCoverage(input)
        guard !base.tasks.isEmpty else { return base }

        let listed = base.tasks.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.restyle }
        let prompt = """
        The user's original brain-dump:

        "\(input)"

        Tasks extracted from it (rewrite each one, same order, same set):
        \(listed)

        Return the styled list: exactly one rewritten task per task above, in the same order, each a complete capitalized one-liner that keeps the meaningful detail.
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleRestyle.self,
            options: config.options()
        )
        // Deterministic 1:1 guard: the styled list must mirror the base set exactly.
        // Any count mismatch -> keep the base list (F1 can never regress vs exp002).
        let styled = r.content.styled.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard styled.count == base.tasks.count else { return base }
        // Map by index; an empty styled slot falls back to the original task.
        let merged = zip(base.tasks, styled).map { original, restyled in
            restyled.isEmpty ? original : restyled
        }
        return RambleResult(tasks: merged)
    }

    /// exp007: singleShotCoverage + a PHRASING contract. Identical topology to the
    /// current best (exp002), but the prompt and the final-tasks schema guide add an
    /// explicit STYLE rule — capitalized, complete, conversational one-liners that
    /// keep meaningful detail (purpose / recipient / subject / deadline) while dropping
    /// vague filler timing. Targets the dominant unsaturated gap: phrasing 2/5 across
    /// every prior config (terse all-lowercase fragments). F1 should be unchanged.
    private func singleShotCoveragePhrased(_ input: String) async throws -> RambleResult {
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.coveragePhrased }
        let prompt = """
        Here is what the user brain-dumped:

        "\(input)"

        First analyze what is and isn't actionable and decide whether any real task remains. Then sweep the whole input and list every distinct intention you find, even ones buried mid-sentence or returned to after a digression. Finally write the merged final list, phrasing each task as a complete, capitalized, natural one-liner that keeps the meaningful detail (empty if none).
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleSplitCoveragePhrased.self,
            options: config.options()
        )
        return r.content.toContract()
    }

    private func singleShotCoverage(_ input: String) async throws -> RambleResult {
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.coverage }
        let prompt = """
        Here is what the user brain-dumped:

        "\(input)"

        First analyze what is and isn't actionable and decide whether any real task remains. Then sweep the whole input and list every distinct intention you find, even ones buried mid-sentence or returned to after a digression. Finally merge duplicates into the final task list (empty if none).
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleSplitCoverage.self,
            options: config.options()
        )
        return r.content.toContract()
    }

    private func singleShotReasoned(_ input: String) async throws -> RambleResult {
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.reasoned }
        let prompt = """
        Here is what the user brain-dumped:

        "\(input)"

        First analyze what is and isn't actionable, decide whether any real task remains, then list the tasks (empty if none).
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleSplitReasoned.self,
            options: config.options()
        )
        return r.content.toContract()
    }

    private func singleShot(_ input: String) async throws -> RambleResult {
        let session = LanguageModelSession(model: try resolveModel()) { Prompts.singleShot }
        let prompt = """
        Here is what the user brain-dumped:

        "\(input)"

        Extract each distinct, actionable task as a short one-liner. If there are none, return an empty list.
        """
        let r = try await session.respond(
            to: prompt,
            generating: FMRambleSplit.self,
            options: config.options()
        )
        return r.content.toContract()
    }

    private func resolveModel() throws -> SystemLanguageModel {
        // Apple's default guardrails over-trigger on benign input (code, mixed-language,
        // blunt phrasing), causing false refusals on ordinary rambles. Use permissive
        // content transformations so the splitter sees the real input.
        let guardrails = SystemLanguageModel.Guardrails.permissiveContentTransformations
        guard let path = config.adapter else {
            return SystemLanguageModel(guardrails: guardrails)
        }
        let adapter = try SystemLanguageModel.Adapter(fileURL: URL(filePath: path))
        return SystemLanguageModel(adapter: adapter, guardrails: guardrails)
    }
}
