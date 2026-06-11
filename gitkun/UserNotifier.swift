import Foundation
import UserNotifications
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "UserNotifier")

final class UserNotifier: NSObject {

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestPermission()
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                logger.warning("Notification permission not granted")
            }
        }
    }

    func send(title: String, body: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["url": url.absoluteString]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func playSound() {
        NSSound(named: "Glass")?.play()
    }
}

extension UserNotifier: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
