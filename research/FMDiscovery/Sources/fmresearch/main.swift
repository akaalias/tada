import Foundation
import FoundationModels
import Contract
import EvalBench
import DiscoveryAgent

// CLI: availability | evaluate [--limit N] | gold
let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "availability"

func intFlag(_ name: String) -> Int? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return Int(args[i + 1])
}

let packageDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let goldDir = packageDir.appendingPathComponent("gold")

func stringFlag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func selectedAgent() -> (name: String, fn: DiscoveryAgentFn) {
    let name = stringFlag("--agent") ?? "baseline"
    guard let config = Configs.named(name) else {
        FileHandle.standardError.write(Data("unknown agent '\(name)'. known: \(Configs.registry.keys.sorted().joined(separator: ", "))\n".utf8))
        exit(2)
    }
    let agent = ConfiguredAgent(config)
    return (name, { try await agent.generate($0) })
}

switch command {
case "availability":
    if #available(macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available: print("FM AVAILABLE")
        case .unavailable(let reason): print("FM UNAVAILABLE: \(String(describing: reason))")
        }
    } else { print("FM UNAVAILABLE: requires macOS 26+") }

case "evaluate":
    let limit = intFlag("--limit")
    // Load gold if present, else synthesise placeholder cases from the input
    // set so the pipeline can dry-run before gold exists.
    var cases: [GoldCase]
    if FileManager.default.fileExists(atPath: goldDir.path),
       let loaded = try? GoldStore.load(from: goldDir), !loaded.isEmpty {
        cases = loaded
        print("loaded \(cases.count) gold cases from gold/")
    } else {
        cases = DiscoveryInputs.all.map {
            GoldCase(id: $0.id, input: $0.input,
                     gold: DiscoveryResult(taskTitle: $0.input, taskDescription: "", questions: []))
        }
        print("no gold/ found — using \(cases.count) placeholder cases (stub judge only)")
    }
    if stringFlag("--subset") == "dev" {
        cases = cases.filter { DiscoveryInputs.devSubsetIDs.contains($0.id) }
        print("dev subset: \(cases.count) cases")
    }
    if let limit { cases = Array(cases.prefix(limit)) }

    let judge: Judge
    if let client = try? AnthropicClient() {
        judge = AnthropicJudge(client: client)
    } else {
        judge = StubJudge()
        print("note: ANTHROPIC_API_KEY not set — using StubJudge (no real scores)")
    }

    let agent = selectedAgent()
    print("agent: \(agent.name)")
    let runner = Runner(judge: judge)
    let metric = await runner.run(agent.fn, over: cases) { print($0) }
    print(metric.summary)

    // Judge notes — the signal for the next hypothesis.
    print("\n── judge notes (candidate weaknesses) ──")
    for s in metric.scores where s.verdict != nil {
        print("• \(s.id) [\(s.verdict!.pairwise.rawValue), rubric \(String(format: "%.1f", s.verdict!.rubric.mean))]: \(s.verdict!.notes)")
    }

    // Persist full results for offline analysis.
    let label = args.firstIndex(of: "--label").map { args[$0 + 1] } ?? "latest"
    let resultsDir = packageDir.appendingPathComponent("results")
    try? FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    if let data = try? enc.encode(metric.scores) {
        try? data.write(to: resultsDir.appendingPathComponent("\(label).json"))
        print("\nwrote results/\(label).json")
    }

    // Append one line per experiment to the dashboard run log.
    let runsURL = resultsDir.appendingPathComponent("runs.jsonl")
    let prior = (try? String(contentsOf: runsURL, encoding: .utf8))?
        .split(separator: "\n")
        .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? []
    let subset = stringFlag("--subset") == "dev" ? "dev" : "full"
    // Running best is per-subset: dev runs only compare to dev runs. Invalid runs
    // (e.g. gold-leak artifacts flagged by the operator) are excluded so they can't
    // poison the kept-threshold for legitimate future runs.
    let bestBefore = prior.filter { ($0["subset"] as? String) == subset && ($0["invalid"] as? Bool != true) }
        .compactMap { $0["quality"] as? Double }.max() ?? -1
    let rm = metric.rubricMeans
    let record: [String: Any] = [
        "index": prior.count, "label": label, "agent": agent.name,
        "note": stringFlag("--note") ?? "", "subset": subset, "n": cases.count,
        "quality": metric.quality, "specPass": metric.specPassRate,
        "wins": metric.wins, "ties": metric.ties, "losses": metric.losses,
        "atomicity": rm.atomicity, "specificity": rm.specificity, "coverage": rm.coverage,
        "naturalness": rm.naturalness, "nonRedundancy": rm.nonRedundancy,
        "kept": metric.quality > bestBefore,
    ]
    if let line = try? JSONSerialization.data(withJSONObject: record),
       let s = String(data: line, encoding: .utf8) {
        let existing = (try? String(contentsOf: runsURL, encoding: .utf8)) ?? ""
        try? (existing + s + "\n").write(to: runsURL, atomically: true, encoding: .utf8)
        print("logged run #\(prior.count) to results/runs.jsonl")
    }

case "inspect":
    let input = args.count > 2 ? args[2] : "Plan a trip to Paris"
    let agent = selectedAgent()
    print("agent: \(agent.name)")
    let result = try await agent.fn(input)
    print("TITLE: \(result.taskTitle)")
    print("DESC:  \(result.taskDescription)")
    for (i, q) in result.questions.enumerated() {
        print("  \(i + 1). \(q.title)\(q.requiresExternalAction ? "  [external]" : "")")
        if !q.description.isEmpty { print("      \(q.description)") }
    }
    print(SpecGate.check(result).passed ? "spec: PASS" : "spec: FAIL \(SpecGate.check(result).violations)")

case "gold":
    let limit = intFlag("--limit")
    let client = try AnthropicClient()
    let gen = GoldGenerator(client: client)
    var inputs = DiscoveryInputs.all
    if let limit { inputs = Array(inputs.prefix(limit)) }
    var cases: [GoldCase] = []
    for item in inputs {
        print("• gold for \(item.id): \"\(item.input)\"")
        let gold = try await gen.generate(item.input)
        let spec = SpecGate.check(gold)
        if !spec.passed { print("    WARNING spec: \(spec.violations.joined(separator: "; "))") }
        cases.append(GoldCase(id: item.id, input: item.input, gold: gold))
    }
    try GoldStore.save(cases, to: goldDir)
    print("wrote \(cases.count) gold cases to \(goldDir.path)")

default:
    print("usage: fmresearch [availability|evaluate [--limit N]|gold]")
}
