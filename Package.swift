// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScrcpyGUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScrcpyGUI",
            path: "Sources/ScrcpyGUI"
        )
    ]
)
