import AppKit
import gitkunCore
import Combine
import KunIntegrationBridge
import OSLog

private let logger = Logger(subsystem: logSubsystem, category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    let appState = AppState()
    private var cancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?
    private var menuExportCancellable: AnyCancellable?
    var settingsWindow: NSWindow?
    private var kuntraykunBridge: KuntraykunBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarImage(named: "MenuBarIcon")
        KuntraykunIconExport.export(statusItem.button?.image)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // kuntraykun 連携（kunkit）: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        // v4: メニュー構造を共有してサブメニュー表示・項目実行にも応じる（初回書き出しは start() 内。
        // 表示中の書き出し保留も kunkit がトラッキング通知の観測で行う）。
        let bridge = KuntraykunBridge(statusItem: statusItem, menu: menu)
        bridge.start()
        kuntraykunBridge = bridge

        // メニュー内容は AppState 由来で動的に変わる（通知/PR のカウント・Status・アップデート文言）。
        // 状態変化を debounce してスナップショットを書き出し直し、kuntraykun のサブメニューを最新に保つ。
        menuExportCancellable = appState.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.kuntraykunBridge?.exportMenuSnapshot() }

        // アップデート有無を kuntraykun に報告する（集約バッジ/赤丸用）。
        updateCancellable = appState.$availableUpdate.map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasUpdate in self?.kuntraykunBridge?.reportUpdate(hasUpdate) }

        // 未読/未レビューの有無は表示中リストから導出する（手動同期はしない）
        cancellable = appState.$notifications.map { !$0.isEmpty }
            .combineLatest(appState.$unreviewedPRs.map { !$0.isEmpty })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unread, unreviewed in
                let name = MenuBarIcon.assetName(hasUnread: unread, hasUnreviewed: unreviewed)
                self?.statusItem.button?.image = Self.menuBarImage(named: name)
                KuntraykunIconExport.export(self?.statusItem.button?.image)
            }

        appState.startPolling()
    }

    // MARK: - メニューバーアイコン

    /// メニューバーアイコンを `Contents/Resources` の PNG から読み込む。
    /// Asset Catalog を廃止したため `NSImage(named:)` ではなくバンドル内のファイルパスで解決する。
    /// - 通常アイコン（`MenuBarIcon`）のみ template 指定でライト/ダークに自動追従。
    ///   未読/未レビュー系（色付き）は original のまま表示する。
    /// - 画像実体は 32px。`size` を 16pt に固定して Retina で高精細に描画させる。
    static func menuBarImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            logger.error("menu bar icon not found in bundle: \(name, privacy: .public)")
            return nil
        }
        image.isTemplate = (name == "MenuBarIcon")
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
