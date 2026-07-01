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

// MARK: - MenuRowDisplayable conformance

private let githubFallbackURL = URL(string: "https://github.com")!

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
