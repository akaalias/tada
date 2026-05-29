// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FMDiscovery",
    platforms: [.macOS(.v26)],
    targets: [
        // Output contract shared by the agent (producer) and bench (judge).
        .target(name: "Contract"),

        // Immutable harness: gold cases, spec gate, judge, metric, runner.
        .target(name: "EvalBench", dependencies: ["Contract"]),

        // Mutable artifact: the FM-based discovery agent we iterate on.
        .target(name: "DiscoveryAgent", dependencies: ["Contract"]),

        // CLI entry point.
        .executableTarget(
            name: "fmresearch",
            dependencies: ["Contract", "EvalBench", "DiscoveryAgent"],
            path: "Sources/fmresearch"
        ),

        .testTarget(name: "EvalBenchTests", dependencies: ["EvalBench", "Contract"]),
    ]
)
