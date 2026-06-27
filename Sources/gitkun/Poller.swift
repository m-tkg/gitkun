import Foundation

/// 一定間隔で `onFire` を呼ぶタイマー。`start()` 時に即時 1 回発火する。
/// 通知ポーリングと更新チェックの両方で使う。
final class Poller {

    private var timer: Timer?
    private var interval: TimeInterval
    private let onFire: () -> Void

    init(interval: Int, onFire: @escaping () -> Void) {
        self.interval = TimeInterval(interval)
        self.onFire = onFire
    }

    func start() {
        scheduleTimer()
        // 起動時に即発火
        onFire()
    }

    func updateInterval(_ newInterval: Int) {
        interval = TimeInterval(newInterval)
        timer?.invalidate()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.onFire()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit {
        timer?.invalidate()
    }
}
