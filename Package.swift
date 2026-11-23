// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppPresence",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AppPresence", path: "Sources/AppPresence")
    ]
)
