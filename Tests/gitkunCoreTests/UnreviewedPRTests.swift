import XCTest
@testable import gitkunCore

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

    func testSearchResponseDecodesWithoutRequestCategories() throws {
        let json = """
        {"id":1,"number":10,"title":"PR","html_url":"https://github.com/o/r/pull/10",
         "repository_url":"https://api.github.com/repos/o/r","updated_at":"2026-01-01T00:00:00Z",
         "draft":false,"labels":[]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let pr = try decoder.decode(UnreviewedPR.self, from: Data(json.utf8))
        XCTAssertFalse(pr.isPersonalRequest)
        XCTAssertFalse(pr.isTeamRequest)
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
