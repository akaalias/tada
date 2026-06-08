// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RambleSplit",
    platforms: [.macOS(.v26)],
    targets: [
        // Output contract shared by the agent (producer) and bench (judge).
        .target(name: "Contract"),

        // Immutable harness: gold, judge, set-match metric, runner, spec gate.
        .target(name: "EvalBench", dependencies: ["Contract"]),

        // Mutable artifact: the FM-based ramble-split agent we iterate on.
        .target(name: "SplitAgent", dependencies: ["Contract"]),

        // CLI entry point.
        .executableTarget(
            name: "fmramble",
            dependencies: ["Contract", "EvalBench", "SplitAgent"],
            path: "Sources/fmramble"
        ),
    ]
)
