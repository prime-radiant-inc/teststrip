import Foundation

/// A reverse-geocoded place with its photo count, for the design-5b TOP LOCATIONS
/// sidebar. lat/lon are the mean of contributing coordinates, so tapping a row
/// can drill the map/grid to that centroid. Coordinates with no cached name yet
/// are simply absent — the list fills in as geocoding drains.
public struct CatalogTopLocation: Equatable, Sendable {
    public var displayName: String
    public var assetCount: Int
    public var latitude: Double
    public var longitude: Double

    public init(displayName: String, assetCount: Int, latitude: Double, longitude: Double) {
        self.displayName = displayName
        self.assetCount = assetCount
        self.latitude = latitude
        self.longitude = longitude
    }
}
