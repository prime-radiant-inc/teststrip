import SwiftUI
import TeststripCore

/// The People inspector section (Task 7): one row per detected face in the
/// selected photo, with per-face naming controls. Every gesture here is
/// confirm-before-write — nothing lands in `person_faces`/`people` until the
/// user taps Confirm, names a person, or picks an existing one.
struct PhotoFacesSectionView: View {
    var model: AppModel
    var asset: Asset

    private var presentation: PhotoFacesPresentation {
        model.photoFacesPresentation(for: asset.id)
    }

    private var previewURL: URL? {
        model.previewURL(for: asset.id, levels: [.large, .medium, .grid, .micro])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if presentation.rows.isEmpty {
                Text("No faces detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presentation.rows) { row in
                    faceRow(row)
                }
            }
        }
    }

    private func faceRow(_ row: PhotoFaceRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FaceCropAvatar(previewURL: previewURL, boundingBox: row.boundingBox)
            VStack(alignment: .leading, spacing: 5) {
                faceLabel(for: row)
                controls(for: row)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            model.focusedFaceID == row.faceID ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovering in
            if isHovering {
                model.focusedFaceID = row.faceID
            } else if model.focusedFaceID == row.faceID {
                model.focusedFaceID = nil
            }
        }
    }

    /// The naming-state label, prefixed with a ✨ marker for a still-provisional
    /// AI match (Task 14) — the confirmed and unnamed states are unmarked.
    @ViewBuilder
    private func faceLabel(for row: PhotoFaceRow) -> some View {
        HStack(spacing: 4) {
            if case .suggested = row.state {
                Image(systemName: DesignGlyph.ai.symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(row.state.displayLabel)
                .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder
    private func controls(for row: PhotoFaceRow) -> some View {
        switch row.state {
        case .unnamed:
            addNameButton(for: row)
        case .suggested:
            HStack(spacing: 6) {
                Button("Confirm") {
                    apply { try model.confirmAIFace(assetID: row.faceID.assetID, faceIndex: row.faceID.faceIndex) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button("Remove") {
                    apply { try model.removePerson(forFaceRow: row) }
                }
                .controlSize(.small)
                .help("Remove this suggested match")
            }
        case .confirmed:
            Button("Remove") {
                apply { try model.removePerson(forFaceRow: row) }
            }
            .controlSize(.small)
            .help("Clear this face's confirmed identity")
        }
    }

    /// Ranked-picker popover for naming an unnamed face (Task 6's pill
    /// pattern): `model.editingFaceID` pins the popover open per-face, shared
    /// with the loupe's face-box overlay so the two surfaces never disagree
    /// about which face is mid-edit.
    private func addNameButton(for row: PhotoFaceRow) -> some View {
        Button("Add name") {
            model.editingFaceID = row.faceID
        }
        .controlSize(.small)
        .fixedSize()
        .help("Name this face")
        .popover(isPresented: editingBinding(for: row.faceID), arrowEdge: .bottom) {
            PersonAutocompleteField(
                candidates: model.rankedPersonCandidates(forFace: row.faceID),
                onPick: { personID in
                    apply { try model.nameFace(row.faceID, personID: personID) }
                    model.editingFaceID = nil
                },
                onCreate: { name in
                    apply { try model.nameFace(row.faceID, newPersonName: name) }
                    model.editingFaceID = nil
                }
            )
            .frame(width: 240)
            .padding(8)
        }
    }

    private func editingBinding(for faceID: FaceID) -> Binding<Bool> {
        Binding(
            get: { model.editingFaceID == faceID },
            set: { if !$0, model.editingFaceID == faceID { model.editingFaceID = nil } }
        )
    }

    private func apply(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
