import Foundation
import TeststripCore

public struct GeoFixtureSeederResult: Equatable {
    public var totalCount: Int
    public var gpsBearingCount: Int
    public var latitude: Double
    public var longitude: Double

    public init(totalCount: Int, gpsBearingCount: Int, latitude: Double, longitude: Double) {
        self.totalCount = totalCount
        self.gpsBearingCount = gpsBearingCount
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Writes a folder of synthetic JPEGs for the `places-map-and-geocode` card: a
/// known subset carries GPS EXIF at the Eiffel Tower (matching
/// `verify_reverse_geocode_smoke.sh` so reverse-geocoding is predictable), the
/// rest carry no GPS.
public struct GeoFixtureSeeder {
    public static let eiffelLatitude = 48.8584
    public static let eiffelLongitude = 2.2945

    public var directory: URL
    public var count: Int

    public init(directory: URL, count: Int) {
        self.directory = directory
        self.count = count
    }

    public func run() throws -> GeoFixtureSeederResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gpsBearingCount = max(1, count / 2)
        for index in 0..<count {
            let url = directory.appendingPathComponent(String(format: "GEO_%04d.jpg", index))
            if index < gpsBearingCount {
                try BenchmarkImageFixtures.writeJPEGWithGPS(
                    to: url,
                    index: index,
                    latitude: Self.eiffelLatitude,
                    longitude: Self.eiffelLongitude
                )
            } else {
                try BenchmarkImageFixtures.writeJPEG(to: url, index: index)
            }
        }
        return GeoFixtureSeederResult(
            totalCount: count,
            gpsBearingCount: min(gpsBearingCount, count),
            latitude: Self.eiffelLatitude,
            longitude: Self.eiffelLongitude
        )
    }
}
