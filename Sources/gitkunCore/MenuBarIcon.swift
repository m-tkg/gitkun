import Foundation

/// 未読/未レビューの有無からメニューバーアイコンのアセット名を導出する純粋ロジック。
public enum MenuBarIcon {

    /// - Parameters:
    ///   - hasUnread: 未読通知が1件以上あるか
    ///   - hasUnreviewed: 未レビュー PR が1件以上あるか
    /// - Returns: `Resources/` 配下の PNG アセット名（拡張子なし）
    public static func assetName(hasUnread: Bool, hasUnreviewed: Bool) -> String {
        switch (hasUnread, hasUnreviewed) {
        case (true, true): return "MenuBarIconUnreadAndUnreview"
        case (true, false): return "MenuBarIconUnread"
        case (false, true): return "MenuBarIconUnreview"
        case (false, false): return "MenuBarIcon"
        }
    }
}
