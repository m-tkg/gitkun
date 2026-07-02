import XCTest
@testable import gitkunCore

/// `PollingIntervalPolicy.effectiveSeconds` の挙動を固定する特性テスト。
final class PollingIntervalTests: XCTestCase {

    // MARK: - フォールバック（0以下・未設定相当）

    func testNonPositiveValuesFallBackTo30() {
        XCTAssertEqual(PollingIntervalPolicy.effectiveSeconds(0), 30)
        XCTAssertEqual(PollingIntervalPolicy.effectiveSeconds(-1), 30)
    }

    // MARK: - 1以上はそのまま使う

    func testPositiveValuesPassThrough() {
        XCTAssertEqual(PollingIntervalPolicy.effectiveSeconds(15), 15)
        XCTAssertEqual(PollingIntervalPolicy.effectiveSeconds(45), 45)
        XCTAssertEqual(PollingIntervalPolicy.effectiveSeconds(300), 300)
    }
}
