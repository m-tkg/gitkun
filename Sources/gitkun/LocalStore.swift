import Foundation
import gitkunCore

final class LocalStore {
    static let shared = LocalStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let knownIDs = "knownNotificationIDs"
        static let knownUnreviewedIDs = "knownUnreviewedPRIDs"
        static let pollingInterval = "pollingInterval"
        static let unreadSoundName = "unreadSoundName"
        static let reviewSoundName = "reviewSoundName"
        static let excludeWIP = "excludeWIP"
    }

    private init() {
        // 廃止した設定キーの残骸を掃除する
        defaults.removeObject(forKey: "knownNotificationUpdatedAts")
        defaults.removeObject(forKey: "diffStrategy")
        // soundEnabled は各サウンドの N/A 選択（*SoundName）に置き換えられた
        defaults.removeObject(forKey: "soundEnabled")
        // アップデート通知バナーを廃止したため、関連キーも掃除する
        defaults.removeObject(forKey: "updateSoundName")
        defaults.removeObject(forKey: "lastNotifiedReleaseTag")
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

    /// draft / WIP の PR を Review Requests から除外するか。SettingsView の @AppStorage と同じキー。
    var excludeWIP: Bool {
        get {
            defaults.object(forKey: Keys.excludeWIP) == nil
                ? true
                : defaults.bool(forKey: Keys.excludeWIP)
        }
        set { defaults.set(newValue, forKey: Keys.excludeWIP) }
    }

    // 起動ごとにリセットするメモリ変数
    var isFirstFetch: Bool = true
}
