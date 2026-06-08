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
        }
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
        guard let path = config.adapter else { return SystemLanguageModel.default }
        let adapter = try SystemLanguageModel.Adapter(fileURL: URL(filePath: path))
        return SystemLanguageModel(adapter: adapter)
    }
}
