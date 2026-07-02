import XCTest
@testable import gitkunCore

/// `RelativeTime.format(iso:now:)` の現行挙動を固定する特性テスト。
final class RelativeTimeTests: XCTestCase {

    func testUnparsableISOReturnsEmptyString() {
        XCTAssertEqual(RelativeTime.format(iso: "not-a-date", now: Date()), "")
    }

    func testValidISOReturnsNonEmptyString() {
        let result = RelativeTime.format(iso: "2026-01-01T00:00:00Z", now: Date())
        XCTAssertFalse(result.isEmpty)
    }
}
