import XCTest
@testable import gitkunCore

/// `FetchErrors` の現行挙動を固定する特性テスト。
final class FetchErrorsTests: XCTestCase {

    func testAllSuccessIsEmpty() {
        var errors = FetchErrors()
        let value: Int? = errors.unwrap(.success(1) as Result<Int, AppError>)
        XCTAssertEqual(value, 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func testMultipleFailuresJoinDetailWithNewlineAndStatusLabelWithComma() {
        var errors = FetchErrors()
        let a: Int? = errors.unwrap(.failure(.ghNotFound) as Result<Int, AppError>)
        let b: Int? = errors.unwrap(.failure(.fetchFailed("boom")) as Result<Int, AppError>)

        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertEqual(errors.detail, "gh not found\nfetch failed: boom")
        XCTAssertEqual(errors.statusLabel, "gh not found, fetch failed")
    }

    func testUnwrapReturnsNilOnFailure() {
        var errors = FetchErrors()
        let value: Int? = errors.unwrap(.failure(.authRequired) as Result<Int, AppError>)
        XCTAssertNil(value)
    }

    func testUnwrapReturnsValueOnSuccess() {
        var errors = FetchErrors()
        let value: String? = errors.unwrap(.success("ok") as Result<String, AppError>)
        XCTAssertEqual(value, "ok")
    }
}
