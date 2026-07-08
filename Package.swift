// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "gitkun",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // kuntraykun 連携・更新チェック・共通ユーティリティ（ProcessRunner / SelfUpdater 等）の共有ライブラリ。
        .package(url: "https://github.com/m-tkg/kunkit.git", from: "1.3.0")
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
                .product(name: "KunSupport", package: "kunkit"),
                .product(name: "KunAppKit", package: "kunkit"),
            ]
        ),
        .testTarget(
            name: "gitkunCoreTests",
            dependencies: ["gitkunCore"]
        ),
    ]
)
