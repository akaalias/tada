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
        case .extractAudit: return try await extractAudit(input)
        case .extractAuditGated: return try await extractAudit(input, minBaseTasks: 2)
        }
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
