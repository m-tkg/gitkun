import AppKit
import gitkunCore

// MARK: - メニュー構築

extension AppDelegate {

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
            for item in items.prefix(AppState.displayLimit) {
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
        statusMenu.addItem(disabled: appState.status.displayLabel)
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
