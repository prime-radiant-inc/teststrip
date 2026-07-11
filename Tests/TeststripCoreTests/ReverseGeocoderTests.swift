import XCTest
@testable import TeststripCore

final class ReverseGeocoderTests: XCTestCase {
    func testDisplayNamePrefersLocalityAndJoinsCountryWithMiddleDot() {
        XCTAssertEqual(
            CatalogPlaceName.displayName(locality: "Paris", administrativeArea: "Île-de-France", country: "France"),
            "Paris · France"
        )
    }

    func testDisplayNameFallsBackToAdministrativeAreaWhenLocalityMissing() {
        XCTAssertEqual(
            CatalogPlaceName.displayName(locality: nil, administrativeArea: "California", country: "USA"),
            "California · USA"
        )
    }

    func testDisplayNameUsesCountryOnlyWhenNoPlaceComponent() {
        XCTAssertEqual(
            CatalogPlaceName.displayName(locality: nil, administrativeArea: nil, country: "France"),
            "France"
        )
    }

    func testDisplayNameUsesPlaceOnlyWhenNoCountry() {
        XCTAssertEqual(
            CatalogPlaceName.displayName(locality: "Paris", administrativeArea: nil, country: nil),
            "Paris"
        )
    }

    func testDisplayNameIsNilWhenEveryComponentIsNilOrBlank() {
        XCTAssertNil(CatalogPlaceName.displayName(locality: nil, administrativeArea: nil, country: nil))
        XCTAssertNil(CatalogPlaceName.displayName(locality: "  ", administrativeArea: "", country: nil))
    }

    func testCLGeocoderBridgeTimesOutWhenLookupHangs() {
        let geocoder = CLGeocoderReverseGeocoder(timeout: 0.05) { _, _ in
            // A lookup that never completes, standing in for CLGeocoder
            // hanging: without the bounded wait this blocks until the worker
            // supervisor's 120s command timeout kills the process before any
            // per-item failure is recorded.
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return nil
        }
        XCTAssertThrowsError(try geocoder.reverseGeocode(latitude: 48.8584, longitude: 2.2945)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("timed out"),
                "expected a timeout error, got: \(error.localizedDescription)"
            )
        }
    }

    func testCLGeocoderBridgeReturnsResultWhenLookupCompletesInTime() throws {
        let geocoder = CLGeocoderReverseGeocoder(timeout: 5) { _, _ in
            ReverseGeocodeResult(locality: "Paris", administrativeArea: nil, country: "France")
        }
        let result = try geocoder.reverseGeocode(latitude: 48.8584, longitude: 2.2945)
        XCTAssertEqual(result?.locality, "Paris")
        XCTAssertEqual(result?.country, "France")
    }

    func testReverseGeocoderProtocolReturnsCannedResultForRoundedKey() throws {
        let geocoder = StubReverseGeocoder(results: [
            GeocodeCoordinateKey.key(latitude: 48.8584, longitude: 2.2945):
                ReverseGeocodeResult(locality: "Paris", administrativeArea: nil, country: "France")
        ])
        let result = try geocoder.reverseGeocode(latitude: 48.8584, longitude: 2.2945)
        XCTAssertEqual(result?.locality, "Paris")
        XCTAssertNil(try geocoder.reverseGeocode(latitude: 0.0, longitude: 0.0))
    }
}

private struct StubReverseGeocoder: ReverseGeocoder {
    var results: [String: ReverseGeocodeResult]

    func reverseGeocode(latitude: Double, longitude: Double) throws -> ReverseGeocodeResult? {
        results[GeocodeCoordinateKey.key(latitude: latitude, longitude: longitude)]
    }
}
