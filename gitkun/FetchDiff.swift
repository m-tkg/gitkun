import Foundation

/// フェッチ結果に対する新規判定・マージの純粋ロジック。
/// 副作用を持たないため `AppState` から独立してテストできる。
enum FetchDiff {

    /// `fetched` のうち `known` に含まれない ID を持つ要素（新規）と、
    /// 次回の既知 ID 集合（今回フェッチした全 ID）を返す。
    /// フェッチ結果から消えた ID は既知集合に残らない。
    static func newItems<Item: Identifiable>(
        fetched: [Item],
        known: Set<Item.ID>
    ) -> (newOnes: [Item], nextKnown: Set<Item.ID>) {
        let fetchedIDs = Set(fetched.map(\.id))
        let newIDs = fetchedIDs.subtracting(known)
        return (fetched.filter { newIDs.contains($0.id) }, fetchedIDs)
    }

    /// assignee:@me と author:@me の検索結果から PR のみを id で重複排除
    /// （同一 id は assigned 側を優先）し、updatedAt 降順で最大 `limit` 件返す。
    static func mergeMyPRs(assigned: [AssignedItem]?,
                           authored: [AssignedItem]?,
                           limit: Int) -> [AssignedItem] {
        var prsByID: [Int: AssignedItem] = [:]
        for item in (assigned ?? []) where item.isPullRequest {
            prsByID[item.id] = item
        }
        for item in (authored ?? []) where item.isPullRequest && prsByID[item.id] == nil {
            prsByID[item.id] = item
        }
        return Array(prsByID.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
}
