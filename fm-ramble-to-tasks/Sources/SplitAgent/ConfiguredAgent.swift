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
        }
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
