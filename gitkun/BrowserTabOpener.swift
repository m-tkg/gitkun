import AppKit
import OSLog

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "BrowserTabOpener")

/// GitHub の URL を既定ブラウザで開く。既定が Safari / Chrome で、同じ PR / Issue を表示している
/// タブが既にあれば、そのタブをアクティブにする（新規タブを増やさない）。
/// それ以外（別ブラウザ・未起動・自動化権限拒否・スクリプト失敗）は `NSWorkspace` で新規に開く。
///
/// タブの検索・切り替えは macOS 標準 API に無いため AppleScript（`NSAppleScript`）で行う。
/// タブ URL の照合は `GitHubTabMatcher`（純粋ロジック）に委譲する。
enum BrowserTabOpener {

    /// 対応ブラウザ。スクリプトの方言は `engine` で分岐する（Chromium 系は Chrome と同一辞書）。
    private struct Browser {
        enum Engine { case safari, chromium }

        let bundleID: String
        let appName: String
        let engine: Engine

        /// 既定ブラウザ判定で得た bundle id → 対応ブラウザ。未対応は nil。
        /// Chromium 系（Edge / Brave / Vivaldi / Opera）は Chrome と同じ AppleScript 辞書を持つ。
        private static let known: [Browser] = [
            Browser(bundleID: "com.apple.Safari",          appName: "Safari",                engine: .safari),
            Browser(bundleID: "com.google.Chrome",         appName: "Google Chrome",         engine: .chromium),
            Browser(bundleID: "com.google.Chrome.beta",    appName: "Google Chrome Beta",    engine: .chromium),
            Browser(bundleID: "com.google.Chrome.dev",     appName: "Google Chrome Dev",     engine: .chromium),
            Browser(bundleID: "com.google.Chrome.canary",  appName: "Google Chrome Canary",  engine: .chromium),
            Browser(bundleID: "com.microsoft.edgemac",     appName: "Microsoft Edge",        engine: .chromium),
            Browser(bundleID: "com.brave.Browser",         appName: "Brave Browser",         engine: .chromium),
            Browser(bundleID: "com.vivaldi.Vivaldi",       appName: "Vivaldi",               engine: .chromium),
            Browser(bundleID: "com.operasoftware.Opera",   appName: "Opera",                 engine: .chromium),
        ]

        init(bundleID: String, appName: String, engine: Engine) {
            self.bundleID = bundleID
            self.appName = appName
            self.engine = engine
        }

        init?(bundleID: String) {
            guard let browser = Self.known.first(where: { $0.bundleID == bundleID }) else { return nil }
            self = browser
        }
    }

    /// 開いているタブの位置。AppleScript の window / tab はいずれも 1-based。
    private struct TabLocation {
        let windowIndex: Int
        let tabIndex: Int
        let url: URL
    }

    /// GitHub URL を開く。既存タブがあれば移動、無ければ新規タブ。
    static func open(_ url: URL) {
        // NSAppleScript はメインスレッドで実行する（通知デリゲートはメインとは限らない）。
        if Thread.isMainThread {
            openOnMain(url)
        } else {
            DispatchQueue.main.async { openOnMain(url) }
        }
    }

    private static func openOnMain(_ url: URL) {
        guard let browser = defaultBrowser() else {
            logger.debug("Default browser is not a supported browser; opening normally")
            NSWorkspace.shared.open(url)
            return
        }
        guard isRunning(browser) else {
            logger.debug("\(browser.appName, privacy: .public) is not running; opening normally")
            NSWorkspace.shared.open(url)
            return
        }
        guard let tab = findMatchingTab(for: url, in: browser) else {
            logger.debug("No existing tab matched \(url.absoluteString, privacy: .public); opening new tab")
            NSWorkspace.shared.open(url)
            return
        }
        guard activate(tab, in: browser) else {
            logger.error("Found matching tab but failed to activate it; opening new tab")
            NSWorkspace.shared.open(url)
            return
        }
        logger.debug("Activated existing tab for \(url.absoluteString, privacy: .public)")
    }

    // MARK: - 既定ブラウザの判定

    private static func defaultBrowser() -> Browser? {
        guard let probe = URL(string: "https://github.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            return nil
        }
        if let browser = Browser(bundleID: bundleID) { return browser }
        logger.debug("Default browser bundle id is not supported: \(bundleID, privacy: .public)")
        return nil
    }

    private static func isRunning(_ browser: Browser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    // MARK: - タブ検索・切り替え

    private static func findMatchingTab(for url: URL, in browser: Browser) -> TabLocation? {
        guard let descriptor = runAppleScript(tabListScript(for: browser)) else { return nil }
        return parseTabs(descriptor).first { GitHubTabMatcher.matches(url, $0.url) }
    }

    private static func activate(_ tab: TabLocation, in browser: Browser) -> Bool {
        runAppleScript(activateScript(for: browser, tab: tab)) != nil
    }

    private static func parseTabs(_ descriptor: NSAppleEventDescriptor) -> [TabLocation] {
        let count = descriptor.numberOfItems
        guard count > 0 else { return [] }

        var result: [TabLocation] = []
        for i in 1...count {  // AppleScript の list は 1-based
            guard let line = descriptor.atIndex(i)?.stringValue else { continue }
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 3,
                  let w = Int(parts[0]), let t = Int(parts[1]),
                  let u = URL(string: parts[2]) else { continue }
            result.append(TabLocation(windowIndex: w, tabIndex: t, url: u))
        }
        return result
    }

    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript error: \(error, privacy: .public)")
            return nil
        }
        return result
    }

    // MARK: - AppleScript

    /// 各タブを `windowIndex \t tabIndex \t URL` の text にして list で返す。
    ///
    /// 速度のため URL はウィンドウ単位で一括取得する（`URL of tabs of w`）。タブごとに
    /// `URL of t` を取ると Apple Event 往復がタブ数に比例し、タブが多いと数秒かかるため。
    /// 一括取得ならウィンドウ数ぶんの往復で済む。取得済みリストの反復は往復を伴わない。
    /// `tabIndex` はリスト位置（1-based）から導出する。URL 取得不可なタブは値が
    /// `missing value` 等になるが、`u as text` で文字列化 → パース時に弾かれてスキップされる。
    ///
    /// 注意: 区切りの `tab`（タブ文字）は `tell application` ブロックの外で評価する。ブロック内では
    /// ブラウザの用語（`tab` 要素）に解釈されて文字列 "tab" になり、パースが壊れるため。
    private static func tabListScript(for browser: Browser) -> String {
        """
        set sep to tab
        tell application "\(browser.appName)"
            set out to {}
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                try
                    set tabURLs to URL of tabs of w
                    set ti to 0
                    repeat with u in tabURLs
                        set ti to ti + 1
                        try
                            set end of out to (wi as text) & sep & (ti as text) & sep & (u as text)
                        end try
                    end repeat
                end try
            end repeat
            return out
        end tell
        """
    }

    private static func activateScript(for browser: Browser, tab: TabLocation) -> String {
        let selectTab: String
        switch browser.engine {
        case .safari:
            selectTab = "set current tab of window \(tab.windowIndex) to tab \(tab.tabIndex) of window \(tab.windowIndex)"
        case .chromium:
            selectTab = "set active tab index of window \(tab.windowIndex) to \(tab.tabIndex)"
        }
        return """
        tell application "\(browser.appName)"
            \(selectTab)
            set index of window \(tab.windowIndex) to 1
            activate
        end tell
        """
    }
}
