import Foundation
import FoundationModels

/// The search space. Every field is a lever the autoresearch loop can change.
/// One experiment = one SplitConfig (a delta from the running best).
public struct SplitConfig: Sendable {
    public enum Topology: String, Sendable {
        case singleShot          // 1 call: input -> 0..N tasks
        case singleShotReasoned  // 1 call: reasoning-first gated schema -> 0..N tasks
        // Future experiments add: segmentExtract, overGenerateFilter,
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
