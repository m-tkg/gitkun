import Foundation

// MARK: - リリース（更新チェック）

/// `/repos/{owner}/{repo}/releases/latest` のレスポンス（必要フィールドのみ）。
public struct ReleaseInfo: Decodable {
    public let tagName: String
    public let htmlUrl: String
}
