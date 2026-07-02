import Foundation

// MARK: - 設定・ステータス

/// ポーリング間隔（秒）の解決ポリシー。UserDefaults に保存された生の Int を
/// 実際に使う秒数へ変換する純関数。
public enum PollingIntervalPolicy {
    /// `stored` が 0 以下（未設定含む）なら 30 にフォールバックし、
    /// 1 以上ならその値をそのまま使う。
    public static func effectiveSeconds(_ stored: Int) -> Int {
        stored > 0 ? stored : 30
    }
}

public enum AppStatus {
    case idle
    case loading
    case ok
    case error(String)
}

extension AppStatus {
    public var displayLabel: String {
        switch self {
        case .idle:           return "Status: -"
        case .loading:        return "Status: Loading..."
        case .ok:             return "Status: OK"
        case .error(let msg): return "Status: \(msg)"
        }
    }
}
