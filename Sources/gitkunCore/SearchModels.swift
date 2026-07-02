import Foundation

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
    public let title: String
    public let htmlUrl: String
    public let repositoryUrl: String
    public let updatedAt: String
    public let pullRequest: PullRequestRef?

    public var isPullRequest: Bool { pullRequest != nil }

    public struct PullRequestRef: Decodable {
        public init() {}
    }

    public init(
        id: Int,
        title: String,
        htmlUrl: String,
        repositoryUrl: String,
        updatedAt: String,
        pullRequest: PullRequestRef?
    ) {
        self.id = id
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
