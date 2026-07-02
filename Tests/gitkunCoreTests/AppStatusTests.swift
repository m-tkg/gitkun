import XCTest
@testable import gitkunCore

/// `AppStatus.displayLabel` の現行挙動を固定する特性テスト。
final class AppStatusTests: XCTestCase {

    func testIdleDisplayLabel() {
        XCTAssertEqual(AppStatus.idle.displayLabel, "Status: -")
    }

    func testLoadingDisplayLabel() {
        XCTAssertEqual(AppStatus.loading.displayLabel, "Status: Loading...")
    }

    func testOkDisplayLabel() {
        XCTAssertEqual(AppStatus.ok.displayLabel, "Status: OK")
    }

    func testErrorDisplayLabelEmbedsMessage() {
        XCTAssertEqual(AppStatus.error("fetch failed").displayLabel, "Status: fetch failed")
    }
}
