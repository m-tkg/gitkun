import AppKit
import gitkunCore
import OSLog

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "SelfUpdater")

/// 最新リリースの zip をダウンロード・展開し、起動中の `.app` を上書きして再起動する。
///
/// 実行中のバンドルは自プロセスでは上書きできないため、旧プロセスの終了を待ってから
/// 入れ替える切り離しシェルスクリプトを起動し、自身は `NSApp.terminate` で終了する。
@MainActor
final class SelfUpdater {

    enum UpdateError: LocalizedError {
        case notWritable(String)
        case archiveNotFound
        case commandFailed(String)
        case bundleNotFound
        case bundleIDMismatch

        var errorDescription: String? {
            switch self {
            case .notWritable(let path):
                return "アプリの場所に書き込めません: \(path)。手動での更新が必要です。"
            case .archiveNotFound:
                return "リリースに zip が見つかりませんでした。"
            case .commandFailed(let msg):
                return "更新コマンドが失敗しました: \(msg)"
            case .bundleNotFound:
                return "ダウンロードしたアーカイブに .app が見つかりませんでした。"
            case .bundleIDMismatch:
                return "ダウンロードした .app の識別子が一致しませんでした。"
            }
        }
    }

    private let service: GitHubNotificationService

    init(service: GitHubNotificationService) {
        self.service = service
    }

    /// 更新を実行する。成功した場合はアプリを終了するため、呼び出し元には戻らない。
    func performUpdate(to release: ReleaseInfo) async throws {
        let bundleURL = Bundle.main.bundleURL
        try ensureWritable(bundleURL)

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("gitkun-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        // 1. ダウンロード（gh release download）
        try await service.downloadLatestReleaseZip(tag: release.tagName, into: workDir)

        // 2. zip を特定
        guard let zipURL = try firstFile(in: workDir, pathExtension: "zip") else {
            throw UpdateError.archiveNotFound
        }

        // 3. 展開（.app の展開には ditto が最適）
        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await runAndWait("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        // 4. .app を特定して識別子を検証
        guard let newApp = try firstFile(in: extractDir, pathExtension: "app") else {
            throw UpdateError.bundleNotFound
        }
        guard let newBundleID = Bundle(url: newApp)?.bundleIdentifier,
              newBundleID == Bundle.main.bundleIdentifier else {
            throw UpdateError.bundleIDMismatch
        }

        // 5. 入れ替えスクリプトを切り離し起動し、自身を終了
        try launchReplaceScript(newApp: newApp, dest: bundleURL)
        logger.info("Relaunch script started; terminating for update to \(release.tagName, privacy: .public)")
        NSApp.terminate(nil)
    }

    // MARK: - 補助

    private func ensureWritable(_ bundleURL: URL) throws {
        let fm = FileManager.default
        let parent = bundleURL.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: bundleURL.path) else {
            throw UpdateError.notWritable(bundleURL.path)
        }
    }

    private func firstFile(in directory: URL, pathExtension: String) throws -> URL? {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        return entries.first { $0.pathExtension == pathExtension }
    }

    /// 旧プロセス終了を待って `.app` を入れ替え、再起動する切り離しスクリプトを起動する。
    /// パスは環境変数で渡し、空白を含むパスでも安全にする。
    private func launchReplaceScript(newApp: URL, dest: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.bak"
        mv "$DEST" "$DEST.bak" || exit 1
        if ! mv "$NEW" "$DEST"; then
          mv "$DEST.bak" "$DEST"
          exit 1
        fi
        rm -rf "$DEST.bak"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = [
            "DEST": dest.path,
            "NEW": newApp.path,
            "PATH": "/usr/bin:/bin",
        ]
        try process.run()
    }

    /// プロセスを起動し終了を待つ。失敗時は stderr を `UpdateError` に変換する。
    private func runAndWait(_ executable: String, _ arguments: [String]) async throws {
        do {
            _ = try await ProcessRunner.run(executable: executable, arguments: arguments)
        } catch let failure as ProcessRunner.Failure {
            let msg = failure.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("Command failed (\(executable, privacy: .public) exit=\(failure.exitCode)): \(msg)")
            throw UpdateError.commandFailed(msg.isEmpty ? "exit \(failure.exitCode)" : msg)
        }
    }
}
