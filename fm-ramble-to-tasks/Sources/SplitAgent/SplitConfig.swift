import Foundation
import FoundationModels

/// The search space. Every field is a lever the autoresearch loop can change.
/// One experiment = one SplitConfig (a delta from the running best).
public struct SplitConfig: Sendable {
    public enum Topology: String, Sendable {
        case singleShot          // 1 call: input -> 0..N tasks
        case singleShotReasoned  // 1 call: reasoning-first gated schema -> 0..N tasks
        case singleShotCoverage  // 1 call: reasoned gate + exhaustive candidate sweep -> 0..N tasks
        case singleShotCoveragePhrased // singleShotCoverage + explicit phrasing/style contract (exp007)
        case singleShotCoverageRestyle // exp002 base + a DECOUPLED 1:1 style-only rewrite pass (exp008)
        case singleShotCoverageRestyleGuarded // exp008 restyle + per-task token-subset anti-hallucination guard (exp009)
        case singleShotCoverageRestyleVerbatim // exp009 guard + verbatim-detail restyle + deterministic proper-noun recasing (exp010)
        case extractAudit        // 2 calls: reasoned extract, then coverage-audit adds missing tasks
        case extractAuditGated   // extractAudit, but audit ONLY fires when base found >=2 tasks
        case extractAuditSweep   // extractAuditGated, but audit enumerates-then-diffs (exp005)
        case overGenerateFilter  // 2 calls: exhaustive over-generate, then commitment+dedup filter (exp006)
        // Future experiments add: segmentExtract,
        // brainstormSelect, extractCritique, adapterDirect, ...
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
    public var temp: Double?
    public var sampling: Sampling
    public var maxTokens: Int?
    // Absolute path to a trained .fmadapter; nil = stock base model.
    public var adapter: String?

    public init(
        topology: Topology,
        temp: Double? = nil,
        sampling: Sampling = .modelDefault,
        maxTokens: Int? = nil,
        adapter: String? = nil
    ) {
        self.topology = topology
        self.temp = temp
        self.sampling = sampling
        self.maxTokens = maxTokens
        self.adapter = adapter
    }

    func options() -> GenerationOptions {
        GenerationOptions(sampling: sampling.mode, temperature: temp, maximumResponseTokens: maxTokens)
    }
}
