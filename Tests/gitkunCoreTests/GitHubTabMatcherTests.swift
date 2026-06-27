import XCTest
@testable import gitkunCore

final class GitHubTabMatcherTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: - 同じ PR / Issue とみなすケース

    func testSamePRConversationAndFilesMatch() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12"),
            url("https://github.com/m-tkg/gitkun/pull/12/files")))
    }

    func testSamePRWithCommitsSubpageMatches() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12/commits"),
            url("https://github.com/m-tkg/gitkun/pull/12")))
    }

    func testSamePRWithAnchorAndQueryMatches() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12"),
            url("https://github.com/m-tkg/gitkun/pull/12?foo=bar#issuecomment-999")))
    }

    func testSameIssueWithAnchorMatches() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/issues/5"),
            url("https://github.com/m-tkg/gitkun/issues/5#issue-123")))
    }

    func testTrailingSlashIsIgnored() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12/"),
            url("https://github.com/m-tkg/gitkun/pull/12")))
    }

    func testHostCaseIsIgnored() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://GitHub.com/m-tkg/gitkun/pull/12"),
            url("https://github.com/m-tkg/gitkun/pull/12")))
    }

    func testRepositoryRootWithTrailingSlashMatches() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun"),
            url("https://github.com/m-tkg/gitkun/")))
    }

    // MARK: - 別物とみなすケース

    func testDifferentPRNumberDoesNotMatch() {
        XCTAssertFalse(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12"),
            url("https://github.com/m-tkg/gitkun/pull/13")))
    }

    func testDifferentRepoDoesNotMatch() {
        XCTAssertFalse(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12"),
            url("https://github.com/m-tkg/other/pull/12")))
    }

    func testPRAndIssueWithSameNumberDoNotMatch() {
        XCTAssertFalse(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/pull/12"),
            url("https://github.com/m-tkg/gitkun/issues/12")))
    }

    // MARK: - PR / Issue 以外はパス完全一致

    func testSameReleasePageMatches() {
        XCTAssertTrue(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/releases/tag/v1.9.0"),
            url("https://github.com/m-tkg/gitkun/releases/tag/v1.9.0/")))
    }

    func testReleaseTagAndReleaseListDoNotMatch() {
        XCTAssertFalse(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/releases/tag/v1.9.0"),
            url("https://github.com/m-tkg/gitkun/releases")))
    }

    func testCommitSubpageDoesNotTruncate() {
        // commit は番号セグメントを持たないのでパス完全一致のみ
        XCTAssertFalse(GitHubTabMatcher.matches(
            url("https://github.com/m-tkg/gitkun/commit/abc123"),
            url("https://github.com/m-tkg/gitkun/commit/def456")))
    }
}
