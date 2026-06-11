import XCTest

final class UnreviewedPRTests: XCTestCase {

    private func makePR(title: String = "Add feature",
                        draft: Bool = false,
                        labels: [String] = []) -> UnreviewedPR {
        UnreviewedPR(
            id: 1,
            number: 10,
            title: title,
            htmlUrl: "https://github.com/owner/repo/pull/10",
            repositoryUrl: "https://api.github.com/repos/owner/repo",
            updatedAt: "2026-01-01T00:00:00Z",
            draft: draft,
            labels: labels.map { .init(name: $0) }
        )
    }

    func testNormalPRIsReviewWaiting() {
        XCTAssertTrue(makePR().isReviewWaiting)
    }

    func testDraftPRIsNotReviewWaiting() {
        XCTAssertFalse(makePR(draft: true).isReviewWaiting)
    }

    func testWIPTitlePrefixIsNotReviewWaiting() {
        XCTAssertFalse(makePR(title: "[WIP] Add feature").isReviewWaiting)
        XCTAssertFalse(makePR(title: "[wip] Add feature").isReviewWaiting)
    }

    func testWIPLabelIsNotReviewWaiting() {
        XCTAssertFalse(makePR(labels: ["WIP"]).isReviewWaiting)
        XCTAssertFalse(makePR(labels: ["wip"]).isReviewWaiting)
    }

    func testWIPInMiddleOfTitleIsStillReviewWaiting() {
        XCTAssertTrue(makePR(title: "Fix wip handling").isReviewWaiting)
    }
}
