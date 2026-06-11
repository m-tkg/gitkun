import SwiftUI

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
        Settings { SettingsView() }
    }
}
