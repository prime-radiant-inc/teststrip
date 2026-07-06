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
