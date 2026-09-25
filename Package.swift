// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lowlight",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "Lowlight",
            path: "Sources/Lowlight",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
