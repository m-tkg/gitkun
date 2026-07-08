// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "gitkun",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // kuntraykun 連携と更新チェック（ETag 条件付き取得）の共有ライブラリ。
        .package(url: "https://github.com/m-tkg/kunkit.git", from: "1.1.0")
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit/Combine/UserNotifications に依存しないモデル・計算
        .target(
            name: "gitkunCore"
        ),
        // 実行ファイル本体: メニューバー常駐・ポーリング・通知・設定UI
        .executableTarget(
            name: "gitkun",
            dependencies: [
                "gitkunCore",
                .product(name: "KunIntegrationBridge", package: "kunkit"),
                .product(name: "KunUpdateKit", package: "kunkit"),
            ]
        ),
        .testTarget(
            name: "gitkunCoreTests",
            dependencies: ["gitkunCore"]
        ),
    ]
)
