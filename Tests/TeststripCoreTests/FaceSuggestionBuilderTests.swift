import XCTest
@testable import TeststripCore

final class FaceSuggestionBuilderTests: XCTestCase {
    private func faceID(_ asset: String, _ index: Int = 0) -> FaceID {
        FaceID(assetID: AssetID(rawValue: asset), faceIndex: index)
    }

    func testClustersNearbyFacesAndDropsSingletons() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("a"), vector: [1, 0, 0]),
                FaceEmbedding(faceID: faceID("b"), vector: [0.99, 0.14, 0]),
                FaceEmbedding(faceID: faceID("c"), vector: [0, 1, 0])
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.matches, [])
        XCTAssertEqual(suggestions.clusters, [
            FaceClusterSuggestion(faceIDs: [faceID("a"), faceID("b")])
        ])
    }

    func testMatchesFacesToConfirmedPersonCentroidBeforeClustering() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("new-a"), vector: [0.99, 0.1, 0]),
                FaceEmbedding(faceID: faceID("new-b"), vector: [1, 0.05, 0]),
                FaceEmbedding(faceID: faceID("other"), vector: [0, 0, 1])
            ],
            confirmedFacesByPerson: ["person-maya": [[1, 0, 0], [0.98, 0.2, 0]]]
        )

        XCTAssertEqual(suggestions.matches, [
            FaceMatchSuggestion(personID: "person-maya", faceIDs: [faceID("new-a"), faceID("new-b")])
        ])
        XCTAssertEqual(suggestions.clusters, [])
    }

    func testIgnoresEmptyAndMismatchedDimensionEmbeddings() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("empty"), vector: []),
                FaceEmbedding(faceID: faceID("short"), vector: [1]),
                FaceEmbedding(faceID: faceID("a"), vector: [1, 0, 0]),
                FaceEmbedding(faceID: faceID("b"), vector: [0.99, 0.14, 0])
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.matches, [])
        XCTAssertEqual(suggestions.clusters, [
            FaceClusterSuggestion(faceIDs: [faceID("a"), faceID("b")])
        ])
    }

    // Two faces of the same person, embedded with VNGenerateImageFeaturePrint,
    // land ~0.7-0.9 apart in L2-normalized space (measured on the astronaut
    // corpus). The default cluster threshold must be calibrated to that scale,
    // otherwise real repeated individuals never group and no suggestions appear.
    func testGroupsSamePersonAtImageFeaturePrintScale() {
        // Unit vectors whose mutual distance is ~0.75, matching same-person
        // feature-print pairs; a distinct person sits ~1.4 away.
        let personA1: [Double] = [1, 0, 0]
        let personA2: [Double] = [0.719, 0.695, 0]
        let personB: [Double] = [0, 0, 1]

        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("a1"), vector: personA1),
                FaceEmbedding(faceID: faceID("a2"), vector: personA2),
                FaceEmbedding(faceID: faceID("b"), vector: personB)
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.clusters, [
            FaceClusterSuggestion(faceIDs: [faceID("a1"), faceID("a2")])
        ])
    }

    func testLargerClustersSortFirst() {
        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: [
                FaceEmbedding(faceID: faceID("solo-a"), vector: [1, 0, 0]),
                FaceEmbedding(faceID: faceID("solo-b"), vector: [0.99, 0.14, 0]),
                FaceEmbedding(faceID: faceID("trio-a"), vector: [0, 1, 0]),
                FaceEmbedding(faceID: faceID("trio-b"), vector: [0, 0.99, 0.14]),
                FaceEmbedding(faceID: faceID("trio-c"), vector: [0.14, 0.99, 0])
            ],
            confirmedFacesByPerson: [:]
        )

        XCTAssertEqual(suggestions.clusters.map { $0.faceIDs.count }, [3, 2])
    }
}
