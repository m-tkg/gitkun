import XCTest
@testable import gitkunCore

final class NotificationGroupingTests: XCTestCase {

    private func labels(_ reasons: [String]) -> [String] {
        NotificationGrouping.grouped(reasons) { $0 }.map(\.label)
    }

    // MARK: - 集約

    func testAggregatesReviewReasons() {
        let groups = NotificationGrouping.grouped(["review_requested", "approval_requested"]) { $0 }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.label, "Review Requested")
        XCTAssertEqual(groups.first?.items.count, 2)
    }

    func testAggregatesMentionReasons() {
        let groups = NotificationGrouping.grouped(["mention", "team_mention"]) { $0 }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.label, "Mentioned")
        XCTAssertEqual(groups.first?.items.count, 2)
    }

    func testCommentStateAuthorEachOwnCategory() {
        XCTAssertEqual(labels(["comment"]), ["Commented"])
        XCTAssertEqual(labels(["state_change"]), ["State Changed"])
        XCTAssertEqual(labels(["author"]), ["Authored"])
    }

    // MARK: - その他 reason は個別グループ維持

    func testOtherReasonsKeepIndividualGroups() {
        XCTAssertEqual(labels(["subscribed"]), ["Subscribed"])
        XCTAssertEqual(labels(["assign"]), ["Assigned"])
    }

    // MARK: - 並び順

    func testCategoriesComeBeforeOthersInDeclaredOrder() {
        let ls = labels(["subscribed", "author", "comment", "review_requested",
                         "mention", "state_change", "assign"])
        XCTAssertEqual(ls, ["Review Requested", "Mentioned", "Commented",
                            "State Changed", "Authored", "Assigned", "Subscribed"])
    }

    func testUnknownReasonGoesLast() {
        XCTAssertEqual(labels(["future_reason", "comment"]), ["Commented", "future_reason"])
    }

    // MARK: - グループ内の要素は保持

    func testItemsPreservedWithinGroup() {
        let groups = NotificationGrouping.grouped(["comment", "comment"]) { $0 }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.items.count, 2)
    }
}
