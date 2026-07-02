import XCTest
@testable import gitkunCore

final class MenuBarIconTests: XCTestCase {

    func testNoUnreadNoUnreviewed() {
        XCTAssertEqual(
            MenuBarIcon.assetName(hasUnread: false, hasUnreviewed: false),
            "MenuBarIcon")
    }

    func testUnreadOnly() {
        XCTAssertEqual(
            MenuBarIcon.assetName(hasUnread: true, hasUnreviewed: false),
            "MenuBarIconUnread")
    }

    func testUnreviewedOnly() {
        XCTAssertEqual(
            MenuBarIcon.assetName(hasUnread: false, hasUnreviewed: true),
            "MenuBarIconUnreview")
    }

    func testUnreadAndUnreviewed() {
        XCTAssertEqual(
            MenuBarIcon.assetName(hasUnread: true, hasUnreviewed: true),
            "MenuBarIconUnreadAndUnreview")
    }
}
