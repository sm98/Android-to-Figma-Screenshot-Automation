// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenshotSync",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenshotSync",
            path: "Sources/ScreenshotSync"
        )
    ]
)
