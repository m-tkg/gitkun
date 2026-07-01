import XCTest
@testable import gitkunCore

/// `NotificationReason` の現行挙動を固定する特性テスト。
final class NotificationReasonTests: XCTestCase {

    // MARK: - displayLabel（全ケース）

    func testDisplayLabels() {
        XCTAssertEqual(NotificationReason.mention.displayLabel, "Mentioned")
        XCTAssertEqual(NotificationReason.reviewRequested.displayLabel, "Review Requested")
        XCTAssertEqual(NotificationReason.approvalRequested.displayLabel, "Approval Requested")
        XCTAssertEqual(NotificationReason.assign.displayLabel, "Assigned")
        XCTAssertEqual(NotificationReason.authorField.displayLabel, "Authored")
        XCTAssertEqual(NotificationReason.comment.displayLabel, "Commented")
        XCTAssertEqual(NotificationReason.stateChange.displayLabel, "State Changed")
        XCTAssertEqual(NotificationReason.ciActivity.displayLabel, "CI Activity")
        XCTAssertEqual(NotificationReason.push.displayLabel, "Pushed")
        XCTAssertEqual(NotificationReason.teamMention.displayLabel, "Team Mentioned")
        XCTAssertEqual(NotificationReason.securityAlert.displayLabel, "Security Alert")
        XCTAssertEqual(NotificationReason.subscribed.displayLabel, "Subscribed")
        XCTAssertEqual(NotificationReason.manual.displayLabel, "Manual")
        XCTAssertEqual(NotificationReason.invitation.displayLabel, "Invitation")
        XCTAssertEqual(NotificationReason.memberFeatureRequested.displayLabel, "Member Feature Requested")
    }

    // MARK: - allCases 宣言順（メニュー表示優先順の固定）

    func testAllCasesDeclarationOrder() {
        XCTAssertEqual(NotificationReason.allCases, [
            .mention,
            .reviewRequested,
            .approvalRequested,
            .assign,
            .authorField,
            .comment,
            .stateChange,
            .ciActivity,
            .push,
            .teamMention,
            .securityAlert,
            .subscribed,
            .manual,
            .invitation,
            .memberFeatureRequested,
        ])
    }

    func testAllCasesCount() {
        XCTAssertEqual(NotificationReason.allCases.count, 15)
    }

    // MARK: - rawValue からの生成

    func testKnownRawValuesMapToExpectedCases() {
        XCTAssertEqual(NotificationReason(rawValue: "mention"), .mention)
        XCTAssertEqual(NotificationReason(rawValue: "review_requested"), .reviewRequested)
        XCTAssertEqual(NotificationReason(rawValue: "approval_requested"), .approvalRequested)
        XCTAssertEqual(NotificationReason(rawValue: "assign"), .assign)
        XCTAssertEqual(NotificationReason(rawValue: "author"), .authorField)
        XCTAssertEqual(NotificationReason(rawValue: "comment"), .comment)
        XCTAssertEqual(NotificationReason(rawValue: "state_change"), .stateChange)
        XCTAssertEqual(NotificationReason(rawValue: "ci_activity"), .ciActivity)
        XCTAssertEqual(NotificationReason(rawValue: "push"), .push)
        XCTAssertEqual(NotificationReason(rawValue: "team_mention"), .teamMention)
        XCTAssertEqual(NotificationReason(rawValue: "security_alert"), .securityAlert)
        XCTAssertEqual(NotificationReason(rawValue: "subscribed"), .subscribed)
        XCTAssertEqual(NotificationReason(rawValue: "manual"), .manual)
        XCTAssertEqual(NotificationReason(rawValue: "invitation"), .invitation)
        XCTAssertEqual(NotificationReason(rawValue: "member_feature_requested"), .memberFeatureRequested)
    }

    func testUnknownRawValueReturnsNil() {
        XCTAssertNil(NotificationReason(rawValue: "future_reason"))
    }
}
