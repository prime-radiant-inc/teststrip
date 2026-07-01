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
            dependencies: ["TeststripCore"]
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
        )
    ]
)
