import Foundation
import FoundationModels
import Contract
import SplitAgent

// CLI: availability | inspect "<input>" [--agent <name>]
let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "availability"

func stringFlag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func selectedAgent() -> (name: String, agent: ConfiguredAgent) {
    let name = stringFlag("--agent") ?? "baseline"
    guard let config = Configs.named(name) else {
        FileHandle.standardError.write(Data("unknown agent '\(name)'. known: \(Configs.registry.keys.sorted().joined(separator: ", "))\n".utf8))
        exit(2)
    }
    return (name, ConfiguredAgent(config))
}

switch command {
case "availability":
    switch SystemLanguageModel.default.availability {
    case .available: print("FM AVAILABLE")
    case .unavailable(let reason): print("FM UNAVAILABLE: \(String(describing: reason))")
    }

case "inspect":
    let input = (args.count > 2 && !args[2].hasPrefix("--"))
        ? args[2]
        : "Okay so yeah let me think. I want to review the 2024 tax document with Franziska. I got to talk to her about August. And I should probably bring out the trash."
    let a = selectedAgent()
    print("agent: \(a.name)")
    print("input: \(input)")
    let result = try await a.agent.generate(input)
    print("tasks (\(result.tasks.count)):")
    for t in result.tasks { print("  - \(t)") }

default:
    print("usage: fmramble [availability | inspect \"<input>\"] [--agent <name>]")
}
