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
