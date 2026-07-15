// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OoopsMediaPress",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "OoopsMediaPress", targets: ["OoopsMediaPress"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "OoopsMediaPress",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/OoopsMediaPress",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "OoopsMediaPressTests",
            dependencies: ["OoopsMediaPress"],
            path: "Tests/OoopsMediaPressTests"
        )
    ]
)
