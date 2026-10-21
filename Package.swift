// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Codexy",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CodexyCore"),
        .executableTarget(name: "CodexyUsage", dependencies: ["CodexyCore"], resources: [.copy("skins")]),
        .testTarget(name: "CodexyCoreTests", dependencies: ["CodexyCore"]),
    ]
)
