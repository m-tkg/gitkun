import XCTest

final class URLResolverTests: XCTestCase {

    private func makeNotification(subjectURL: String?) -> GitHubNotification {
        GitHubNotification(
            id: "1",
            updatedAt: "2026-01-01T00:00:00Z",
            reason: "mention",
            subject: .init(title: "t", url: subjectURL),
            repository: .init(fullName: "owner/repo",
                              htmlUrl: "https://github.com/owner/repo")
        )
    }

    func testIssueURL() {
        let n = makeNotification(subjectURL: "https://api.github.com/repos/owner/repo/issues/123")
        XCTAssertEqual(URLResolver.resolve(notification: n).absoluteString,
                       "https://github.com/owner/repo/issues/123")
    }

    func testPullRequestURLUsesSingularPath() {
        let n = makeNotification(subjectURL: "https://api.github.com/repos/owner/repo/pulls/5")
        XCTAssertEqual(URLResolver.resolve(notification: n).absoluteString,
                       "https://github.com/owner/repo/pull/5")
    }

    func testCommitURLUsesSingularPath() {
        let n = makeNotification(subjectURL: "https://api.github.com/repos/owner/repo/commits/abc123")
        XCTAssertEqual(URLResolver.resolve(notification: n).absoluteString,
                       "https://github.com/owner/repo/commit/abc123")
    }

    func testNilSubjectURLFallsBackToRepositoryURL() {
        let n = makeNotification(subjectURL: nil)
        XCTAssertEqual(URLResolver.resolve(notification: n).absoluteString,
                       "https://github.com/owner/repo")
    }

    func testQueryParametersAreStripped() {
        let n = makeNotification(subjectURL: "https://api.github.com/repos/owner/repo/issues/1?foo=bar")
        XCTAssertEqual(URLResolver.resolve(notification: n).absoluteString,
                       "https://github.com/owner/repo/issues/1")
    }
}
