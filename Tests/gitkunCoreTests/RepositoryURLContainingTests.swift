import XCTest
@testable import gitkunCore

final class RepositoryURLContainingTests: XCTestCase {

    private struct Fixture: RepositoryURLContaining {
        let repositoryUrl: String
    }

    func testDerivesOwnerAndRepo() {
        let fixture = Fixture(repositoryUrl: "https://api.github.com/repos/m-tkg/gitkun")
        XCTAssertEqual(fixture.repositoryFullName, "m-tkg/gitkun")
    }

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(Fixture(repositoryUrl: "").repositoryFullName, "")
    }

    func testTooShortPathReturnsEmpty() {
        XCTAssertEqual(Fixture(repositoryUrl: "https://api.github.com/repos").repositoryFullName, "")
    }
}
