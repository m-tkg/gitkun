import Foundation

// MARK: - 相対時刻フォーマット

public enum RelativeTime {
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// ISO8601 文字列を "5m ago" 等の相対時刻文字列に変換する。パース不能なら空文字を返す。
    public static func format(iso: String, now: Date = Date()) -> String {
        guard let date = iso8601Formatter.date(from: iso) else { return "" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
