// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IconForge",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "IconForge", path: "Sources/IconForge")]
)
