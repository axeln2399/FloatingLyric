// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingLyric",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FloatingLyricCore"),
        .executableTarget(name: "FloatingLyric", dependencies: ["FloatingLyricCore"]),
        .testTarget(name: "FloatingLyricCoreTests", dependencies: ["FloatingLyricCore"]),
    ]
)
