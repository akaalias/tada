import Foundation
import FoundationModels
import Contract
import EvalBench
import SplitAgent

// CLI: availability | inspect "<input>" | gold | evaluate
//   [--agent <name>] [--subset dev] [--limit N] [--label <s>] [--note <s>]
let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "availability"

func stringFlag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func intFlag(_ name: String) -> Int? {
    guard let s = stringFlag(name) else { return nil }
    return Int(s)
}

let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let goldDir = packageDir.appendingPathComponent("gold")
let resultsDir = packageDir.appendingPathComponent("results")

func selectedAgent() -> (name: String, fn: RambleAgentFn) {
    let name = stringFlag("--agent") ?? "baseline"
    // Ceiling check: Sonnet as the CANDIDATE (via the gold generator), to bound
    // how high the on-device number could go under the same gold/judge/metric.
    if name.hasPrefix("cloud_") {
        guard let client = try? AnthropicClient() else {
            FileHandle.standardError.write(Data("cloud agent needs ANTHROPIC_API_KEY\n".utf8)); exit(2)
        }
        let gen = GoldGenerator(client: client)
        return (name, { try await gen.generate($0) })
    }
    guard let config = Configs.named(name) else {
        FileHandle.standardError.write(Data("unknown agent '\(name)'. known: \(Configs.registry.keys.sorted().joined(separator: ", "))\n".utf8))
        exit(2)
    }
    let agent = ConfiguredAgent(config)
    return (name, { try await agent.generate($0) })
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
    let result = try await a.fn(input)
    print("tasks (\(result.tasks.count)):")
    for t in result.tasks { print("  - \(t)") }

case "gold":
    guard let client = try? AnthropicClient() else {
        FileHandle.standardError.write(Data("gold generation needs ANTHROPIC_API_KEY\n".utf8)); exit(2)
    }
    let gen = GoldGenerator(client: client)
    var cases: [GoldCase] = []
    for inp in RambleInputs.all {
        let g = try await gen.generate(inp.input)
        print("• \(inp.id) [\(inp.kind)] -> \(g.tasks.count) tasks")
        for t in g.tasks { print("    - \(t)") }
        cases.append(GoldCase(id: inp.id, input: inp.input, gold: g))
    }
    try GoldStore.save(cases, to: goldDir)
    print("wrote \(cases.count) gold cases to gold/")

case "evaluate":
    guard let all = try? GoldStore.load(from: goldDir), !all.isEmpty else {
        FileHandle.standardError.write(Data("no gold/ found — run `swift run fmramble gold` first\n".utf8)); exit(2)
    }
    // Default to the DEV optimization gate; TEST is held out for honesty; FULL = all.
    let subsetArg = stringFlag("--subset") ?? "dev"
    let subset = (subsetArg == "test" || subsetArg == "full") ? subsetArg : "dev"
    var cases: [GoldCase]
    switch subset {
    case "test": cases = all.filter { RambleInputs.isTest($0.id) }
    case "full": cases = all
    default:     cases = all.filter { !RambleInputs.isTest($0.id) }   // dev
    }
    if let limit = intFlag("--limit") { cases = Array(cases.prefix(limit)) }

    let judge: Judge
    if let client = try? AnthropicClient() {
        judge = AnthropicJudge(client: client)
    } else {
        judge = StubJudge()
        print("note: ANTHROPIC_API_KEY not set — StubJudge (rubric diagnostics not real; F1 still real)")
    }

    let agent = selectedAgent()
    print("agent: \(agent.name)  subset: \(subset)  cases: \(cases.count)")
    let runner = Runner(judge: judge)
    let metric = await runner.run(agent.fn, over: cases) { print($0) }
    print(metric.summary)

    print("\n── judge notes (candidate weaknesses) ──")
    for s in metric.scores where s.verdict != nil {
        print("• \(s.id): \(s.verdict!.notes)")
    }

    // Persist full results + append one line to the run log (with kept threshold).
    try? FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
    let label = stringFlag("--label") ?? "latest"
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    if let data = try? enc.encode(metric.scores) {
        try? data.write(to: resultsDir.appendingPathComponent("\(label).json"))
        print("\nwrote results/\(label).json")
    }

    let runsURL = resultsDir.appendingPathComponent("runs.jsonl")
    let prior = (try? String(contentsOf: runsURL, encoding: .utf8))?
        .split(separator: "\n")
        .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? []
    let bestBefore = prior.filter { ($0["subset"] as? String) == subset && ($0["invalid"] as? Bool != true) }
        .compactMap { $0["quality"] as? Double }.max() ?? -1
    let rm = metric.rubricMeans
    let record: [String: Any] = [
        "index": prior.count, "label": label, "agent": agent.name,
        "note": stringFlag("--note") ?? "", "subset": subset, "n": cases.count,
        "quality": metric.quality, "precision": metric.precision, "recall": metric.recall,
        "f1": metric.f1, "zeroTaskAccuracy": metric.zeroTaskAccuracy, "specPass": metric.specPassRate,
        "faithfulness": rm.faithfulness, "atomicity": rm.atomicity, "actionability": rm.actionability,
        "coverage": rm.coverage, "nonRedundancy": rm.nonRedundancy,
        "kept": metric.quality > bestBefore,
    ]
    if let line = try? JSONSerialization.data(withJSONObject: record),
       let s = String(data: line, encoding: .utf8) {
        let existing = (try? String(contentsOf: runsURL, encoding: .utf8)) ?? ""
        try? (existing + s + "\n").write(to: runsURL, atomically: true, encoding: .utf8)
        print("logged run #\(prior.count) to results/runs.jsonl  (kept: \(metric.quality > bestBefore))")
    }

default:
    print("usage: fmramble [availability | inspect \"<input>\" | gold | evaluate] [--agent <name>] [--subset dev] [--limit N] [--label <s>]")
}
