import XCTest
@testable import gitkunCore

/// `NotificationBanner.body(for:)` の現行挙動を固定する特性テスト。
final class NotificationBannerTests: XCTestCase {

    private func makeItem(title: String) -> AssignedItem {
        AssignedItem(
            id: 1,
            title: title,
            htmlUrl: "https://github.com/owner/repo/issues/1",
            repositoryUrl: "https://api.github.com/repos/owner/repo",
            updatedAt: "2026-01-01T00:00:00Z",
            pullRequest: nil
        )
    }

    func testEmptyItemsReturnsNil() {
        XCTAssertNil(NotificationBanner.body(for: []))
    }

    func testSingleItemReturnsTitleOnly() {
        let items: [any MenuRowDisplayable] = [makeItem(title: "Fix bug")]
        XCTAssertEqual(NotificationBanner.body(for: items), "Fix bug")
    }

    func testMultipleItemsAppendsMoreCount() {
        let items: [any MenuRowDisplayable] = [
            makeItem(title: "Fix bug"),
            makeItem(title: "Add feature"),
            makeItem(title: "Refactor"),
        ]
        XCTAssertEqual(NotificationBanner.body(for: items), "Fix bug (+2 more)")
    }
}
