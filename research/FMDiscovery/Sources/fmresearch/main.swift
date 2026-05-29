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
    if let limit { cases = Array(cases.prefix(limit)) }

    let judge: Judge
    if let client = try? AnthropicClient() {
        judge = AnthropicJudge(client: client)
    } else {
        judge = StubJudge()
        print("note: ANTHROPIC_API_KEY not set — using StubJudge (no real scores)")
    }

    let agent = BaselineAgent()
    let runner = Runner(judge: judge)
    let metric = await runner.run({ try await agent.generate($0) }, over: cases) { print($0) }
    print(metric.summary)

case "inspect":
    let input = args.count > 2 ? args[2] : "Plan a trip to Paris"
    let result = try await BaselineAgent().generate(input)
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
