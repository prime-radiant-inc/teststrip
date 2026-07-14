import TeststripCore
import XCTest
@testable import TeststripApp

final class PhotoFacesPresentationTests: XCTestCase {
    private func face(_ index: Int) -> CatalogFaceObservation {
        CatalogFaceObservation(
            assetID: AssetID(rawValue: "a"),
            faceIndex: index,
            boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            captureQuality: nil,
            embedding: [],
            provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "h")
        )
    }

    func testRowsReflectConfirmedSuggestedUnnamed() {
        let obs = [face(0), face(1), face(2)]
        let p = PhotoFacesPresentation(
            assetID: AssetID(rawValue: "a"),
            observations: obs,
            confirmedByFaceIndex: [0: ("p1", "Jesse")],
            suggestionsByFaceIndex: [1: ("p2", "Ann")]
        )
        XCTAssertEqual(p.rows.map(\.state), [
            .confirmed(personID: "p1", name: "Jesse"),
            .suggested(personID: "p2", name: "Ann"),
            .unnamed
        ])
    }

    func testConfirmedWinsOverSuggestedForTheSameFace() {
        let obs = [face(0)]
        let p = PhotoFacesPresentation(
            assetID: AssetID(rawValue: "a"),
            observations: obs,
            confirmedByFaceIndex: [0: ("p1", "Jesse")],
            suggestionsByFaceIndex: [0: ("p2", "Ann")]
        )
        XCTAssertEqual(p.rows.map(\.state), [
            .confirmed(personID: "p1", name: "Jesse")
        ])
    }
}
