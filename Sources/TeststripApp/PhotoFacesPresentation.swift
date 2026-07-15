import TeststripCore

/// The naming state of one detected face, for the People section of the
/// single-photo inspector.
enum PhotoFaceState: Equatable {
    case confirmed(personID: String, name: String)
    case suggested(personID: String, name: String)
    case unnamed

    /// The label shown for this face's naming state — shared by the People
    /// inspector rows (`PhotoFacesSectionView`) and the loupe's face-box
    /// overlay (Task 8) so they always agree.
    var displayLabel: String {
        switch self {
        case .confirmed(_, let name):
            "\(name) \u{2713}"
        case .suggested(_, let name):
            "guess: \(name)"
        case .unnamed:
            "Unnamed"
        }
    }

    /// The assigned person, for confirmed and suggested faces alike — used to
    /// route removal (`AppModel.removeFacePerson`/`rejectFaceSuggestion`) to
    /// the right origin.
    var personID: String? {
        switch self {
        case .confirmed(let personID, _), .suggested(let personID, _): personID
        case .unnamed: nil
        }
    }
}

/// One row in the People inspector section: a detected face plus whatever
/// naming state it currently has (confirmed identity, a suggested identity,
/// or none).
struct PhotoFaceRow: Equatable, Identifiable {
    var faceID: FaceID
    var boundingBox: FaceBoundingBox
    var state: PhotoFaceState

    var id: FaceID { faceID }
}

/// Maps a photo's detected faces to editable People rows: confirmed
/// (`person_faces`) wins over suggested (`PeopleFaceSuggestion`) for the
/// same face, which otherwise falls back to unnamed.
struct PhotoFacesPresentation: Equatable {
    var rows: [PhotoFaceRow]

    init(
        assetID: AssetID,
        observations: [CatalogFaceObservation],
        confirmedByFaceIndex: [Int: (personID: String, name: String)],
        suggestionsByFaceIndex: [Int: (personID: String, name: String)]
    ) {
        rows = observations
            .sorted { $0.faceIndex < $1.faceIndex }
            .map { observation in
                let state: PhotoFaceState
                if let confirmed = confirmedByFaceIndex[observation.faceIndex] {
                    state = .confirmed(personID: confirmed.personID, name: confirmed.name)
                } else if let suggested = suggestionsByFaceIndex[observation.faceIndex] {
                    state = .suggested(personID: suggested.personID, name: suggested.name)
                } else {
                    state = .unnamed
                }
                return PhotoFaceRow(
                    faceID: FaceID(assetID: assetID, faceIndex: observation.faceIndex),
                    boundingBox: observation.boundingBox,
                    state: state
                )
            }
    }
}
