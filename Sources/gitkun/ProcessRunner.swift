import Foundation
import OSLog

private let logger = Logger(subsystem: logSubsystem, category: "ProcessRunner")

/// 外部コマンドを起動して stdout を返す共通ランナー。
///
/// stdout/stderr は `readabilityHandler` で逐次読み出して蓄積する。
/// `terminationHandler` 内で `readDataToEndOfFile` を呼ぶ実装だと、出力が pipe バッファ
/// （macOS では概ね 64KB）を超えた瞬間に process が write でブロックして exit せず、
/// terminationHandler が呼ばれない deadlock になるため、こちらの形を採る。
enum ProcessRunner {

    /// exit code が 0 以外だったときに投げる。エラーの意味付けは呼び出し側で行う。
    struct Failure: Error {
        let exitCode: Int32
        let stderr: String
    }

    /// プロセスを起動し、正常終了（exit 0）なら stdout を返す。
    /// `environment` が nil の場合は親プロセスの環境を継承する。
    static func run(executable: String,
                    arguments: [String],
                    environment: [String: String]? = nil) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

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
                        continuation.resume(throwing: Failure(exitCode: proc.terminationStatus,
                                                              stderr: errMsg))
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
}

extension ProcessRunner.Failure {
    /// stderr を1行のエラーメッセージ用文字列に整形する。空なら exit code にフォールバックする。
    var conciseMessage: String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "exit \(exitCode)" : trimmed
    }
}
