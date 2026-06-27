import XCTest
@testable import gitkunCore

final class VersionComparatorTests: XCTestCase {

    func testNewerPatchVersion() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.2.1", than: "1.2.0"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.2.0", than: "1.2.0"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.1.9", than: "1.2.0"))
    }

    func testUppercaseVPrefix() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "V1.3", than: "1.2.9"))
    }

    func testMissingComponentsAreTreatedAsZero() {
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.2", than: "1.2.0"))
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.2.1", than: "1.2"))
    }

    func testNumericNotLexicographicComparison() {
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.10.0", than: "1.9.0"))
    }

    func testPreReleaseSuffixUsesLeadingDigitsOnly() {
        // "0-beta" は数字部分のみ採用され 0 として扱われる
        XCTAssertFalse(VersionComparator.isNewer(tag: "v1.2.0-beta", than: "1.2.0"))
        XCTAssertTrue(VersionComparator.isNewer(tag: "v1.2.1-beta", than: "1.2.0"))
    }
}
