import Foundation

// MARK: - 通知

public struct GitHubNotification: Decodable, Identifiable {
    public let id: String
    public let updatedAt: String
    public let reason: String
    public let subject: Subject
    public let repository: Repository

    public struct Subject: Decodable {
        public let title: String
        public let url: String?
        /// 通知対象のリソース種別（`PullRequest` / `Issue` / `Commit` / `Release` / `Discussion` …）。
        public let type: String?

        public init(title: String, url: String?, type: String? = nil) {
            self.title = title
            self.url = url
            self.type = type
        }
    }

    public struct Repository: Decodable {
        public let fullName: String
        public let htmlUrl: String
    }
}

/// `/notifications` の reason 値。UI 上でのグルーピング順と表示ラベルを持つ。
/// 参考: https://docs.github.com/ja/rest/activity/notifications
public enum NotificationReason: String, CaseIterable {
    case mention
    case reviewRequested = "review_requested"
    case approvalRequested = "approval_requested"
    case assign
    case authorField = "author"
    case comment
    case stateChange = "state_change"
    case ciActivity = "ci_activity"
    case push
    case teamMention = "team_mention"
    case securityAlert = "security_alert"
    case subscribed
    case manual
    case invitation
    case memberFeatureRequested = "member_feature_requested"

    public var displayLabel: String {
        switch self {
        case .mention:                return "Mentioned"
        case .reviewRequested:        return "Review Requested"
        case .approvalRequested:      return "Approval Requested"
        case .assign:                 return "Assigned"
        case .authorField:            return "Authored"
        case .comment:                return "Commented"
        case .stateChange:            return "State Changed"
        case .ciActivity:             return "CI Activity"
        case .push:                   return "Pushed"
        case .teamMention:            return "Team Mentioned"
        case .securityAlert:          return "Security Alert"
        case .subscribed:             return "Subscribed"
        case .manual:                 return "Manual"
        case .invitation:             return "Invitation"
        case .memberFeatureRequested: return "Member Feature Requested"
        }
    }
}

/// `/notifications` の `subject.type` 値。通知行に種別を表示するために使う。
/// 未知・nil は表示しない（補助情報なので欠落しても破綻させない）。
public enum NotificationSubjectType: String {
    case pullRequest = "PullRequest"
    case issue = "Issue"
    case commit = "Commit"
    case release = "Release"
    case discussion = "Discussion"

    public var displayLabel: String {
        switch self {
        case .pullRequest: return "Pull Request"
        case .issue:       return "Issue"
        case .commit:      return "Commit"
        case .release:     return "Release"
        case .discussion:  return "Discussion"
        }
    }
}

extension GitHubNotification {
    /// `subject.type` を表示用ラベルに正規化する。未知 raw 値はそのまま、nil は nil。
    public var subjectTypeLabel: String? {
        guard let raw = subject.type else { return nil }
        return NotificationSubjectType(rawValue: raw)?.displayLabel ?? raw
    }

    /// `subject.url` が PR（`.../pulls/{n}`）を指すとき `owner/repo#n` を返す。それ以外は nil。
    /// レビュー依頼の再分類で `UnreviewedPR.prKey` と突き合わせるためのキー。
    public var pullRequestKey: String? {
        guard let urlString = subject.url,
              let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents
        // [..., "repos", owner, repo, "pulls", number]
        guard parts.count >= 5, parts[parts.count - 2] == "pulls" else { return nil }
        let number = parts[parts.count - 1]
        let repo = parts[parts.count - 3]
        let owner = parts[parts.count - 4]
        return "\(owner)/\(repo)#\(number)"
    }
}
