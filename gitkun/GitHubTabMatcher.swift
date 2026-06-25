import Foundation

/// ブラウザの既存タブと、これから開こうとしている URL が「同じページ」かを判定する純粋ロジック。
///
/// 「同じ PR / Issue なら同一」とみなす。すなわち `…/pull/{番号}` や `…/issues/{番号}` まで一致すれば、
/// `/files`・`/commits` などのサブページや `#issuecomment-…` アンカー、クエリ違いでも同じとみなす。
/// PR / Issue 以外の URL（リリースページ・コミット等）は末尾スラッシュのみ吸収したパス完全一致で比較する。
enum GitHubTabMatcher {

    /// 番号で切り詰める対象のセグメント名。
    private static let numberedSegments: Set<String> = ["pull", "issues"]

    /// 同一判定に使う正規化キーを返す。
    /// - host は小文字化、query / fragment は捨てる
    /// - パスに `pull`/`issues` の直後が数字のセグメントがあれば、その番号までで切り詰める
    /// - それ以外は末尾スラッシュを除いたパス全体
    static func canonicalKey(_ url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = (components?.host ?? "").lowercased()
        let path = components?.path ?? url.path

        var segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if let i = segments.firstIndex(where: { numberedSegments.contains($0) }),
           i + 1 < segments.count,
           segments[i + 1].allSatisfy(\.isNumber), !segments[i + 1].isEmpty {
            segments = Array(segments[0...(i + 1)])
        }

        return host + "/" + segments.joined(separator: "/")
    }

    /// 2 つの URL が同じページを指すか。
    static func matches(_ a: URL, _ b: URL) -> Bool {
        canonicalKey(a) == canonicalKey(b)
    }
}
