import AppKit
import gitkunCore
import KunUpdateKit
import SwiftUI

// MARK: - アクション

extension AppDelegate {

    @objc func doRefresh()    { appState.fetchNow() }

    /// 設定ウィンドウを開く。
    /// SwiftUI の Settings シーンは macOS 14+ でセレクタ経由の表示がブロックされたため、
    /// 自前の NSWindow + NSHostingController で表示する。
    @objc func openSettings() {
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
    @objc func checkForUpdate() {
        Task { @MainActor in
            switch await appState.checkForUpdate() {
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

    @objc func installUpdate() {
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
    @objc func doQuit()       { NSApplication.shared.terminate(nil) }
    @objc func copyError() {
        guard let d = appState.lastErrorDetail else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(d, forType: .string)
    }
    @objc func openConsole() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
    }
}
