import Foundation

public enum MyCoderUsageError: LocalizedError, Equatable {
    case missingCredentials
    case invalidCredentials
    case networkError(String)
    case apiError(Int)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "MyCoder cookie is missing."
        case .invalidCredentials:
            "MyCoder cookie is invalid or expired."
        case let .networkError(message):
            "MyCoder network error: \(message)"
        case let .apiError(statusCode):
            "MyCoder API returned HTTP \(statusCode)."
        case let .parseFailed(message):
            "Failed to parse MyCoder response: \(message)"
        }
    }
}
