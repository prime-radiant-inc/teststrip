import TeststripCore

/// One face tile in the face-group review surface: the face to look at (its
/// bounding box, for a zoomed crop) plus the asset it belongs to, so the tile
/// can reveal the whole photo on hover/click.
struct FaceReviewTile: Equatable, Identifiable {
    var faceID: FaceID
    var boundingBox: FaceBoundingBox

    var id: FaceID { faceID }
    var assetID: AssetID { faceID.assetID }
}

/// The review-first surface behind a face-group suggestion card. Every face in
/// the group is shown large and zoomed to the face so the user *looks* before
/// naming; a wrong face is removed (a real catalog gesture — sticky reject for
/// a matched person, dismiss for a new cluster), then the person is
/// confirmed/named over what remains. Because removal is a catalog gesture,
/// this is a pure projection of the *current* suggestion, recomputed after each
/// mutation — there is no divergent local include/exclude state.
struct FaceGroupReviewPresentation: Equatable, Identifiable {
    var suggestionID: String
    var kind: PeopleFaceSuggestion.Kind
    var tiles: [FaceReviewTile]

    var id: String { suggestionID }

    /// A matched-person group ("Is this <name>?") versus a new cluster
    /// ("Who is this?").
    var personName: String? {
        if case .matchExisting(_, let name) = kind { return name }
        return nil
    }

    var title: String {
        if let personName {
            return "Is this \(personName)?"
        }
        return "Who is this?"
    }

    /// The confirm button's label: the person's name for a match (one tap
    /// confirms), or "Name…" for a new cluster (opens the naming sheet).
    var confirmActionTitle: String {
        personName ?? "Name\u{2026}"
    }

    /// A one-tap confirm (matched person) versus a name-first confirm (new
    /// cluster), mirroring the card's `isOneTapConfirm`.
    var isOneTapConfirm: Bool {
        personName != nil
    }

    var remainingFaceCount: Int {
        tiles.count
    }

    var remainingPhotoCount: Int {
        Set(tiles.map(\.assetID)).count
    }

    /// Confirming an empty group would create/clear nothing, so it's disabled
    /// once every face has been removed.
    var isConfirmEnabled: Bool {
        !tiles.isEmpty
    }

    var summary: String {
        let faces = remainingFaceCount
        let photos = remainingPhotoCount
        return "\(faces) \(faces == 1 ? "face" : "faces") \u{00B7} \(photos) \(photos == 1 ? "photo" : "photos")"
    }
}
