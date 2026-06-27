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
            number: id,
            title: title ?? "item\(id)",
            htmlUrl: "https://github.com/o/r/pull/\(id)",
            repositoryUrl: "https://api.github.com/repos/o/r",
            updatedAt: updatedAt,
            pullRequest: isPR ? .init(url: nil) : nil
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
