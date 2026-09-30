// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        // 工具链坑（W2 评审移交⑤）：包只声明 iOS/watchOS；在 macOS 宿主直接 `swift test`
        // 会因 SharedStore 的 OSAllocatedUnfairLock（需 macOS 13+，而包未声明 macOS 平台）
        // 编译失败。刻意不加 .macOS（未测试面不声明）——测试/DoD 路径是 xcodebuild
        // （scheme PawIt，iOS Simulator destination）。
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        // GRDB：SQLite 工具库，D2「零丢数据」存储基础（DatabasePool 自动 WAL）。
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
