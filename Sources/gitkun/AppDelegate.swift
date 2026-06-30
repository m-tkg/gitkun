import AppKit
import gitkunCore
import Combine
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    let appState = AppState()
    private var cancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var kuntraykunBridge: KuntraykunBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarImage(named: "MenuBarIcon")
        KuntraykunIconExport.export(statusItem.button?.image)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusItem.isVisible = !hidden },
            popUpMenu: { [weak self] point in self?.statusItem.menu?.popUp(positioning: nil, at: point, in: nil) }
        )
        bridge.start()
        kuntraykunBridge = bridge

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
                let name: String
                switch (unread, unreviewed) {
                case (true,  true):  name = "MenuBarIconUnreadAndUnreview"
                case (true,  false): name = "MenuBarIconUnread"
                case (false, true):  name = "MenuBarIconUnreview"
                case (false, false): name = "MenuBarIcon"
                }
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

    // MARK: - メニュー構築

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 先頭に現在バージョン（操作不可）。
        menu.addItem(disabled: "gitkun v\(appState.currentVersion)")
        menu.addItem(.separator())

        // 通知セクション（reason 別 submenu）
        if appState.notifications.isEmpty {
            menu.addItem(disabled: "No unread notifications")
        } else {
            buildGroupedNotificationItems(into: menu)
        }
        menu.addItem(.separator())

        // レビュー依頼。クリックしても一覧から削除しない（次ポーリングで再取得）。
        addSubmenu(into: menu,
                   title: "Review Requests",
                   items: appState.unreviewedPRs,
                   emptyTitle: "No review requests",
                   dotColor: .systemOrange)

        // My PRs（assignee:@me と author:@me のマージ）。クリックしても削除しない。
        addSubmenu(into: menu,
                   title: "My PRs",
                   items: appState.myPRs,
                   emptyTitle: "No PRs",
                   dotColor: .systemBlue)

        // Assigned Issues。クリックしても削除しない。
        addSubmenu(into: menu,
                   title: "Assigned Issues",
                   items: appState.assignedIssues,
                   emptyTitle: "No assigned issues",
                   dotColor: .systemPurple)
        menu.addItem(.separator())

        // Status サブメニュー
        menu.addItem(buildStatusMenuItem())
        menu.addItem(.separator())

        // 設定・更新
        let refresh = NSMenuItem(title: "Refresh", action: #selector(doRefresh), keyEquivalent: "")
        refresh.target = self
        refresh.isEnabled = !appState.isFetching
        menu.addItem(refresh)

        // 更新あり → インストール、なし → 手動チェック（1項目で切り替え）。
        let updateItem: NSMenuItem
        if let update = appState.availableUpdate {
            updateItem = NSMenuItem(title: "⬆ Update to \(update.tagName)…",
                                    action: #selector(installUpdate), keyEquivalent: "")
        } else {
            updateItem = NSMenuItem(title: "Check for Updates…",
                                    action: #selector(checkForUpdate), keyEquivalent: "")
        }
        updateItem.target = self
        updateItem.isEnabled = !appState.isFetching
        menu.addItem(updateItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(doQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// 共通: 親メニュー + サブメニュー（行は `NotificationMenuItemView`）を構築。
    /// 行クリック時は項目の `webURL` をブラウザで開いてから `onClick` を呼ぶ。
    /// クリックで一覧から項目を削除はしない（次ポーリングで再取得される）。
    private func addSubmenu<T: MenuRowDisplayable>(into menu: NSMenu,
                                                   title: String,
                                                   items: [T],
                                                   emptyTitle: String,
                                                   dotColor: NSColor,
                                                   onClick: @escaping (T) -> Void = { _ in }) {
        let parent = NSMenuItem(title: "\(title) (\(items.count))", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)

        if items.isEmpty {
            submenu.addItem(disabled: emptyTitle)
        } else {
            for item in items.prefix(20) {
                let menuItem = NSMenuItem()
                menuItem.view = NotificationMenuItemView(
                    repoFullName: item.repoFullName,
                    title: item.displayTitle,
                    updatedAt: item.updatedAtString,
                    dotColor: dotColor,
                    detail: item.rowDetail
                ) {
                    BrowserTabOpener.open(item.webURL)
                    onClick(item)
                }
                submenu.addItem(menuItem)
            }
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func buildGroupedNotificationItems(into menu: NSMenu) {
        // reason を集約カテゴリ（Review Requested / Mentioned / Commented / State Changed /
        // Authored）+ その他個別 reason にまとめ、表示順に並べる（純ロジックは gitkunCore）。
        // 現在レビュー依頼中でない review_requested 通知は Commented へ寄せる（effectiveReason）。
        let activeReviewKeys = appState.activeReviewKeys
        let groups = NotificationGrouping.grouped(appState.notifications) {
            NotificationGrouping.effectiveReason(
                reason: $0.reason,
                pullRequestKey: $0.pullRequestKey,
                activeReviewKeys: activeReviewKeys
            )
        }

        for group in groups {
            // 通知はクリックでブラウザを開いた後に refresh する。
            // GitHub 側で既読になった通知が次フェッチで一覧から消える。
            addSubmenu(into: menu,
                       title: group.label,
                       items: group.items,
                       emptyTitle: "",
                       dotColor: .systemGreen) { [weak self] _ in
                self?.appState.fetchNow()
            }
        }
    }

    private func buildStatusMenuItem() -> NSMenuItem {
        let statusMenuItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
        let statusMenu = NSMenu(title: "Status")
        statusMenu.addItem(disabled: statusLabel)
        statusMenu.addItem(disabled: "Version: \(appState.currentVersion)")
        statusMenu.addItem(disabled: "Unread: \(appState.notifications.count)")
        statusMenu.addItem(disabled: "Review requests: \(appState.unreviewedPRs.count)")
        statusMenu.addItem(disabled: "My PRs: \(appState.myPRs.count)")
        statusMenu.addItem(disabled: "Assigned issues: \(appState.assignedIssues.count)")
        if let date = appState.lastChecked {
            let f = DateFormatter()
            f.timeStyle = .short
            statusMenu.addItem(disabled: "Last checked: \(f.string(from: date))")
        }
        if let detail = appState.lastErrorDetail {
            statusMenu.addItem(.separator())
            statusMenu.addItem(disabled: detail)
            let copy = NSMenuItem(title: "Copy Error", action: #selector(copyError), keyEquivalent: "")
            copy.target = self
            statusMenu.addItem(copy)
            let console = NSMenuItem(title: "Open Console.app", action: #selector(openConsole), keyEquivalent: "")
            console.target = self
            statusMenu.addItem(console)
        }
        statusMenuItem.submenu = statusMenu
        return statusMenuItem
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle:           return "Status: -"
        case .loading:        return "Status: Loading..."
        case .ok:             return "Status: OK"
        case .error(let msg): return "Status: \(msg)"
        }
    }

    // MARK: - アクション

    @objc private func doRefresh()    { appState.fetchNow() }

    /// 設定ウィンドウを開く。
    /// SwiftUI の Settings シーンは macOS 14+ でセレクタ経由の表示がブロックされたため、
    /// 自前の NSWindow + NSHostingController で表示する。
    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(appState: appState, launchManager: appState.launchManager)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "gitkun Settings"
            window.styleMask = [.titled, .closable]
            // 閉じてもインスタンスを保持し、再度開けるようにする
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    /// メニューからの手動更新チェック。結果をダイアログで提示する。
    @objc private func checkForUpdate() {
        Task { @MainActor in
            switch await appState.checkForUpdate(interactive: true) {
            case .available(let release):
                promptInstall(release)
            case .upToDate:
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "You’re up to date"
                alert.informativeText = "gitkun v\(appState.currentVersion) is the latest version."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            case .failed(let error):
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Update check failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func installUpdate() {
        guard let update = appState.availableUpdate else { return }
        promptInstall(update)
    }

    /// 更新のインストール確認ダイアログ。
    private func promptInstall(_ update: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update to \(update.tagName)?"
        alert.informativeText = "gitkun will quit and relaunch with the new version."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                do {
                    try await appState.performUpdate()
                } catch {
                    presentUpdateError(error, releaseURL: update.htmlUrl)
                }
            }
        case .alertSecondButtonReturn:
            openReleasePage(update.htmlUrl)
        default:
            break
        }
    }

    private func presentUpdateError(_ error: Error, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            openReleasePage(releaseURL)
        }
    }

    private func openReleasePage(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        BrowserTabOpener.open(url)
    }
    @objc private func doQuit()       { NSApplication.shared.terminate(nil) }
    @objc private func copyError() {
        guard let d = appState.lastErrorDetail else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(d, forType: .string)
    }
    @objc private func openConsole() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        Task { @MainActor in self.buildMenu(menu) }
    }
}

// MARK: - NSMenu helper

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}

// MARK: - Kuntraykun 連携

/// kuntraykun（`com.mtkg.kuntraykun`）に「まとめられる」ための連携ブリッジ。
///
/// 仕様: kuntraykun リポジトリの `docs/kun-integration-protocol.md`（連携プロトコル v1）。
/// 通知名・キーは kuntraykun 側と一致させること。
///
/// - `sync` を観測し、自分が管理対象なら（かつ kuntraykun 起動中なら）自分のアイコンを隠す。
/// - `showMenu` を観測し、自分宛なら指定座標に自分のメニューを popUp する。
/// - 起動時に `appLaunched` を送り、kuntraykun から最新の `sync` を受け取る。
@MainActor
final class KuntraykunBridge {
    private static let kuntraykunBundleIDs = ["com.mtkg.kuntraykun", "com.mtkg.kuntraykun.local"]
    private static let syncName = Notification.Name("com.mtkg.kuntraykun.sync")
    private static let showMenuName = Notification.Name("com.mtkg.kuntraykun.showMenu")
    private static let appLaunchedName = Notification.Name("com.mtkg.kun.appLaunched")
    private static let updateStateName = Notification.Name("com.mtkg.kun.updateState")
    private static let managedDefaultsKey = "KuntraykunManaged"

    private let setHidden: (Bool) -> Void
    private let popUpMenu: (NSPoint) -> Void
    private let myBundleID: String
    private var isManaged: Bool
    /// `NSWorkspace.runningApplications` の KVO 監視トークン。
    private var runningAppsObservation: NSKeyValueObservation?
    /// 遅延表示（復活）の世代。再評価のたびに進めて保留中の復活をキャンセルする。
    private var showGeneration = 0
    /// 直近に kuntraykun へ報告したアップデート有無。sync 受信時に再送して整合させる。
    private var lastReportedUpdate = false

    init(setHidden: @escaping (Bool) -> Void, popUpMenu: @escaping (NSPoint) -> Void) {
        self.setHidden = setHidden
        self.popUpMenu = popUpMenu
        let raw = Bundle.main.bundleIdentifier ?? ""
        self.myBundleID = raw.hasSuffix(".local") ? String(raw.dropLast(".local".count)) : raw
        self.isManaged = UserDefaults.standard.bool(forKey: Self.managedDefaultsKey)
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(onSync(_:)), name: Self.syncName, object: nil)
        dnc.addObserver(self, selector: #selector(onShowMenu(_:)), name: Self.showMenuName, object: nil)

        // LSUIElement（メニューバー常駐）アプリの起動/終了は NSWorkspace の didLaunch/didTerminate 通知が
        // 配信されないため、runningApplications を KVO 監視する（kuntraykun のクラッシュ時もアイコンが復活する）。
        // .initial で初回の表示判定も行う。
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        }

        dnc.postNotificationName(
            Self.appLaunchedName, object: nil,
            userInfo: ["bundleID": myBundleID, "protocol": "1"],
            deliverImmediately: true
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        runningAppsObservation?.invalidate()
    }

    @objc private func onSync(_ note: Notification) {
        let managed = (note.userInfo?["managed"] as? String ?? "")
            .split(separator: ",").map(String.init)
        let nowManaged = managed.contains(myBundleID)
        if nowManaged != isManaged {
            isManaged = nowManaged
            UserDefaults.standard.set(nowManaged, forKey: Self.managedDefaultsKey)
        }
        refreshVisibility()
        // 起動直後の kuntraykun にも現在のアップデート状態を伝える。
        reportUpdate(lastReportedUpdate)
    }

    /// 「アップデートあり/なし」を kuntraykun に報告する（更新検知時・解消時に呼ぶ）。
    func reportUpdate(_ hasUpdate: Bool) {
        lastReportedUpdate = hasUpdate
        DistributedNotificationCenter.default().postNotificationName(
            Self.updateStateName, object: nil,
            userInfo: ["bundleID": myBundleID, "hasUpdate": hasUpdate ? "1" : "0", "protocol": "1"],
            deliverImmediately: true
        )
    }

    @objc private func onShowMenu(_ note: Notification) {
        guard note.userInfo?["target"] as? String == myBundleID,
              let xs = note.userInfo?["x"] as? String, let x = Double(xs),
              let ys = note.userInfo?["y"] as? String, let y = Double(ys) else { return }
        popUpMenu(NSPoint(x: x, y: y))
    }

    /// アイコン表示規則: 隠す = (管理対象) かつ (kuntraykun 起動中)。未起動なら隠さない。
    @objc private func refreshVisibility() {
        // NSRunningApplication.runningApplications(withBundleIdentifier:) は実行中でも空を返すことがあり
        // （誤判定でアイコンが再表示される）、KVO 対象の NSWorkspace.shared.runningApplications と
        // 同じソースで判定して整合させる。
        let hubRunning = NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return Self.kuntraykunBundleIDs.contains(id)
        }
        // 再評価のたびに世代を進め、保留中の遅延表示を無効化する。
        showGeneration &+= 1
        if !isManaged || hubRunning {
            // 管理対象でない→表示、管理対象かつ kuntraykun 起動中→隠す（いずれも即時）。
            setHidden(isManaged && hubRunning)
        } else {
            // 管理対象だが kuntraykun を検知できない。KVO の瞬間的なゆらぎで誤って復活し
            // アイコンが一瞬出てしまうのを防ぐため、少し待ってから復活する（待機中に再検知したらキャンセル）。
            let gen = showGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.showGeneration == gen else { return }
                    self.setHidden(false)
                }
            }
        }
    }
}
