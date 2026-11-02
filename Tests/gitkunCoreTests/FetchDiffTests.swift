import XCTest
@testable import gitkunCore

final class FetchDiffTests: XCTestCase {

    private struct Item: Identifiable, Equatable {
        let id: Int
    }

    func testAllNewWhenKnownIsEmpty() {
        let result = FetchDiff.newItems(fetched: [Item(id: 1), Item(id: 2)], known: [])
        XCTAssertEqual(result.newOnes, [Item(id: 1), Item(id: 2)])
        XCTAssertEqual(result.nextKnown, [1, 2])
    }

    func testKnownItemsAreNotNew() {
        let result = FetchDiff.newItems(fetched: [Item(id: 1), Item(id: 2)], known: [1])
        XCTAssertEqual(result.newOnes, [Item(id: 2)])
        XCTAssertEqual(result.nextKnown, [1, 2])
    }

    func testDisappearedKnownIDsAreDropped() {
        // フェッチ結果から消えた ID は次回の既知集合に残らない（現行挙動の維持）
        let result = FetchDiff.newItems(fetched: [Item(id: 3)], known: [1, 2])
        XCTAssertEqual(result.newOnes, [Item(id: 3)])
        XCTAssertEqual(result.nextKnown, [3])
    }

    func testEmptyFetchYieldsEmpty() {
        let result = FetchDiff.newItems(fetched: [Item](), known: [1])
        XCTAssertTrue(result.newOnes.isEmpty)
        XCTAssertTrue(result.nextKnown.isEmpty)
    }
}

final class MyPRsMergeTests: XCTestCase {

    private func makeItem(id: Int,
                          isPR: Bool = true,
                          title: String? = nil,
                          updatedAt: String = "2026-01-01T00:00:00Z") -> AssignedItem {
        AssignedItem(
            id: id,
            title: title ?? "item\(id)",
            htmlUrl: "https://github.com/o/r/pull/\(id)",
            repositoryUrl: "https://api.github.com/repos/o/r",
            updatedAt: updatedAt,
            pullRequest: isPR ? .init() : nil
        )
    }

    func testIssuesAreExcluded() {
        let merged = FetchDiff.mergeMyPRs(
            assigned: [makeItem(id: 1, isPR: false), makeItem(id: 2)],
            authored: [makeItem(id: 3, isPR: false)],
            limit: 50)
        XCTAssertEqual(merged.map(\.id), [2])
    }

    func testDedupePrefersAssignedSide() {
        let merged = FetchDiff.mergeMyPRs(
            assigned: [makeItem(id: 1, title: "assigned")],
            authored: [makeItem(id: 1, title: "authored")],
            limit: 50)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "assigned")
    }

    func testSortedByUpdatedAtDescending() {
        let merged = FetchDiff.mergeMyPRs(
            assigned: [makeItem(id: 1, updatedAt: "2026-01-01T00:00:00Z")],
            authored: [makeItem(id: 2, updatedAt: "2026-03-01T00:00:00Z"),
                       makeItem(id: 3, updatedAt: "2026-02-01T00:00:00Z")],
            limit: 50)
        XCTAssertEqual(merged.map(\.id), [2, 3, 1])
    }

    func testNilInputsAreTreatedAsEmpty() {
        XCTAssertEqual(FetchDiff.mergeMyPRs(assigned: nil, authored: nil, limit: 50).count, 0)
        XCTAssertEqual(FetchDiff.mergeMyPRs(assigned: nil,
                                            authored: [makeItem(id: 1)],
                                            limit: 50).map(\.id), [1])
    }

    func testLimitIsApplied() {
        let many = (1...60).map { makeItem(id: $0, updatedAt: String(format: "2026-01-01T00:00:%02dZ", $0 % 60)) }
        let merged = FetchDiff.mergeMyPRs(assigned: many, authored: nil, limit: 50)
        XCTAssertEqual(merged.count, 50)
    }
}

final class ReviewRequestsFilterTests: XCTestCase {

    private func makePR(id: Int,
                         draft: Bool = false,
                         title: String = "title",
                         labelNames: [String] = []) -> UnreviewedPR {
        UnreviewedPR(
            id: id,
            number: id,
            title: title,
            htmlUrl: "https://github.com/o/r/pull/\(id)",
            repositoryUrl: "https://api.github.com/repos/o/r",
            updatedAt: "2026-01-01T00:00:00Z",
            draft: draft,
            labels: labelNames.map { UnreviewedPR.Label(name: $0) }
        )
    }

    func testMergeReviewRequestsPreservesBothCategoriesAndDeduplicates() {
        let personal = [makePR(id: 1), makePR(id: 2)]
        let team = [makePR(id: 2), makePR(id: 3)]
        let result = FetchDiff.mergeReviewRequests(personal: personal, team: team)
        XCTAssertEqual(Set(result.map(\.id)), [1, 2, 3])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result.filter(\.isPersonalRequest).map(\.id)), [1, 2])
        XCTAssertEqual(Set(result.filter(\.isTeamRequest).map(\.id)), [2, 3])
        XCTAssertEqual(FetchDiff.newItems(fetched: result, known: []).newOnes.count, 3)
    }

    func testEachReviewRequestCategoryHasItsOwnLimit() {
        var shared = makePR(id: 1)
        shared.isPersonalRequest = true
        shared.isTeamRequest = true
        var personal = (2...25).map { makePR(id: $0) }
        var team = (26...49).map { makePR(id: $0) }
        for index in personal.indices { personal[index].isPersonalRequest = true }
        for index in team.indices { team[index].isTeamRequest = true }
        let result = FetchDiff.reviewRequests(fetched: [shared] + personal + team, limit: 20)
        XCTAssertEqual(result.personal.count, 20)
        XCTAssertEqual(result.team.count, 20)
        XCTAssertTrue(result.personal.allSatisfy(\.isPersonalRequest))
        XCTAssertTrue(result.team.allSatisfy(\.isTeamRequest))
        XCTAssertEqual(result.personal.first?.id, 1)
        XCTAssertEqual(result.team.first?.id, 1)
    }

    func testReviewRequestCategoriesKeepFetchedOrderAndHandleEmptyCategory() {
        var personal = (1...3).map { makePR(id: $0) }
        for index in personal.indices { personal[index].isPersonalRequest = true }
        let result = FetchDiff.reviewRequests(fetched: personal, limit: 2)
        XCTAssertEqual(result.personal.map(\.id), [1, 2])
        XCTAssertTrue(result.team.isEmpty)
    }
}

final class AssignedIssuesExtractionTests: XCTestCase {

    private func makeItem(id: Int, isPR: Bool) -> AssignedItem {
        AssignedItem(
            id: id,
            title: "item\(id)",
            htmlUrl: "https://github.com/o/r/issues/\(id)",
            repositoryUrl: "https://api.github.com/repos/o/r",
            updatedAt: "2026-01-01T00:00:00Z",
            pullRequest: isPR ? .init() : nil
        )
    }

    func testExtractsOnlyIssuesFromMixedList() {
        let mixed = [
            makeItem(id: 1, isPR: true),
            makeItem(id: 2, isPR: false),
            makeItem(id: 3, isPR: true),
            makeItem(id: 4, isPR: false),
        ]
        let result = FetchDiff.assignedIssues(from: mixed, limit: 50)
        XCTAssertEqual(result.map(\.id), [2, 4])
    }

    func testLimitIsApplied() {
        let issues = (1...60).map { makeItem(id: $0, isPR: false) }
        let result = FetchDiff.assignedIssues(from: issues, limit: 50)
        XCTAssertEqual(result.count, 50)
    }
}
