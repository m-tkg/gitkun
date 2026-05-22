import Foundation

protocol NotificationPollerDelegate: AnyObject {
    func pollerDidFire()
}

final class NotificationPoller {

    weak var delegate: NotificationPollerDelegate?

    private var timer: Timer?
    private var interval: TimeInterval

    init(interval: Int) {
        self.interval = TimeInterval(interval)
    }

    func start() {
        scheduleTimer()
        // 起動時に即フェッチ
        delegate?.pollerDidFire()
    }

    func updateInterval(_ newInterval: Int) {
        interval = TimeInterval(newInterval)
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.delegate?.pollerDidFire()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit {
        timer?.invalidate()
    }
}
