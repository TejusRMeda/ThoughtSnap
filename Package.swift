// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThoughtSnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ThoughtSnap", targets: ["ThoughtSnap"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/stephencelis/SQLite.swift",
            from: "0.15.3"
        ),
        .package(
            url: "https://github.com/soffes/HotKey",
            from: "0.2.0"
        ),
        .package(
            url: "https://github.com/apple/swift-markdown",
            from: "0.3.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ThoughtSnap",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/ThoughtSnap",
            resources: [
                // Assets.xcassets lives inside the target source tree
                .process("Resources/Assets.xcassets"),
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-reflection-metadata"])
            ],
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
            ]
        ),
        .testTarget(
            name: "ThoughtSnapTests",
            dependencies: ["ThoughtSnap"],
            path: "Tests/ThoughtSnapTests"
        )
    ]
)
