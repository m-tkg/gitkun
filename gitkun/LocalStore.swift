import Foundation

final class LocalStore {
    static let shared = LocalStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let knownIDs = "knownNotificationIDs"
        static let knownUpdatedAts = "knownNotificationUpdatedAts"
        static let knownUnreviewedIDs = "knownUnreviewedPRIDs"
        static let pollingInterval = "pollingInterval"
        static let diffStrategy = "diffStrategy"
        static let soundEnabled = "soundEnabled"
        static let lastNotifiedReleaseTag = "lastNotifiedReleaseTag"
    }

    var knownIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.knownIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.knownIDs) }
    }

    var knownUnreviewedIDs: Set<Int> {
        get { Set((defaults.array(forKey: Keys.knownUnreviewedIDs) as? [Int]) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.knownUnreviewedIDs) }
    }

    var knownUpdatedAts: [String: String] {
        get { (defaults.dictionary(forKey: Keys.knownUpdatedAts) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Keys.knownUpdatedAts) }
    }

    var pollingInterval: PollingInterval {
        get {
            let raw = defaults.integer(forKey: Keys.pollingInterval)
            return PollingInterval(rawValue: raw) ?? .sec30
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.pollingInterval) }
    }

    var diffStrategy: DiffStrategy {
        get {
            let raw = defaults.string(forKey: Keys.diffStrategy) ?? ""
            return DiffStrategy(rawValue: raw) ?? .id
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.diffStrategy) }
    }

    var soundEnabled: Bool {
        get {
            defaults.object(forKey: Keys.soundEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.soundEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.soundEnabled) }
    }

    /// 最後にバナー通知した最新リリースのタグ。同一バージョンの再通知を抑止する。
    var lastNotifiedReleaseTag: String? {
        get { defaults.string(forKey: Keys.lastNotifiedReleaseTag) }
        set { defaults.set(newValue, forKey: Keys.lastNotifiedReleaseTag) }
    }

    // 起動ごとにリセットするメモリ変数
    var isFirstFetch: Bool = true
}
