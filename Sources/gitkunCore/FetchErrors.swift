import Foundation

// MARK: - エラー集約

public struct FetchErrors {
    private(set) var details: [String] = []
    private(set) var labels: [String] = []

    public init() {}

    public var isEmpty: Bool { details.isEmpty }
    public var detail: String { details.joined(separator: "\n") }
    public var statusLabel: String { labels.joined(separator: ", ") }

    /// `Result` を unwrap し、失敗時は内部にエラーを蓄積して `nil` を返す。
    public mutating func unwrap<T>(_ result: Result<T, AppError>) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            details.append(error.errorDescription ?? "\(error)")
            labels.append(error.statusLabel)
            return nil
        }
    }
}
