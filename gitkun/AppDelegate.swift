import AppKit
import Combine
import OSLog

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    let appState = AppState()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(named: "MenuBarIcon")

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

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
                self?.statusItem.button?.image = NSImage(named: name)
            }

        appState.startPolling()
    }

    // MARK: - メニュー構築

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 通知セクション（reason 別 submenu）
        menu.addItem(disabled: "GitHub Notifications")
        menu.addItem(.separator())
        if appState.notifications.isEmpty {
            menu.addItem(disabled: "No unread notifications")
        } else {
            buildGroupedNotificationItems(into: menu)
        }
        menu.addItem(.separator())

        // レビュー依頼
        addSubmenu(into: menu,
                   title: "Review Requests",
                   items: appState.unreviewedPRs,
                   emptyTitle: "No review requests",
                   dotColor: .systemOrange) { [weak self] pr in
            self?.appState.remove(unreviewedPR: pr)
        }

        // My PRs（assignee:@me と author:@me のマージ）
        addSubmenu(into: menu,
                   title: "My PRs",
                   items: appState.myPRs,
                   emptyTitle: "No PRs",
                   dotColor: .systemBlue) { [weak self] item in
            self?.appState.remove(assignedItem: item)
        }

        // Assigned Issues
        addSubmenu(into: menu,
                   title: "Assigned Issues",
                   items: appState.assignedIssues,
                   emptyTitle: "No assigned issues",
                   dotColor: .systemPurple) { [weak self] item in
            self?.appState.remove(assignedItem: item)
        }
        menu.addItem(.separator())

        // Status サブメニュー
        menu.addItem(buildStatusMenuItem())
        menu.addItem(.separator())

        // 更新あり（最新リリースが自バージョンより新しいときのみ表示）
        if let update = appState.availableUpdate {
            let updateItem = NSMenuItem(title: "⬆ Update to \(update.tagName)…",
                                        action: #selector(installUpdate), keyEquivalent: "")
            updateItem.target = self
            updateItem.isEnabled = !appState.isFetching
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        // 設定
        let refresh = NSMenuItem(title: "Refresh", action: #selector(doRefresh), keyEquivalent: "")
        refresh.target = self
        refresh.isEnabled = !appState.isFetching
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let loginTitle = appState.launchManager.isEnabled ? "Launch at login: ON" : "Launch at login: OFF"
        let login = NSMenuItem(title: loginTitle, action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(doQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// 共通: 親メニュー + サブメニュー（行は `NotificationMenuItemView`）を構築。
    /// `onRemove` 後に項目の `webURL` をブラウザで開く。
    private func addSubmenu<T: MenuRowDisplayable>(into menu: NSMenu,
                                                   title: String,
                                                   items: [T],
                                                   emptyTitle: String,
                                                   dotColor: NSColor,
                                                   onRemove: @escaping (T) -> Void) {
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
                    dotColor: dotColor
                ) {
                    onRemove(item)
                    NSWorkspace.shared.open(item.webURL)
                }
                submenu.addItem(menuItem)
            }
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func buildGroupedNotificationItems(into menu: NSMenu) {
        let grouped = Dictionary(grouping: appState.notifications, by: \.reason)

        // 固定優先順 → 未知 reason はアルファベット順で末尾
        var orderedKeys = NotificationReason.allCases
            .map(\.rawValue)
            .filter { grouped[$0] != nil }
        let known = Set(NotificationReason.allCases.map(\.rawValue))
        orderedKeys.append(contentsOf: grouped.keys.filter { !known.contains($0) }.sorted())

        for key in orderedKeys {
            guard let items = grouped[key], !items.isEmpty else { continue }
            let label = NotificationReason(rawValue: key)?.displayLabel ?? key
            addSubmenu(into: menu,
                       title: label,
                       items: items,
                       emptyTitle: "",
                       dotColor: .systemGreen) { [weak self] notif in
                self?.appState.remove(notification: notif)
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
    @objc private func toggleLogin()  { appState.launchManager.toggle() }

    /// SwiftUI の Settings シーンを開く。LSUIElement アプリのため前面化が必要。
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    @objc private func installUpdate() {
        guard let update = appState.availableUpdate else { return }

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
        NSWorkspace.shared.open(url)
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
