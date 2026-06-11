import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "GitHubNotificationService")

actor GitHubNotificationService {

    private var cachedToken: String?

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func findGHPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - 公開 API

    func fetchNotifications() async throws -> [GitHubNotification] {
        try await fetch("/notifications?per_page=50&all=false",
                        as: [GitHubNotification].self,
                        label: "notifications")
    }

    func fetchUnreviewedPRs() async throws -> [UnreviewedPR] {
        let prs: [UnreviewedPR] = try await fetchSearch(
            "/search/issues?q=is:open+is:pr+review-requested:@me&per_page=50",
            label: "unreviewed PRs")
        // draft / タイトル先頭 [WIP] / wip ラベルは review 待ちと判定しない
        return prs.filter(\.isReviewWaiting)
    }

    func fetchAssignedItems() async throws -> [AssignedItem] {
        try await fetchSearch("/search/issues?q=is:open+assignee:@me&per_page=50",
                              label: "assigned items")
    }

    func fetchAuthoredPRs() async throws -> [AssignedItem] {
        try await fetchSearch("/search/issues?q=is:open+is:pr+author:@me&per_page=50",
                              label: "authored PRs")
    }

    func fetchLatestRelease() async throws -> ReleaseInfo {
        try await fetch("/repos/\(Self.repoFullName)/releases/latest",
                        as: ReleaseInfo.self,
                        label: "latest release")
    }

    /// 更新チェック対象リポジトリ（自分自身）。
    private static let repoFullName = "m-tkg/gitkun"

    /// 指定タグのリリースから zip 資産を `directory` にダウンロードする。
    func downloadLatestReleaseZip(tag: String, into directory: URL) async throws {
        guard let ghPath = Self.findGHPath() else {
            logger.error("gh not found in known paths")
            throw AppError.ghNotFound
        }
        let token = try await resolveToken(ghPath: ghPath)
        logger.info("Downloading release \(tag, privacy: .public)")
        _ = try await runProcess(executable: ghPath,
                                 arguments: ["release", "download", tag,
                                             "--repo", Self.repoFullName,
                                             "--pattern", "*.zip",
                                             "--dir", directory.path,
                                             "--clobber"],
                                 token: token)
    }

    // MARK: - フェッチ共通

    private func fetch<T: Decodable>(_ endpoint: String, as type: T.Type, label: String) async throws -> T {
        let data = try await runGHAPI(endpoint, label: label)
        return try decode(T.self, from: data, label: label)
    }

    private func fetchSearch<T: Decodable>(_ endpoint: String, label: String) async throws -> [T] {
        try await fetch(endpoint, as: SearchResponse<T>.self, label: label).items
    }

    // MARK: - トークン取得（初回のみ Keychain にアクセス、以降はキャッシュ）

    private func resolveToken(ghPath: String) async throws -> String {
        if let token = cachedToken {
            return token
        }

        logger.info("Fetching gh token via 'gh auth token'")

        let data = try await runProcess(executable: ghPath,
                                        arguments: ["auth", "token"],
                                        token: nil)
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            logger.error("gh auth token returned empty output")
            throw AppError.authRequired
        }
        logger.info("gh token resolved successfully")
        cachedToken = token
        return token
    }

    // MARK: - gh API 呼び出し

    private func runGHAPI(_ endpoint: String, label: String) async throws -> Data {
        guard let ghPath = Self.findGHPath() else {
            logger.error("gh not found in known paths")
            throw AppError.ghNotFound
        }
        let token = try await resolveToken(ghPath: ghPath)
        logger.info("Fetching \(label, privacy: .public)")
        return try await runProcess(executable: ghPath,
                                    arguments: ["api", endpoint],
                                    token: token)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, label: String) throws -> T {
        do {
            let decoded = try Self.decoder.decode(T.self, from: data)
            if let count = (decoded as? any Collection)?.count {
                logger.info("Fetched \(count) \(label, privacy: .public)")
            } else {
                logger.info("Decoded \(label, privacy: .public)")
            }
            return decoded
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            logger.error("Parse error for \(label, privacy: .public): \(error) raw=\"\(preview)\"")
            throw AppError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Process 起動

    /// `ProcessRunner` で gh を実行し、失敗時は stderr の内容から `AppError` に変換する。
    private func runProcess(executable: String,
                            arguments: [String],
                            token: String?) async throws -> Data {
        var env = baseEnv()
        if let token { env["GH_TOKEN"] = token }

        do {
            return try await ProcessRunner.run(executable: executable,
                                               arguments: arguments,
                                               environment: env)
        } catch let failure as ProcessRunner.Failure {
            let errMsg = failure.stderr
            if errMsg.lowercased().contains("auth") || errMsg.lowercased().contains("login") {
                logger.error("Auth error: \(errMsg)")
                throw AppError.authRequired
            }
            logger.error("Fetch failed (exit=\(failure.exitCode)): \(errMsg)")
            throw AppError.fetchFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - 共通環境変数

    private func baseEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = NSHomeDirectory()
        return env
    }
}
