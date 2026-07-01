import XCTest
@testable import gitkunCore

/// `AppError` の現行挙動を固定する特性テスト。
final class AppErrorTests: XCTestCase {

    // MARK: - errorDescription

    func testGhNotFoundErrorDescription() {
        XCTAssertEqual(AppError.ghNotFound.errorDescription, "gh not found")
    }

    func testAuthRequiredErrorDescription() {
        XCTAssertEqual(AppError.authRequired.errorDescription, "auth required")
    }

    func testFetchFailedErrorDescriptionEmbedsMessage() {
        XCTAssertEqual(AppError.fetchFailed("boom").errorDescription, "fetch failed: boom")
    }

    func testParseErrorErrorDescriptionEmbedsMessage() {
        XCTAssertEqual(AppError.parseError("bad json").errorDescription, "parse error: bad json")
    }

    // MARK: - statusLabel

    func testGhNotFoundStatusLabel() {
        XCTAssertEqual(AppError.ghNotFound.statusLabel, "gh not found")
    }

    func testAuthRequiredStatusLabel() {
        XCTAssertEqual(AppError.authRequired.statusLabel, "auth required")
    }

    func testFetchFailedStatusLabelDoesNotEmbedMessage() {
        XCTAssertEqual(AppError.fetchFailed("boom").statusLabel, "fetch failed")
    }

    func testParseErrorStatusLabelDoesNotEmbedMessage() {
        XCTAssertEqual(AppError.parseError("bad json").statusLabel, "parse error")
    }
}
