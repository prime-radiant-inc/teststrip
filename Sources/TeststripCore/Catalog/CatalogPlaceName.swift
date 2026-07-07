import Foundation

/// A cached reverse-geocoded place name for a rounded coordinate key. Display-only
/// derived data: it lives solely in `place_cache`, never on `AssetMetadata`, and
/// clearing it and re-running is always safe.
public struct CatalogPlaceName: Equatable, Sendable {
    public var coordinateKey: String
    public var locality: String?
    public var administrativeArea: String?
    public var country: String?
    public var displayName: String?

    public init(
        coordinateKey: String,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        displayName: String? = nil
    ) {
        self.coordinateKey = coordinateKey
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.country = country
        self.displayName = displayName
    }
}
