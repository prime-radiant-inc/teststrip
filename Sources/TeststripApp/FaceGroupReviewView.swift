import AppKit
import SwiftUI
import TeststripCore

/// The review-first surface behind a face-group suggestion card: every face in
/// the group is shown large and zoomed to the face, so the user *looks* before
/// naming. Removing a face is a real catalog gesture (sticky reject / dismiss),
/// so the view is a pure projection of the current suggestion — it re-reads
/// `model.peopleFaceSuggestions` by id and rebuilds after each mutation.
struct FaceGroupReviewView: View {
    var model: AppModel
    var suggestionID: String
    /// One-tap confirm for a matched person.
    var confirm: (PeopleFaceSuggestion) -> Void
    /// Name-first confirm for a new cluster (opens the naming sheet).
    var name: (PeopleFaceSuggestion) -> Void
    var close: () -> Void

    private var suggestion: PeopleFaceSuggestion? {
        model.peopleFaceSuggestions.first { $0.id == suggestionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let suggestion {
                let review = model.faceGroupReview(for: suggestion)
                header(review)
                Divider()
                tileGrid(suggestion: suggestion, review: review)
                Divider()
                confirmBar(suggestion: suggestion, review: review)
            } else {
                completionState
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private func header(_ review: FaceGroupReviewPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(review.title)
                    .font(.title3.weight(.semibold))
                Text(review.summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Done", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private func tileGrid(suggestion: PeopleFaceSuggestion, review: FaceGroupReviewPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Click a face to see the whole photo. Remove anyone who doesn't belong, then confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(review.tiles) { tile in
                        FaceReviewTileView(
                            previewURL: model.previewURL(for: tile.assetID, levels: [.large, .medium, .grid, .micro]),
                            boundingBox: tile.boundingBox,
                            remove: { remove(suggestion, tile) }
                        )
                    }
                }
            }
            .padding(18)
        }
    }

    private func confirmBar(suggestion: PeopleFaceSuggestion, review: FaceGroupReviewPresentation) -> some View {
        HStack(spacing: 12) {
            Text(review.isOneTapConfirm
                ? "Confirm links these \(review.remainingFaceCount == 1 ? "face" : "faces") to \(review.personName ?? "this person")."
                : "Name the person to create a new group from these faces.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button {
                if review.isOneTapConfirm {
                    confirm(suggestion)
                } else {
                    name(suggestion)
                }
            } label: {
                Text(review.confirmActionTitle)
                    .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!review.isConfirmEnabled)
            .help(review.isOneTapConfirm ? "Confirm this group as \(review.confirmActionTitle)" : "Name this new group")
        }
        .padding(18)
    }

    private var completionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing left to review in this group.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func remove(_ suggestion: PeopleFaceSuggestion, _ tile: FaceReviewTile) {
        do {
            try model.removeFaceFromReviewGroup(suggestion, faceID: tile.faceID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// One face tile in the review surface: a large crop zoomed to the face that
/// swaps to the whole photo on hover/click, with a control to remove the face
/// from the group. Reuses `FaceCropLoader` (shared with `FaceCropAvatar`).
struct FaceReviewTileView: View {
    var previewURL: URL?
    var boundingBox: FaceBoundingBox
    var remove: () -> Void

    @State private var faceCrop: NSImage?
    @State private var loadedKey: FaceCropAvatar.CropKey?
    @State private var isRevealingPhoto = false

    private var cropKey: FaceCropAvatar.CropKey {
        FaceCropAvatar.CropKey(url: previewURL, box: boundingBox)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            faceOrPhoto
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isRevealingPhoto ? Color.accentColor : Color.white.opacity(0.08),
                                      lineWidth: isRevealingPhoto ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { isRevealingPhoto.toggle() }
                .onHover { hovering in isRevealingPhoto = hovering }

            removeButton
                .padding(6)
        }
        .task(id: cropKey) { await loadFaceCrop() }
        .help("Click to see the whole photo; use the ✕ to remove this face from the group")
    }

    @ViewBuilder
    private var faceOrPhoto: some View {
        if isRevealingPhoto {
            CachedPreviewImage(previewURL: previewURL, scaling: .fit)
        } else if let faceCrop {
            Image(nsImage: faceCrop)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
        }
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Remove this face from the group")
        .accessibilityLabel("Remove face")
    }

    @MainActor
    private func loadFaceCrop() async {
        guard let previewURL else {
            faceCrop = nil
            loadedKey = nil
            return
        }
        let key = cropKey
        guard loadedKey != key else { return }
        loadedKey = key
        guard let cropped = await FaceCropLoader.loadCroppedFace(previewURL: previewURL, boundingBox: boundingBox),
              !Task.isCancelled else {
            return
        }
        faceCrop = cropped
    }
}
