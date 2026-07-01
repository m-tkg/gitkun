import AppKit

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
        self.myBundleID = Bundle.main.baseBundleIdentifier
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

// MARK: - Bundle helper

extension Bundle {
    /// `.local` サフィックスを除いた基底 bundle ID（本番/ローカルビルドで同一視するため）。
    /// `bundleIdentifier` が nil の場合は空文字列にフォールバックする。
    var baseBundleIdentifier: String {
        let raw = bundleIdentifier ?? ""
        return raw.hasSuffix(".local") ? String(raw.dropLast(".local".count)) : raw
    }
}
