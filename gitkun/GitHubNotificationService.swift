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
        try await fetchSearch("/search/issues?q=is:open+is:pr+review-requested:@me&per_page=50",
                              label: "unreviewed PRs")
    }

    func fetchAssignedItems() async throws -> [AssignedItem] {
        try await fetchSearch("/search/issues?q=is:open+assignee:@me&per_page=50",
                              label: "assigned items")
    }

    func fetchAuthoredPRs() async throws -> [AssignedItem] {
        try await fetchSearch("/search/issues?q=is:open+is:pr+author:@me&per_page=50",
                              label: "authored PRs")
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

    // MARK: - Process 起動: pipe を readabilityHandler でストリーム読みする

    /// `Process` を起動し、stdout/stderr を `readabilityHandler` で逐次読み出して蓄積する。
    /// `terminationHandler` 内で `readDataToEndOfFile` を呼ぶ実装だと、出力が pipe バッファ
    /// （macOS では概ね 64KB）を超えた瞬間に process が write でブロックして exit せず、
    /// terminationHandler が呼ばれない deadlock になるため、こちらの形を採る。
    private func runProcess(executable: String,
                            arguments: [String],
                            token: String?) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var env = baseEnv()
        if let token { env["GH_TOKEN"] = token }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var outData = Data()
            var errData = Data()
            var hasResumed = false

            func resume(_ action: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                action()
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    lock.lock()
                    outData.append(chunk)
                    lock.unlock()
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    lock.lock()
                    errData.append(chunk)
                    lock.unlock()
                }
            }

            process.terminationHandler = { proc in
                // ハンドラを外して残りのデータを読み切る
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let remaining = try? outPipe.fileHandleForReading.readToEnd() {
                    lock.lock(); outData.append(remaining); lock.unlock()
                }
                if let remaining = try? errPipe.fileHandleForReading.readToEnd() {
                    lock.lock(); errData.append(remaining); lock.unlock()
                }

                lock.lock()
                let stdout = outData
                let stderr = errData
                lock.unlock()

                let errMsg = String(data: stderr, encoding: .utf8) ?? ""
                let outPreview = String(data: stdout.prefix(200), encoding: .utf8) ?? ""
                logger.info("exit=\(proc.terminationStatus) stderr=\"\(errMsg)\" stdout_preview=\"\(outPreview)\"")

                resume {
                    guard proc.terminationStatus == 0 else {
                        if errMsg.lowercased().contains("auth") || errMsg.lowercased().contains("login") {
                            logger.error("Auth error: \(errMsg)")
                            continuation.resume(throwing: AppError.authRequired)
                        } else {
                            logger.error("Fetch failed (exit=\(proc.terminationStatus)): \(errMsg)")
                            continuation.resume(throwing: AppError.fetchFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                        return
                    }
                    continuation.resume(returning: stdout)
                }
            }

            do {
                try process.run()
            } catch {
                resume { continuation.resume(throwing: error) }
            }
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
