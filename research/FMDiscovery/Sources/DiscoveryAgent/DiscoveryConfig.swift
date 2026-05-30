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
        case ragCorpusSelect     // over-generate a diverse candidate pool (N temps), then SELECT 7 by embedding resemblance to the questions Sonnet actually asks for the nearest corpus task types (corpus as a relevance prior, output stays 3B-generated)
        case ragPerspectiveEnsemble // generate full sets from 3 DISTINCT generation FRAMES (execution / scope / domain-expert) — prompt-diversity, not temp-diversity — then deterministically round-robin-merge by emission order with near-dup suppression (no 3B selection pass)
        case ragJustifiedQuestions // single call, INTERLEAVED per-question CoT: schema forces a concrete decision-impact rationale immediately BEFORE each question (vs exp018's batch-first list), gating filler at the point of emission
        case ragStartingPointCritique // contrastive RAG draft → ONE scoped 2nd call judging only ONE failure mode (does any slot establish the user's STARTING POINT?) → if not, swap the single weakest slot in Swift for a task-specific starting-point question (≤1 slot changes, 6 verbatim)
        case ragGivensAware      // single call, in-schema: FIRST extract the facts the task already states (providedFacts — an EASY reading task, not judgment), THEN write 7 questions, none of which may re-ask a given; frees slots wasted on restating givens
        case ragCompositeBestOfN // best-of-N over the exp011 contrastive-RAG generator, selected by a COMPOSITE deterministic ruler (coverage span − filler − near-dup − compound/atomicity penalties), low-temp floor — fixes exp004's coverage-only scorer flaw, no 3B judgment
        case ragAntiModalContrast // stage1: greedy (most-modal=most-generic) draft; stage2: generate FRESH questions told to SURPASS that self-draft — a DIRECTED, task-specific push off the model's own modal cluster (vs exp011's fixed neutral anchor, exp024's undirected temperature)
        case adapterDirect       // single call on a fine-tuned LoRA adapter, schema-free guided generation (system+user match the training format; includeSchemaInPrompt:false)
        case adapterScopedCritique // adapterDirect draft (champion) → ONE scoped starting-point critique ON THE ADAPTER → swap ≤1 redundant/weak slot for a task-specific starting-point question
        case adapterDivergeConverge // stage1: UNCONSTRAINED free-text brainstorm on the adapter (no schema) of the decision-critical unknowns for THIS task → stage2: native-format adapter call converges that prose into the 7 questions
        case adapterSolutionSpaceEIG // stage1: generate N DIVERGENT concrete candidate scenarios (competing interpretations of who/what the user wants) on the adapter → stage2: native-format adapter call writes the 7 questions that best DISCRIMINATE which scenario the user is in (solution-space information gain, ICLR'25)
        case adapterDispersionBestOfN // greedy champion draft + N low-temp adapter samples → SELECT the whole set (verbatim) maximising embedding coverage-VOLUME (pairwise dispersion = least internal redundancy) + on-task relevance, deterministic in Swift; no FM judging pass
        case adapterRagFewShot   // champion adapter, native training format, with 2 retrieved gold exemplar question-sets APPENDED as reference demonstrations (which decision-critical unknowns similar tasks cover) — single greedy call, no extra judgment pass
        case adapterRagFewShotLOO // adapterRagFewShot but LEAVE-ONE-OUT: exclude any exemplar whose input matches the eval task, so demonstrations are genuinely OTHER tasks (the non-leaking, valid version of exp032)
        case adapterCoverageFacilitySelect // over-generate a POOL of INDIVIDUAL questions across adapter draws (greedy champion + low-temp), dedup, then greedily pick 7 maximising a facility-location / max-sum dispersion objective (relevance + min-distance to chosen) VERBATIM — the literal Lever D over individual questions (exp031 selected whole sets only)
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
    // Absolute path to a trained .fmadapter; nil = stock base model. (lever 7)
    public var adapter: String?

    public init(
        topology: Topology,
        brainstormTemp: Double? = nil, brainstormSampling: Sampling = .modelDefault,
        selectTemp: Double? = nil, selectSampling: Sampling = .modelDefault,
        maxTokens: Int? = nil,
        sampleTemps: [Double]? = nil,
        adapter: String? = nil
    ) {
        self.topology = topology
        self.brainstormTemp = brainstormTemp
        self.brainstormSampling = brainstormSampling
        self.selectTemp = selectTemp
        self.selectSampling = selectSampling
        self.maxTokens = maxTokens
        self.sampleTemps = sampleTemps
        self.adapter = adapter
    }

    func options(temp: Double?, sampling: Sampling) -> GenerationOptions {
        GenerationOptions(sampling: sampling.mode, temperature: temp, maximumResponseTokens: maxTokens)
    }
}
