import XCTest
import TeststripCore
@testable import TeststripApp

final class PersonKeyFacePresentationTests: XCTestCase {
    private func person(_ id: String, _ name: String, count: Int) -> CatalogPerson {
        CatalogPerson(id: id, name: name, assetCount: count)
    }

    func testNamedPersonPresentationCarriesKeyFaceWhenPresent() {
        let key = PersonKeyFace(assetID: AssetID(rawValue: "a2"), faceIndex: 0,
                                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                                captureQuality: 0.9)
        let presentation = PeoplePresentation(
            totalAssetCount: 0,
            namedPeople: [person("p1", "Ann", count: 3)],
            evaluationSummaries: [],
            keyFaces: ["p1": key]
        )
        XCTAssertEqual(presentation.namedPeople.first?.keyFace, key)
    }

    func testNamedPersonPresentationKeyFaceNilWhenAbsent() {
        let presentation = PeoplePresentation(
            totalAssetCount: 0,
            namedPeople: [person("p1", "Ann", count: 3)],
            evaluationSummaries: [],
            keyFaces: [:]
        )
        XCTAssertNil(presentation.namedPeople.first?.keyFace)
    }
}
