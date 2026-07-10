// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Teststrip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TeststripCore", targets: ["TeststripCore"]),
        .executable(name: "TeststripApp", targets: ["TeststripApp"]),
        .executable(name: "TeststripWorker", targets: ["TeststripWorker"]),
        .executable(name: "TeststripBench", targets: ["TeststripBench"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", "2.6.0"..<"3.0.0")
    ],
    targets: [
        .target(
            name: "TeststripCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TeststripWorker",
            dependencies: ["TeststripCore"]
        ),
        .executableTarget(
            name: "TeststripApp",
            dependencies: [
                "TeststripCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "TeststripBench",
            dependencies: ["TeststripCore"]
        ),
        .testTarget(
            name: "TeststripCoreTests",
            dependencies: ["TeststripCore"]
        ),
        .testTarget(
            name: "TeststripWorkerTests",
            dependencies: ["TeststripCore", "TeststripWorker"]
        ),
        .testTarget(
            name: "TeststripAppTests",
            dependencies: ["TeststripCore", "TeststripApp"]
        ),
        .testTarget(
            name: "TeststripBenchTests",
            dependencies: ["TeststripBench"]
        )
    ]
)
