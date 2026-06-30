import Foundation

/// 通知一覧のトップグループ（集約カテゴリ）。複数の `reason` を1つにまとめる。
/// 「まず一覧で知りたい4分類 + 自分が作成（Authored）」を `reason` から確実に判定できる範囲で集約する。
/// 集約対象外の `reason`（subscribed / assign など）は個別グループのまま残す。
public enum NotificationCategory: CaseIterable {
    case reviewRequested
    case mentioned
    case commented
    case stateChanged
    case authored

    public var displayLabel: String {
        switch self {
        case .reviewRequested: return "Review Requested"
        case .mentioned:       return "Mentioned"
        case .commented:       return "Commented"
        case .stateChanged:    return "State Changed"
        case .authored:        return "Authored"
        }
    }

    /// この集約カテゴリに含まれる `reason` 群。
    var reasons: Set<String> {
        switch self {
        case .reviewRequested: return ["review_requested", "approval_requested"]
        case .mentioned:       return ["mention", "team_mention"]
        case .commented:       return ["comment"]
        case .stateChanged:    return ["state_change"]
        case .authored:        return ["author"]
        }
    }

    /// `reason` を集約カテゴリに対応づける。対象外なら nil。
    public init?(reason: String) {
        guard let match = Self.allCases.first(where: { $0.reasons.contains(reason) }) else {
            return nil
        }
        self = match
    }
}

/// 通知を表示グループへ集約し、表示順に並べる純ロジック。
public enum NotificationGrouping {
    public struct Group<T> {
        public let label: String
        public let items: [T]
    }

    /// 通知を表示グループへ集約して表示順に返す。
    /// - 先頭: 集約カテゴリ（`NotificationCategory.allCases` の宣言順）
    /// - 続いて: 集約対象外 `reason` を個別グループ化（`NotificationReason.allCases` 順、未知はアルファベット順で末尾）
    public static func grouped<T>(_ items: [T], reason: (T) -> String) -> [Group<T>] {
        var itemsByLabel: [String: [T]] = [:]
        var sortKeyByLabel: [String: (primary: Int, secondary: String)] = [:]
        var appearanceOrder: [String] = []

        for item in items {
            let (label, key) = Self.labelAndSortKey(forReason: reason(item))
            if itemsByLabel[label] == nil {
                itemsByLabel[label] = []
                sortKeyByLabel[label] = key
                appearanceOrder.append(label)
            }
            itemsByLabel[label]?.append(item)
        }

        let sortedLabels = appearanceOrder.sorted { lhs, rhs in
            let a = sortKeyByLabel[lhs]!
            let b = sortKeyByLabel[rhs]!
            if a.primary != b.primary { return a.primary < b.primary }
            return a.secondary < b.secondary
        }

        return sortedLabels.map { Group(label: $0, items: itemsByLabel[$0]!) }
    }

    /// 表示グループ判定に使う「実効 reason」を返す。
    ///
    /// GitHub は一度レビュー依頼された PR の更新を、その後コメントが付いても
    /// `reason=review_requested` のまま通知し続ける。そこで、現在も自分にレビュー依頼が
    /// 立っている PR（`activeReviewKeys`）に含まれない `review_requested` 通知は `comment`
    /// 扱いに補正し、Commented グループへ寄せる。
    ///
    /// - Parameters:
    ///   - activeReviewKeys: 現在レビュー依頼中の PR キー集合（`owner/repo#n`）。
    ///     未取得・取得失敗時は nil を渡す（その場合は補正しない＝誤って comment に落とさない）。
    public static func effectiveReason(reason: String,
                                       pullRequestKey: String?,
                                       activeReviewKeys: Set<String>?) -> String {
        guard reason == "review_requested",
              let active = activeReviewKeys,
              let key = pullRequestKey,
              !active.contains(key) else {
            return reason
        }
        return "comment"
    }

    /// `reason` を (表示ラベル, ソートキー) に対応づける。
    private static func labelAndSortKey(forReason reason: String) -> (label: String, key: (primary: Int, secondary: String)) {
        if let category = NotificationCategory(reason: reason),
           let index = NotificationCategory.allCases.firstIndex(of: category) {
            return (category.displayLabel, (index, ""))
        }
        if let known = NotificationReason(rawValue: reason),
           let index = NotificationReason.allCases.firstIndex(of: known) {
            return (known.displayLabel, (100 + index, ""))
        }
        // 未知 reason はラベルそのものを使い、アルファベット順で末尾へ。
        return (reason, (1000, reason))
    }
}
