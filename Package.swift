// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JKBMS",
    defaultLocalization: "zh",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "JKBMSCore", targets: ["JKBMSCore"]),
        .executable(name: "JKBMSApp", targets: ["JKBMSApp"])
    ],
    targets: [
        .target(
            name: "JKBMSCore",
            path: "Sources/JKBMSCore",
            resources: [.copy("Resources/original")]
        ),
        .executableTarget(
            name: "JKBMSApp",
            dependencies: ["JKBMSCore"],
            path: "Sources/JKBMSApp"
        ),
        .testTarget(
            name: "JKBMSCoreTests",
            dependencies: ["JKBMSCore"],
            path: "Tests/JKBMSCoreTests"
        )
    ]
)
