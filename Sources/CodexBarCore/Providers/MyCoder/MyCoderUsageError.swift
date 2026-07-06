import Foundation

public enum MyCoderUsageError: Error, Equatable {
    case missingCredentials
    case invalidCredentials
    case networkError(String)
    case apiError(Int)
    case parseFailed(String)
}
