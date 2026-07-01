import XCTest
@testable import gitkunCore

/// `PollingInterval` の現行挙動を固定する特性テスト。
final class PollingIntervalTests: XCTestCase {

    // MARK: - 有効値

    func testValidRawValuesMapToExpectedCases() {
        XCTAssertEqual(PollingInterval(rawValue: 15), .sec15)
        XCTAssertEqual(PollingInterval(rawValue: 30), .sec30)
        XCTAssertEqual(PollingInterval(rawValue: 60), .sec60)
        XCTAssertEqual(PollingInterval(rawValue: 120), .sec120)
        XCTAssertEqual(PollingInterval(rawValue: 300), .sec300)
    }

    // MARK: - 無効値

    func testInvalidRawValuesReturnNil() {
        XCTAssertNil(PollingInterval(rawValue: 0))
        XCTAssertNil(PollingInterval(rawValue: 45))
        XCTAssertNil(PollingInterval(rawValue: -1))
    }
}
