import Foundation

public enum CatalogError: Error, Equatable {
    case notFound(String)
    case sqlite(String)
}

extension CatalogError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let identifier):
            return "Catalog item not found: \(identifier)"
        case .sqlite(let message):
            return message
        }
    }
}
