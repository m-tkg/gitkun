import Foundation

// MARK: - 設定・ステータス

public enum PollingInterval: Int {
    case sec15 = 15
    case sec30 = 30
    case sec60 = 60
    case sec120 = 120
    case sec300 = 300
}

public enum AppStatus {
    case idle
    case loading
    case ok
    case error(String)
}

extension AppStatus {
    public var displayLabel: String {
        switch self {
        case .idle:           return "Status: -"
        case .loading:        return "Status: Loading..."
        case .ok:             return "Status: OK"
        case .error(let msg): return "Status: \(msg)"
        }
    }
}
