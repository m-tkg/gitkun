import Foundation

// MARK: - 共通 protocol

/// `repository_url` を持つ Search API 由来の型に `owner/repo` を提供する。
public protocol RepositoryURLContaining {
    var repositoryUrl: String { get }
}

extension RepositoryURLContaining {
    public var repositoryFullName: String {
        // repositoryUrl: https://api.github.com/repos/{owner}/{repo}
        guard let url = URL(string: repositoryUrl) else { return "" }
        let parts = url.pathComponents
        guard parts.count >= 3 else { return "" }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }
}

/// メニュー行と通知バナーで共通に使う表示プロパティ。
public protocol MenuRowDisplayable {
    var repoFullName: String { get }
    var displayTitle: String { get }
    var updatedAtString: String { get }
    var webURL: URL { get }
    /// リポジトリ名の右に添える補助情報（通知の種別など）。なければ nil。
    var rowDetail: String? { get }
}

extension MenuRowDisplayable {
    public var rowDetail: String? { nil }
}

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

// MARK: - 未レビュー PR / Assigned Item

public struct UnreviewedPR: Decodable, Identifiable, RepositoryURLContaining {
    public let id: Int
    public let number: Int
    public let title: String
    public let htmlUrl: String
    public let repositoryUrl: String
    public let updatedAt: String
    public let draft: Bool
    public let labels: [Label]

    public struct Label: Decodable {
        public let name: String

        public init(name: String) {
            self.name = name
        }
    }

    public init(
        id: Int,
        number: Int,
        title: String,
        htmlUrl: String,
        repositoryUrl: String,
        updatedAt: String,
        draft: Bool,
        labels: [Label]
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.htmlUrl = htmlUrl
        self.repositoryUrl = repositoryUrl
        self.updatedAt = updatedAt
        self.draft = draft
        self.labels = labels
    }

    /// `owner/repo#number` 形式のキー。通知の `pullRequestKey` と突き合わせる。
    public var prKey: String { "\(repositoryFullName)#\(number)" }

    /// review 待ちとして扱うか。以下は review 待ちと判定しない。
    /// - draft PR
    /// - タイトルが `[WIP]` で始まる（大文字小文字は区別しない）
    /// - `wip` ラベルが付いている（大文字小文字は区別しない）
    public var isReviewWaiting: Bool {
        if draft { return false }
        if title.lowercased().hasPrefix("[wip]") { return false }
        if labels.contains(where: { $0.name.lowercased() == "wip" }) { return false }
        return true
    }
}

/// 自分にアサインされている open な PR / Issue。
/// `/search/issues?q=is:open+assignee:@me` のレスポンス。
/// `pullRequest` フィールドが nil でなければ PR、nil なら Issue。
public struct AssignedItem: Decodable, Identifiable, RepositoryURLContaining {
    public let id: Int
    public let number: Int
    public let title: String
    public let htmlUrl: String
    public let repositoryUrl: String
    public let updatedAt: String
    public let pullRequest: PullRequestRef?

    public var isPullRequest: Bool { pullRequest != nil }

    public struct PullRequestRef: Decodable {
        public let url: String?
    }

    public init(
        id: Int,
        number: Int,
        title: String,
        htmlUrl: String,
        repositoryUrl: String,
        updatedAt: String,
        pullRequest: PullRequestRef?
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.htmlUrl = htmlUrl
        self.repositoryUrl = repositoryUrl
        self.updatedAt = updatedAt
        self.pullRequest = pullRequest
    }
}

/// `/search/issues` 共通のレスポンス。
public struct SearchResponse<T: Decodable>: Decodable {
    public let items: [T]
}

// MARK: - リリース（更新チェック）

/// `/repos/{owner}/{repo}/releases/latest` のレスポンス（必要フィールドのみ）。
public struct ReleaseInfo: Decodable {
    public let tagName: String
    public let htmlUrl: String
}

/// `v` プレフィックス付きのタグと `CFBundleShortVersionString` を数値比較する。
public enum VersionComparator {
    /// `tag` が `current` より新しければ true。
    public static func isNewer(tag: String, than current: String) -> Bool {
        let a = components(tag)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 先頭の `v`/`V` を除去し `.` 区切りで数値化。各要素は先頭の数字部分のみ採用（`0-beta` → 0）。
    private static func components(_ version: String) -> [Int] {
        let trimmed = (version.hasPrefix("v") || version.hasPrefix("V"))
            ? String(version.dropFirst())
            : version
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}

// MARK: - MenuRowDisplayable conformance

private let githubFallbackURL = URL(string: "https://github.com")!

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

extension GitHubNotification: MenuRowDisplayable {
    public var repoFullName: String { repository.fullName }
    public var displayTitle: String { subject.title }
    public var updatedAtString: String { updatedAt }
    public var webURL: URL { URLResolver.resolve(notification: self) }
    public var rowDetail: String? { subjectTypeLabel }
}

extension UnreviewedPR: MenuRowDisplayable {
    public var repoFullName: String { repositoryFullName }
    public var displayTitle: String { title }
    public var updatedAtString: String { updatedAt }
    public var webURL: URL { URL(string: htmlUrl) ?? githubFallbackURL }
}

extension AssignedItem: MenuRowDisplayable {
    public var repoFullName: String { repositoryFullName }
    public var displayTitle: String { title }
    public var updatedAtString: String { updatedAt }
    public var webURL: URL { URL(string: htmlUrl) ?? githubFallbackURL }
}

// MARK: - 設定・ステータス

public enum PollingInterval: Int {
    case sec15 = 15
    case sec30 = 30
    case sec60 = 60
    case sec120 = 120
    case sec300 = 300
}

public enum AppStatus {
    case idle
    case loading
    case ok
    case error(String)
}

public enum AppError: Error, LocalizedError {
    case ghNotFound
    case authRequired
    case fetchFailed(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .ghNotFound:           return "gh not found"
        case .authRequired:         return "auth required"
        case .fetchFailed(let msg): return "fetch failed: \(msg)"
        case .parseError(let msg):  return "parse error: \(msg)"
        }
    }

    public var statusLabel: String {
        switch self {
        case .ghNotFound:   return "gh not found"
        case .authRequired: return "auth required"
        case .fetchFailed:  return "fetch failed"
        case .parseError:   return "parse error"
        }
    }
}
