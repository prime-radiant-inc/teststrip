import Foundation
import TeststripCore

/// One map cluster bubble, sized by photo count. Coordinates stay as lat/lon so
/// the presentation is MapKit-free and fully testable; the view builds the
/// `CLLocationCoordinate2D`.
struct PlaceBubblePresentation: Identifiable, Equatable {
    var id: String
    var latitude: Double
    var longitude: Double
    var assetCount: Int
    var radius: Double
    var labelText: String
}

/// One TOP LOCATIONS row.
struct PlaceRowPresentation: Identifiable, Equatable {
    var id: String
    var title: String
    var countText: String
    var latitude: Double
    var longitude: Double
    var assetCount: Int
}

/// The tested presentation-model behind the Places map surface: cluster bubbles
/// sized by count, the TOP LOCATIONS list, a "Geotagged on import" coverage
/// badge, and a one-line summary. Pure value logic — the workspace view is a
/// thin shell over this.
struct PlacesPresentation: Equatable {
    var bubbles: [PlaceBubblePresentation]
    var topLocations: [PlaceRowPresentation]
    var coverageText: String
    var summaryText: String

    static let minimumBubbleRadius = 6.0
    static let maximumBubbleRadius = 60.0
    static let bubbleRadiusPerSqrtCount = 1.5

    init(
        clusters: [CatalogPlaceCluster],
        topLocations: [CatalogTopLocation],
        coverage: CatalogGeotaggedCoverage
    ) {
        self.bubbles = clusters.map { cluster in
            PlaceBubblePresentation(
                id: "\(cluster.latitude),\(cluster.longitude)",
                latitude: cluster.latitude,
                longitude: cluster.longitude,
                assetCount: cluster.assetCount,
                radius: Self.radius(for: cluster.assetCount),
                labelText: Self.abbreviatedCount(cluster.assetCount)
            )
        }
        self.topLocations = topLocations.map { location in
            PlaceRowPresentation(
                id: location.displayName,
                title: location.displayName,
                countText: Self.photoCountText(location.assetCount),
                latitude: location.latitude,
                longitude: location.longitude,
                assetCount: location.assetCount
            )
        }
        self.coverageText = Self.coverageText(coverage)
        self.summaryText = Self.summaryText(locationCount: topLocations.count, coverage: coverage)
    }

    static func radius(for count: Int) -> Double {
        let raw = minimumBubbleRadius + Double(max(count, 0)).squareRoot() * bubbleRadiusPerSqrtCount
        return min(raw, maximumBubbleRadius)
    }

    static func abbreviatedCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return abbreviate(Double(count) / 1_000_000, suffix: "M")
        }
        if count >= 1_000 {
            return abbreviate(Double(count) / 1_000, suffix: "k")
        }
        return "\(count)"
    }

    private static func abbreviate(_ value: Double, suffix: String) -> String {
        if value == value.rounded() {
            return "\(Int(value))\(suffix)"
        }
        return String(format: "%.1f%@", value, suffix)
    }

    private static func coverageText(_ coverage: CatalogGeotaggedCoverage) -> String {
        guard coverage.geotaggedCount > 0 else {
            return "No geotagged frames yet"
        }
        return "Geotagged on import — \(grouped(coverage.geotaggedCount)) of \(grouped(coverage.totalCount))"
    }

    private static func photoCountText(_ count: Int) -> String {
        "\(grouped(count)) \(count == 1 ? "photo" : "photos")"
    }

    private static func summaryText(locationCount: Int, coverage: CatalogGeotaggedCoverage) -> String {
        "\(locationCount) \(locationCount == 1 ? "location" : "locations") · \(grouped(coverage.geotaggedCount)) geotagged"
    }

    private static let groupedCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter
    }()

    private static func grouped(_ count: Int) -> String {
        groupedCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
