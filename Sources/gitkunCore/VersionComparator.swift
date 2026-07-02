import Foundation

/// `v` プレフィックス付きのタグと `CFBundleShortVersionString` を数値比較する。
public enum VersionComparator {
    /// `tag` が `current` より新しければ true。
    public static func isNewer(tag: String, than current: String) -> Bool {
        let a = components(tag)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 先頭の `v`/`V` を除去し `.` 区切りで数値化。各要素は先頭の数字部分のみ採用（`0-beta` → 0）。
    private static func components(_ version: String) -> [Int] {
        let trimmed = (version.hasPrefix("v") || version.hasPrefix("V"))
            ? String(version.dropFirst())
            : version
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}
