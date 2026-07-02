import Foundation

public enum AppError: Error, LocalizedError {
    case ghNotFound
    case authRequired
    case fetchFailed(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .ghNotFound:           return "gh not found"
        case .authRequired:         return "auth required"
        case .fetchFailed(let msg): return "fetch failed: \(msg)"
        case .parseError(let msg):  return "parse error: \(msg)"
        }
    }

    public var statusLabel: String {
        switch self {
        case .ghNotFound:   return "gh not found"
        case .authRequired: return "auth required"
        case .fetchFailed:  return "fetch failed"
        case .parseError:   return "parse error"
        }
    }
}
