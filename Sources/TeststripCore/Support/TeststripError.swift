import Foundation

public enum TeststripError: LocalizedError, Equatable {
    case invalidState(String)
    case unsupportedFormat(String)
    case io(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidState(let message),
             .unsupportedFormat(let message),
             .io(let message),
             .database(let message):
            return message
        }
    }
}
