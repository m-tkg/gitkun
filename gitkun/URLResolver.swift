import Foundation

struct URLResolver {

    static func resolve(notification: GitHubNotification) -> URL {
        let fallback = URL(string: notification.repository.htmlUrl)!

        guard let apiURLString = notification.subject.url,
              let apiURL = URL(string: apiURLString),
              var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        else {
            return fallback
        }

        components.host = "github.com"
        components.scheme = "https"
        components.query = nil

        var path = components.path

        // /repos/{owner}/{repo}/... → /{owner}/{repo}/...
        if path.hasPrefix("/repos/") {
            path = String(path.dropFirst("/repos".count))
        }

        // pulls → pull（単数形）
        path = path.replacingOccurrences(of: "/pulls/", with: "/pull/")

        // commits → commit（単数形）
        path = path.replacingOccurrences(of: "/commits/", with: "/commit/")

        components.path = path

        return components.url ?? fallback
    }
}
