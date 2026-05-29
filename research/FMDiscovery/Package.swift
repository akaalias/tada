// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FMDiscovery",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "fmresearch",
            path: "Sources/fmresearch"
        )
    ]
)
