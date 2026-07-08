import AppKit
import gitkunCore
import Combine
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
    /// メニュー表示中か（連携 v4: 表示中のスナップショット書き出しを保留するため追跡）。
    private var isMenuOpen = false
    /// メニュー表示中に保留したスナップショット書き出しがあるか（連携 v4）。
    private var menuExportPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarImage(named: "MenuBarIcon")
        KuntraykunIconExport.export(statusItem.button?.image)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        // v4: メニュー構造を共有してサブメニュー表示・項目実行にも応じる。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusItem.isVisible = !hidden },
            popUpMenu: { [weak self] point in
                // LSUIElement（バックグラウンド）のまま popUp すると表示に失敗することがある。
                NSApp.activate(ignoringOtherApps: true)
                self?.statusItem.menu?.popUp(positioning: nil, at: point, in: nil)
            },
            exportMenu: { [weak self] in self?.exportMenuSnapshot() },
            performMenuItem: { [weak self] id in self?.performMenuItem(id: id) ?? false }
        )
        bridge.start()
        kuntraykunBridge = bridge
        // 起動時に現在のメニュー構造を書き出しておく（kuntraykun 起動済みでもすぐサブメニューが出せる）。
        exportMenuSnapshot()

        // メニュー内容は AppState 由来で動的に変わる（通知/PR のカウント・Status・アップデート文言）。
        // 状態変化を debounce してスナップショットを書き出し直し、kuntraykun のサブメニューを最新に保つ。
        menuExportCancellable = appState.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.exportMenuSnapshot() }

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

    // MARK: - kuntraykun 連携 v4（メニュースナップショット）

    /// メニュー構造を kuntraykun 用の共有場所へ書き出す（連携 v4）。
    /// `KuntraykunMenuExport.export` は `menu.update()`（= `menuNeedsUpdate` での再構築）を伴うため、
    /// メニュー表示中は行わず保留し、閉じた後にまとめて書き出す（表示中メニューの破壊を防ぐ）。
    func exportMenuSnapshot() {
        guard !isMenuOpen else {
            menuExportPending = true
            return
        }
        guard let menu = statusItem.menu else { return }
        KuntraykunMenuExport.export(menu)
    }

    /// kuntraykun のサブメニューでクリックされた項目（インデックスパス ID）を実行する（連携 v4）。
    func performMenuItem(id: String) -> Bool {
        guard let menu = statusItem.menu else { return false }
        return KuntraykunMenuExport.performItem(id: id, in: menu)
    }

    // NSMenuDelegate（menuNeedsUpdate は AppDelegate+Menu.swift）。
    // 表示中の書き出しを保留するためメニューの開閉を追跡する。
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { self.isMenuOpen = true }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            self.isMenuOpen = false
            guard self.menuExportPending else { return }
            self.menuExportPending = false
            // menuDidClose 中の再構築を避けるため、次のループで書き出す。
            DispatchQueue.main.async { self.exportMenuSnapshot() }
        }
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
