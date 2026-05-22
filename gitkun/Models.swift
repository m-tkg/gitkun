import Foundation

// MARK: - 共通 protocol

/// `repository_url` を持つ Search API 由来の型に `owner/repo` を提供する。
protocol RepositoryURLContaining {
    var repositoryUrl: String { get }
}

extension RepositoryURLContaining {
    var repositoryFullName: String {
        // repositoryUrl: https://api.github.com/repos/{owner}/{repo}
        guard let url = URL(string: repositoryUrl) else { return "" }
        let parts = url.pathComponents
        guard parts.count >= 3 else { return "" }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }
}

/// メニュー行と通知バナーで共通に使う表示プロパティ。
protocol MenuRowDisplayable {
    var repoFullName: String { get }
    var displayTitle: String { get }
    var updatedAtString: String { get }
    var webURL: URL { get }
}

// MARK: - 通知

struct GitHubNotification: Decodable, Identifiable {
    let id: String
    let updatedAt: String
    let reason: String
    let subject: Subject
    let repository: Repository

    struct Subject: Decodable {
        let title: String
        let url: String?
    }

    struct Repository: Decodable {
        let fullName: String
        let htmlUrl: String
    }
}

/// `/notifications` の reason 値。UI 上でのグルーピング順と表示ラベルを持つ。
/// 参考: https://docs.github.com/ja/rest/activity/notifications
enum NotificationReason: String, CaseIterable {
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

    var displayLabel: String {
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

// MARK: - 未レビュー PR / Assigned Item

struct UnreviewedPR: Decodable, Identifiable, RepositoryURLContaining {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let repositoryUrl: String
    let updatedAt: String
}

/// 自分にアサインされている open な PR / Issue。
/// `/search/issues?q=is:open+assignee:@me` のレスポンス。
/// `pullRequest` フィールドが nil でなければ PR、nil なら Issue。
struct AssignedItem: Decodable, Identifiable, RepositoryURLContaining {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let repositoryUrl: String
    let updatedAt: String
    let pullRequest: PullRequestRef?

    var isPullRequest: Bool { pullRequest != nil }

    struct PullRequestRef: Decodable {
        let url: String?
    }
}

/// `/search/issues` 共通のレスポンス。
struct SearchResponse<T: Decodable>: Decodable {
    let items: [T]
}

// MARK: - MenuRowDisplayable conformance

private let githubFallbackURL = URL(string: "https://github.com")!

extension GitHubNotification: MenuRowDisplayable {
    var repoFullName: String { repository.fullName }
    var displayTitle: String { subject.title }
    var updatedAtString: String { updatedAt }
    var webURL: URL { URLResolver.resolve(notification: self) }
}

extension UnreviewedPR: MenuRowDisplayable {
    var repoFullName: String { repositoryFullName }
    var displayTitle: String { title }
    var updatedAtString: String { updatedAt }
    var webURL: URL { URL(string: htmlUrl) ?? githubFallbackURL }
}

extension AssignedItem: MenuRowDisplayable {
    var repoFullName: String { repositoryFullName }
    var displayTitle: String { title }
    var updatedAtString: String { updatedAt }
    var webURL: URL { URL(string: htmlUrl) ?? githubFallbackURL }
}

// MARK: - 設定・ステータス

enum DiffStrategy: String {
    case id
    case updatedAt
}

enum PollingInterval: Int {
    case sec15 = 15
    case sec30 = 30
    case sec60 = 60
    case sec120 = 120
    case sec300 = 300
}

enum AppStatus {
    case idle
    case loading
    case ok
    case error(String)
}

enum AppError: Error, LocalizedError {
    case ghNotFound
    case authRequired
    case fetchFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .ghNotFound:           return "gh not found"
        case .authRequired:         return "auth required"
        case .fetchFailed(let msg): return "fetch failed: \(msg)"
        case .parseError(let msg):  return "parse error: \(msg)"
        }
    }

    var statusLabel: String {
        switch self {
        case .ghNotFound:   return "gh not found"
        case .authRequired: return "auth required"
        case .fetchFailed:  return "fetch failed"
        case .parseError:   return "parse error"
        }
    }
}
