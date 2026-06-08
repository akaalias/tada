import Foundation
import FoundationModels

/// Locations of the bundled on-device discovery assets (folder reference
/// `OnDeviceModels/` inside the app's Resources).
enum OnDeviceAssets {
    private static var baseURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("OnDeviceModels", isDirectory: true)
    }

    /// The champion LoRA adapter (`discovery_v2a_e1.fmadapter`). nil if absent.
    static var adapterURL: URL? {
        guard let url = baseURL?.appendingPathComponent("discovery_v2a_e1.fmadapter", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The corpus directory used as the external coverage prior. nil if absent.
    static var corpusURL: URL? {
        guard let url = baseURL?.appendingPathComponent("corpus", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

/// On-device discovery-question generation: the FMDiscovery champion (exp056,
/// `adapterCorpusCoverageSelect`, quality 0.440 vs Sonnet gold) ported into the
/// app. One greedy call on the fine-tuned LoRA adapter over-generates 8 questions
/// in its native voice, then a deterministic, corpus-coverage-grounded step drops
/// the one whose removal least reduces coverage of the axes Sonnet probes for
/// similar tasks — yielding 7. Everything here is on-device; the result maps
/// straight onto the planner's `TaskPlan` contract.
struct OnDeviceDiscoveryService {

    /// System prompt for the adapter. MUST byte-match the training data's system
    /// content (format_training_data.py) — the adapter learned this exact format.
    static let adapterSystem =
        "A conversation between a user and a helpful assistant. "
        + "Taking the role of a personal task coach. Given a task the user wants to accomplish, "
        + "generate clarifying questions that uncover what they specifically want, the context "
        + "(who/what/when/where/why), constraints and preferences, and key execution details. "
        + "Restate the user's goal as a short specific title (4-9 words), never a generic label. "
        + "Summarise the task in one sentence. Each question is complete, 5-10 words, asks ONE "
        + "thing (never combine with \"and\"/\"or\"), specific to THIS task, addressed to the user, "
        + "no emojis. Produce exactly 7 questions."

    /// True when the system language model is ready AND the adapter is bundled.
    /// Callers use this to decide whether to take the on-device path at all.
    static var isAvailable: Bool {
        guard OnDeviceAssets.adapterURL != nil else { return false }
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
    }

    /// Generate the discovery plan on-device. Throws if the model/adapter is
    /// unavailable or generation fails — callers fall back to the cloud planner.
    func generateDiscoveryQuestions(for task: String) async throws -> TaskPlan {
        guard let adapterURL = OnDeviceAssets.adapterURL else {
            throw OnDeviceDiscoveryError.adapterUnavailable
        }
        let adapter = try SystemLanguageModel.Adapter(fileURL: adapterURL)
        let model = SystemLanguageModel(adapter: adapter)
        let session = LanguageModelSession(model: model) { Self.adapterSystem }

        let prompt = "Task the user entered: \"\(task)\""
        let plan = try await session.respond(
            to: prompt,
            generating: FMDiscoveryPlan8.self,
            includeSchemaInPrompt: false,
            options: GenerationOptions(sampling: .greedy, temperature: 0)
        ).content

        let kept = Self.selectSeven(
            plan.questions,
            input: task,
            titleVecs: SemanticRetrieval.vectors(for: plan.questions.map { $0.question })
        )
        return TaskPlan(
            title: plan.title,
            description: plan.summary,
            subTasks: kept.map {
                SubTaskPlan(title: $0.question, description: $0.detail,
                            requiresExternalAction: $0.requiresExternalAction)
            }
        )
    }

    /// EXP-056 corpus-coverage selection, extracted as a pure function so it can be
    /// tested without the on-device model. From an over-generated set (>7), drop the
    /// ONE question whose removal best PRESERVES coverage of the external corpus axes
    /// (the questions Sonnet asks for the nearest task types); ties → drop the more
    /// internally redundant one. Floors: ≤7 → unchanged; embeddings or corpus axes
    /// unavailable → keep the first 7 (≈ the champion's native first-7 draft).
    static func selectSeven(_ questions: [FMQuestion], input: String,
                            titleVecs: [[Double]]?) -> [FMQuestion] {
        guard questions.count > 7 else { return questions }
        let axisStrings = DiscoveryCorpusBank
            .nearestSemantic(to: input, k: 3, jaccardCeiling: 0.5)
            .flatMap { $0.questions }
        let axisVecs = axisStrings.isEmpty ? nil : SemanticRetrieval.vectors(for: axisStrings)
        return dropToSeven(questions, titleVecs: titleVecs, axisVecs: axisVecs)
    }

    /// Pure corpus-coverage drop math, with the corpus axes injected so it can be
    /// tested without the on-device model or the bundled corpus. From >7 questions,
    /// drop the one whose removal best preserves coverage of `axisVecs`; ties → drop
    /// the more internally redundant. Floors: ≤7 unchanged; missing vectors → first 7.
    static func dropToSeven(_ questions: [FMQuestion],
                            titleVecs: [[Double]]?, axisVecs: [[Double]]?) -> [FMQuestion] {
        guard questions.count > 7 else { return questions }
        guard let tv = titleVecs, let av = axisVecs, !av.isEmpty, tv.count == questions.count else {
            return Array(questions.prefix(7))
        }

        // coverage(kept) = Σ over corpus axes of the max cosine to any kept candidate.
        func coverage(excluding d: Int) -> Double {
            var total = 0.0
            for a in av {
                var best = -1.0
                for i in 0..<tv.count where i != d {
                    let c = SemanticRetrieval.cos(tv[i], a)
                    if c > best { best = c }
                }
                total += best
            }
            return total
        }
        // Internal redundancy of candidate d = aggregate cosine to the others.
        func internalRedundancy(_ d: Int) -> Double {
            var s = 0.0
            for i in 0..<tv.count where i != d { s += SemanticRetrieval.cos(tv[d], tv[i]) }
            return s
        }

        var dropIdx = questions.count - 1
        var bestCov = -Double.infinity
        var bestRed = -Double.infinity
        for d in 0..<questions.count {
            let cov = coverage(excluding: d)
            let red = internalRedundancy(d)
            if cov > bestCov + 1e-9 || (abs(cov - bestCov) <= 1e-9 && red > bestRed) {
                bestCov = cov; bestRed = red; dropIdx = d
            }
        }
        var kept = questions
        kept.remove(at: dropIdx)
        if kept.count > 7 { kept = Array(kept.prefix(7)) }
        return kept
    }
}

enum OnDeviceDiscoveryError: Error {
    case adapterUnavailable
}

// MARK: - Guided-generation types

/// Over-generates 8 questions in the adapter's native voice, so the deterministic
/// corpus-coverage step can drop one redundant slot and keep 7 — all native voice,
/// no foreign-source specificity tax.
@Generable
struct FMDiscoveryPlan8 {
    @Guide(description: "The user's task restated as a short specific title, 4-9 words, in their own words. Never a generic label like 'Clarifying Questions'.")
    var title: String
    @Guide(description: "One plain sentence summarising the task.")
    var summary: String
    @Guide(description: "Exactly 8 clarifying questions.", .count(8))
    var questions: [FMQuestion]
}

@Generable
struct FMQuestion {
    @Guide(description: "A complete clarifying question, 5-10 words, asking exactly ONE thing. Never combine two asks with 'and' or 'or'. Addressed to the user ('you'/'your').")
    var question: String
    @Guide(description: "Optional short extra context. May be empty.")
    var detail: String
    @Guide(description: "True only if answering requires a real-world action outside the app (call, email, visit). False for in-app data entry.")
    var requiresExternalAction: Bool
}
