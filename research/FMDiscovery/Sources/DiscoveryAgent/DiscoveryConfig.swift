import Foundation
import FoundationModels

/// The search space. Every field is a lever the autoresearch loop can change.
/// One experiment = one DiscoveryConfig (a config delta from the running best).
public struct DiscoveryConfig: Sendable {
    public enum Topology: String, Sendable {
        case singleShot          // 1 call → 7 questions
        case brainstormSelect    // call1: list unknowns → call2: select+phrase 7
        case overGenerateScore   // 1 call → 12 scored candidates → Swift picks top 7
        case ragFewShot          // retrieve 2 nearest gold exemplars → inject as few-shot → 1 call
        case ragCoverageBestOfN  // sample N RAG sets at varying temps → pick best by Swift coverage scorer
        case ragCritiqueRevise   // RAG draft → 2nd FM auditor revises for coverage, drops given/redundant
        case ragCoverageScaffold // RAG few-shot + explicit task-conditioned coverage checklist (dims from nearest exemplars), 1 call
        case ragFewShotSemantic  // ragFewShot but exemplars retrieved by on-device NLEmbedding cosine, not word overlap
        case ragAdaptExemplar    // adapt the nearest exemplar's 7 concrete gold questions one-to-one to the new task
        case ragCoverageRepair   // exp003 draft, then deterministically (embeddings) replace the most-redundant slot with the least-covered concrete gold unknown
        case ragSelfConsistency  // N independent RAG sets → embedding-cluster all questions → keep the 7 with broadest cross-sample agreement
        case ragContrastiveFewShot // exp003 positive few-shot + a fixed GOOD-vs-BAD contrastive lesson teaching the anti-patterns to avoid, 1 call
        case ragTournament       // N RAG sets at varying temps → single-elimination PAIRWISE 3B tournament (two-order voting) → return the winning set verbatim
        case ragPlanAssumptions  // stage1: draft a concrete plan + surface the assumptions it forced → stage2: turn those assumed unknowns into 7 RAG-phrased questions
        case ragCorpusFewShot    // RAG few-shot drawn from the 100+ corpus bank (semantic retrieval, k=3) + the exp011 contrastive lesson, 1 call
        case ragDimensionalSchema // single call, but output schema is 7 typed per-dimension slots (goal/scope/who-for/budget/timeline/current-state/constraints) so guided generation STRUCTURALLY enforces coverage breadth
        case ragSequential       // generate questions ONE AT A TIME, each conditioned on the already-asked set (forced-novelty pushes generation off the modal generic cluster into the task-specific tail)
        case ragFillerRepair     // contrastive RAG draft → deterministically detect wasted slots (filler phrases + Jaccard near-dupes) → one scoped call refills only those with concrete task-specific questions
        case ragReasonedFewShot  // single call, but the output schema forces in-schema chain-of-thought: list the 7 decision-critical unknowns FIRST (anchored by a reasoning demo), then write one question per unknown
    }

    public enum Sampling: Sendable {
        case greedy
        case topP(Double)
        case topK(Int)
        case modelDefault

        var mode: GenerationOptions.SamplingMode? {
            switch self {
            case .greedy: return .greedy
            case .topP(let p): return .random(probabilityThreshold: p)
            case .topK(let k): return .random(top: k)
            case .modelDefault: return nil
            }
        }
    }

    public var topology: Topology
    // Decoding (lever 2), per stage.
    public var brainstormTemp: Double?
    public var brainstormSampling: Sampling
    public var selectTemp: Double?
    public var selectSampling: Sampling
    public var maxTokens: Int?
    // best-of-N: per-sample temperatures (each yields one full set; Swift scores+selects).
    public var sampleTemps: [Double]?

    public init(
        topology: Topology,
        brainstormTemp: Double? = nil, brainstormSampling: Sampling = .modelDefault,
        selectTemp: Double? = nil, selectSampling: Sampling = .modelDefault,
        maxTokens: Int? = nil,
        sampleTemps: [Double]? = nil
    ) {
        self.topology = topology
        self.brainstormTemp = brainstormTemp
        self.brainstormSampling = brainstormSampling
        self.selectTemp = selectTemp
        self.selectSampling = selectSampling
        self.maxTokens = maxTokens
        self.sampleTemps = sampleTemps
    }

    func options(temp: Double?, sampling: Sampling) -> GenerationOptions {
        GenerationOptions(sampling: sampling.mode, temperature: temp, maximumResponseTokens: maxTokens)
    }
}
