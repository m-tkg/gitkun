import XCTest
@testable import gitkunCore

/// `UnreviewedPR.webURL` / `AssignedItem.webURL`（`MenuRowDisplayable` 準拠）の現行挙動を固定する特性テスト。
final class MenuRowDisplayableTests: XCTestCase {

    private func makePR(htmlUrl: String) -> UnreviewedPR {
        UnreviewedPR(
            id: 1,
            number: 10,
            title: "Add feature",
            htmlUrl: htmlUrl,
            repositoryUrl: "https://api.github.com/repos/owner/repo",
            updatedAt: "2026-01-01T00:00:00Z",
            draft: false,
            labels: []
        )
    }

    private func makeAssignedItem(htmlUrl: String) -> AssignedItem {
        AssignedItem(
            id: 1,
            title: "item",
            htmlUrl: htmlUrl,
            repositoryUrl: "https://api.github.com/repos/owner/repo",
            updatedAt: "2026-01-01T00:00:00Z",
            pullRequest: nil
        )
    }

    // MARK: - UnreviewedPR.webURL

    func testUnreviewedPRWebURLReturnsValidURL() {
        let pr = makePR(htmlUrl: "https://github.com/owner/repo/pull/10")
        XCTAssertEqual(pr.webURL, URL(string: "https://github.com/owner/repo/pull/10"))
    }

    func testUnreviewedPRWebURLFallsBackOnEmptyString() {
        let pr = makePR(htmlUrl: "")
        XCTAssertEqual(pr.webURL, URL(string: "https://github.com"))
    }

    func testUnreviewedPRWebURLFallsBackOnInvalidURLString() {
        let pr = makePR(htmlUrl: "ht tp://x")
        XCTAssertEqual(pr.webURL, URL(string: "https://github.com"))
    }

    // MARK: - AssignedItem.webURL

    func testAssignedItemWebURLReturnsValidURL() {
        let item = makeAssignedItem(htmlUrl: "https://github.com/owner/repo/issues/5")
        XCTAssertEqual(item.webURL, URL(string: "https://github.com/owner/repo/issues/5"))
    }

    func testAssignedItemWebURLFallsBackOnEmptyString() {
        let item = makeAssignedItem(htmlUrl: "")
        XCTAssertEqual(item.webURL, URL(string: "https://github.com"))
    }

    func testAssignedItemWebURLFallsBackOnInvalidURLString() {
        let item = makeAssignedItem(htmlUrl: "ht tp://x")
        XCTAssertEqual(item.webURL, URL(string: "https://github.com"))
    }
}
