import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class PlacesPresentationTests: XCTestCase {
    func testPresentationSizesBubblesByCountAndBuildsCoverageText() {
        let presentation = PlacesPresentation(
            clusters: [
                CatalogPlaceCluster(latitude: 48.85, longitude: 2.29, assetCount: 1200),
                CatalogPlaceCluster(latitude: 40.74, longitude: -73.98, assetCount: 30)
            ],
            topLocations: [
                CatalogTopLocation(displayName: "Paris · France", assetCount: 1200, latitude: 48.85, longitude: 2.29)
            ],
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 412000, totalCount: 486000)
        )

        XCTAssertEqual(presentation.bubbles.count, 2)
        XCTAssertGreaterThan(presentation.bubbles[0].radius, presentation.bubbles[1].radius)  // 1200 > 30
        XCTAssertEqual(presentation.bubbles[0].labelText, "1.2k")
        XCTAssertEqual(presentation.topLocations.first?.title, "Paris · France")
        XCTAssertEqual(presentation.coverageText, "Geotagged on import — 412,000 of 486,000")
        XCTAssertTrue(presentation.hasGeotaggedPhotos)
    }

    func testPresentationHandlesNoCoverageGracefully() {
        let presentation = PlacesPresentation(
            clusters: [], topLocations: [],
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 0, totalCount: 40)
        )
        XCTAssertTrue(presentation.bubbles.isEmpty)
        XCTAssertEqual(presentation.coverageText, "No geotagged frames yet")
        // With photos present but none geotagged, the workspace must show the
        // invitation, not a world map full of MapKit's own basemap labels.
        XCTAssertFalse(presentation.hasGeotaggedPhotos)
        XCTAssertEqual(
            presentation.emptyStateText,
            "None of these photos have location data yet. Photos taken with GPS on — or after you read locations — appear here on the map."
        )
    }
}
