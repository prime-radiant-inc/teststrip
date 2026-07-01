public enum CatalogError: Error, Equatable {
    case notFound(String)
    case sqlite(String)
}
