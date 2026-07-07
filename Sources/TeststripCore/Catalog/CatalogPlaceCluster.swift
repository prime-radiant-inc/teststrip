import Foundation

/// One non-empty grid cell of geotagged frames. The coordinate is the mean of
/// the cell's contributing coordinates, so a rendered bubble sits on the actual
/// photo cloud rather than the cell corner.
public struct CatalogPlaceCluster: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var assetCount: Int

    public init(latitude: Double, longitude: Double, assetCount: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.assetCount = assetCount
    }
}

/// How many catalog assets carry usable GPS coordinates, for the "Geotagged on
/// import" coverage badge.
public struct CatalogGeotaggedCoverage: Equatable, Sendable {
    public var geotaggedCount: Int
    public var totalCount: Int

    public init(geotaggedCount: Int, totalCount: Int) {
        self.geotaggedCount = geotaggedCount
        self.totalCount = totalCount
    }
}
