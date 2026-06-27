// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "gitkun",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit/Combine/UserNotifications に依存しないモデル・計算
        .target(
            name: "gitkunCore"
        ),
        // 実行ファイル本体: メニューバー常駐・ポーリング・通知・設定UI
        .executableTarget(
            name: "gitkun",
            dependencies: ["gitkunCore"]
        ),
        .testTarget(
            name: "gitkunCoreTests",
            dependencies: ["gitkunCore"]
        ),
    ]
)
