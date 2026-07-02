import SwiftUI

let logSubsystem = "com.mtkg.gitkun"

@main
struct GitkunApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mtkg.gitkun"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            NSApplication.shared.terminate(nil)
        }
    }

    var body: some Scene {
        // 設定ウィンドウは AppDelegate が NSWindow で管理する
        // （Settings シーンは macOS 14+ でメニューのセレクタから開けないため未使用）
        Settings { EmptyView() }
    }
}
