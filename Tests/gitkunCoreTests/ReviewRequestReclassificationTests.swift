import XCTest
@testable import gitkunCore

final class ReviewRequestReclassificationTests: XCTestCase {

    private func notification(reason: String, subjectURL: String?) -> GitHubNotification {
        GitHubNotification(
            id: "1",
            updatedAt: "2026-01-01T00:00:00Z",
            reason: reason,
            subject: .init(title: "t", url: subjectURL, type: "PullRequest"),
            repository: .init(fullName: "owner/repo",
                              htmlUrl: "https://github.com/owner/repo")
        )
    }

    // MARK: - PR キー導出

    func testPullRequestKeyFromPullsURL() {
        let n = notification(reason: "review_requested",
                             subjectURL: "https://api.github.com/repos/owner/repo/pulls/160441")
        XCTAssertEqual(n.pullRequestKey, "owner/repo#160441")
    }

    func testPullRequestKeyNilForIssueURL() {
        let n = notification(reason: "comment",
                             subjectURL: "https://api.github.com/repos/owner/repo/issues/123")
        XCTAssertNil(n.pullRequestKey)
    }

    func testPullRequestKeyNilForNilURL() {
        XCTAssertNil(notification(reason: "review_requested", subjectURL: nil).pullRequestKey)
    }

    func testUnreviewedPRKeyMatchesNotificationKey() {
        let pr = UnreviewedPR(
            id: 1, number: 160441, title: "t",
            htmlUrl: "https://github.com/owner/repo/pull/160441",
            repositoryUrl: "https://api.github.com/repos/owner/repo",
            updatedAt: "2026-01-01T00:00:00Z", draft: false, labels: []
        )
        XCTAssertEqual(pr.prKey, "owner/repo#160441")
    }

    // MARK: - effectiveReason 補正

    func testReviewRequestedStillActiveKeepsReason() {
        let reason = NotificationGrouping.effectiveReason(
            reason: "review_requested",
            pullRequestKey: "owner/repo#159489",
            activeReviewKeys: ["owner/repo#159489"]
        )
        XCTAssertEqual(reason, "review_requested")
    }

    func testReviewRequestedNoLongerActiveBecomesComment() {
        let reason = NotificationGrouping.effectiveReason(
            reason: "review_requested",
            pullRequestKey: "owner/repo#160441",
            activeReviewKeys: ["owner/repo#159489"]
        )
        XCTAssertEqual(reason, "comment")
    }

    func testActiveKeysNilDoesNotReclassify() {
        // レビュー検索が未取得/失敗のときは補正しない（誤って comment に落とさない）。
        let reason = NotificationGrouping.effectiveReason(
            reason: "review_requested",
            pullRequestKey: "owner/repo#160441",
            activeReviewKeys: nil
        )
        XCTAssertEqual(reason, "review_requested")
    }

    func testUnknownPullRequestKeyKeepsReason() {
        let reason = NotificationGrouping.effectiveReason(
            reason: "review_requested",
            pullRequestKey: nil,
            activeReviewKeys: ["owner/repo#159489"]
        )
        XCTAssertEqual(reason, "review_requested")
    }

    func testNonReviewReasonUnaffected() {
        let reason = NotificationGrouping.effectiveReason(
            reason: "comment",
            pullRequestKey: "owner/repo#160441",
            activeReviewKeys: ["owner/repo#159489"]
        )
        XCTAssertEqual(reason, "comment")
    }

    // MARK: - グルーピングとの統合

    func testReclassifiedReviewGoesToCommentedGroup() {
        let active: Set<String> = ["owner/repo#159489"]
        let notifs = [
            notification(reason: "review_requested",
                         subjectURL: "https://api.github.com/repos/owner/repo/pulls/159489"),
            notification(reason: "review_requested",
                         subjectURL: "https://api.github.com/repos/owner/repo/pulls/160441"),
        ]
        let groups = NotificationGrouping.grouped(notifs) {
            NotificationGrouping.effectiveReason(
                reason: $0.reason,
                pullRequestKey: $0.pullRequestKey,
                activeReviewKeys: active
            )
        }
        XCTAssertEqual(groups.map(\.label), ["Review Requested", "Commented"])
        XCTAssertEqual(groups.first { $0.label == "Review Requested" }?.items.count, 1)
        XCTAssertEqual(groups.first { $0.label == "Commented" }?.items.count, 1)
    }
}
