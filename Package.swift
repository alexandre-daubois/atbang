// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Atbang",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "AtbangCore"),
        .executableTarget(name: "Atbang", dependencies: ["AtbangCore"]),
        .testTarget(name: "AtbangCoreTests", dependencies: ["AtbangCore"]),
    ]
)
