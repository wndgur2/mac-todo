// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Todo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Todo",
            path: "Sources/Todo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
