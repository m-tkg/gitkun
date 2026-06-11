import Foundation

final class LocalStore {
    static let shared = LocalStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let knownIDs = "knownNotificationIDs"
        static let knownUnreviewedIDs = "knownUnreviewedPRIDs"
        static let pollingInterval = "pollingInterval"
        static let soundEnabled = "soundEnabled"
        static let unreadSoundName = "unreadSoundName"
        static let reviewSoundName = "reviewSoundName"
        static let lastNotifiedReleaseTag = "lastNotifiedReleaseTag"
    }

    private init() {
        // 廃止した updatedAt 差分方式の残骸を掃除する
        defaults.removeObject(forKey: "knownNotificationUpdatedAts")
        defaults.removeObject(forKey: "diffStrategy")
    }

    var knownIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.knownIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.knownIDs) }
    }

    var knownUnreviewedIDs: Set<Int> {
        get { Set((defaults.array(forKey: Keys.knownUnreviewedIDs) as? [Int]) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.knownUnreviewedIDs) }
    }

    var pollingInterval: PollingInterval {
        get {
            let raw = defaults.integer(forKey: Keys.pollingInterval)
            return PollingInterval(rawValue: raw) ?? .sec30
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.pollingInterval) }
    }

    var soundEnabled: Bool {
        get {
            defaults.object(forKey: Keys.soundEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.soundEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.soundEnabled) }
    }

    /// 新規未読通知のときに鳴らす音の名前。SettingsView の @AppStorage と同じキー。
    var unreadSoundName: String {
        get { defaults.string(forKey: Keys.unreadSoundName) ?? "Glass" }
        set { defaults.set(newValue, forKey: Keys.unreadSoundName) }
    }

    /// 新規レビュー依頼のときに鳴らす音の名前。SettingsView の @AppStorage と同じキー。
    var reviewSoundName: String {
        get { defaults.string(forKey: Keys.reviewSoundName) ?? "Glass" }
        set { defaults.set(newValue, forKey: Keys.reviewSoundName) }
    }

    /// 最後にバナー通知した最新リリースのタグ。同一バージョンの再通知を抑止する。
    var lastNotifiedReleaseTag: String? {
        get { defaults.string(forKey: Keys.lastNotifiedReleaseTag) }
        set { defaults.set(newValue, forKey: Keys.lastNotifiedReleaseTag) }
    }

    // 起動ごとにリセットするメモリ変数
    var isFirstFetch: Bool = true
}
