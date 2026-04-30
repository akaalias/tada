// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tada",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tada", targets: ["Tada"])
    ],
    targets: [
        .executableTarget(
            name: "Tada",
            path: "Sources"
        )
    ]
)
