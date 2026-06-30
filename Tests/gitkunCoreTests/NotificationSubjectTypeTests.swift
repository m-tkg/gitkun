import XCTest
@testable import gitkunCore

final class NotificationSubjectTypeTests: XCTestCase {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func makeNotification(type: String?) -> GitHubNotification {
        GitHubNotification(
            id: "1",
            updatedAt: "2026-01-01T00:00:00Z",
            reason: "comment",
            subject: .init(title: "t", url: nil, type: type),
            repository: .init(fullName: "owner/repo",
                              htmlUrl: "https://github.com/owner/repo")
        )
    }

    // MARK: - JSON デコード

    func testDecodeSubjectTypePresent() throws {
        let json = """
        {"id":"1","updated_at":"2026-01-01T00:00:00Z","reason":"comment",
         "subject":{"title":"t","url":null,"type":"PullRequest"},
         "repository":{"full_name":"owner/repo","html_url":"https://github.com/owner/repo"}}
        """.data(using: .utf8)!
        let n = try Self.decoder.decode(GitHubNotification.self, from: json)
        XCTAssertEqual(n.subject.type, "PullRequest")
    }

    func testDecodeSubjectTypeMissing() throws {
        let json = """
        {"id":"1","updated_at":"2026-01-01T00:00:00Z","reason":"comment",
         "subject":{"title":"t","url":null},
         "repository":{"full_name":"owner/repo","html_url":"https://github.com/owner/repo"}}
        """.data(using: .utf8)!
        let n = try Self.decoder.decode(GitHubNotification.self, from: json)
        XCTAssertNil(n.subject.type)
    }

    // MARK: - enum マッピング

    func testDisplayLabels() {
        XCTAssertEqual(NotificationSubjectType.pullRequest.displayLabel, "Pull Request")
        XCTAssertEqual(NotificationSubjectType.issue.displayLabel, "Issue")
        XCTAssertEqual(NotificationSubjectType.commit.displayLabel, "Commit")
        XCTAssertEqual(NotificationSubjectType.release.displayLabel, "Release")
        XCTAssertEqual(NotificationSubjectType.discussion.displayLabel, "Discussion")
    }

    func testRawValueMapping() {
        XCTAssertEqual(NotificationSubjectType(rawValue: "PullRequest"), .pullRequest)
        XCTAssertEqual(NotificationSubjectType(rawValue: "Issue"), .issue)
        XCTAssertNil(NotificationSubjectType(rawValue: "CheckSuite"))
    }

    // MARK: - subjectTypeLabel / rowDetail

    func testSubjectTypeLabelKnown() {
        XCTAssertEqual(makeNotification(type: "PullRequest").subjectTypeLabel, "Pull Request")
        XCTAssertEqual(makeNotification(type: "Issue").subjectTypeLabel, "Issue")
    }

    func testSubjectTypeLabelUnknownReturnsRaw() {
        XCTAssertEqual(makeNotification(type: "CheckSuite").subjectTypeLabel, "CheckSuite")
    }

    func testSubjectTypeLabelNil() {
        XCTAssertNil(makeNotification(type: nil).subjectTypeLabel)
    }

    func testRowDetailMatchesSubjectTypeLabel() {
        XCTAssertEqual(makeNotification(type: "PullRequest").rowDetail, "Pull Request")
        XCTAssertNil(makeNotification(type: nil).rowDetail)
    }
}
