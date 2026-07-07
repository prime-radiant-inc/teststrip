import Foundation

/// Rounds a coordinate to the shared reverse-geocode cache granularity so nearby
/// photos share one lookup. The produced string MUST match what SQLite's
/// `printf('%.2f,%.2f', ROUND(lat, 2), ROUND(lon, 2))` produces for the same
/// coordinate — the enqueue query computes keys in SQL and the writer computes
/// them here, so both must agree (pinned by CatalogDatabaseTests).
public enum GeocodeCoordinateKey {
    public static let roundingDecimals = 2

    public static func key(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f,%.2f", roundedToKey(latitude), roundedToKey(longitude))
    }

    private static func roundedToKey(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

/// A coordinate awaiting reverse geocoding. Modeled on `preview_generation_queue`
/// items: the drain fetches a bounded batch, resolves each, and removes it.
public struct GeocodeQueueItem: Equatable, Sendable {
    public var coordinateKey: String
    public var latitude: Double
    public var longitude: Double

    public init(coordinateKey: String, latitude: Double, longitude: Double) {
        self.coordinateKey = coordinateKey
        self.latitude = latitude
        self.longitude = longitude
    }
}
