// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlacklevelRemote",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BlacklevelRemote", path: "Sources/BlacklevelRemote")
    ]
)
