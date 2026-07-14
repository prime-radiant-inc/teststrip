import SwiftUI
import TeststripCore

/// The People inspector section (Task 7): one row per detected face in the
/// selected photo, with per-face naming controls. Every gesture here is
/// confirm-before-write — nothing lands in `person_faces`/`people` until the
/// user taps Confirm, names a person, or picks an existing one.
struct PhotoFacesSectionView: View {
    var model: AppModel
    var asset: Asset

    @State private var newPersonFaceID: FaceID?
    @State private var newPersonNameDraft = ""

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
        .sheet(isPresented: isShowingNewPersonSheet) {
            newPersonNameSheet
        }
    }

    private var isShowingNewPersonSheet: Binding<Bool> {
        Binding(
            get: { newPersonFaceID != nil },
            set: { isPresented in
                if !isPresented { newPersonFaceID = nil }
            }
        )
    }

    private func faceRow(_ row: PhotoFaceRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FaceCropAvatar(previewURL: previewURL, boundingBox: row.boundingBox)
            VStack(alignment: .leading, spacing: 5) {
                Text(stateLabel(row.state))
                    .font(.caption.weight(.semibold))
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

    private func stateLabel(_ state: PhotoFaceState) -> String {
        switch state {
        case .confirmed(_, let name):
            "\(name) \u{2713}"
        case .suggested(_, let name):
            "guess: \(name)"
        case .unnamed:
            "Unnamed"
        }
    }

    @ViewBuilder
    private func controls(for row: PhotoFaceRow) -> some View {
        switch row.state {
        case .unnamed:
            addNameMenu(for: row)
        case .suggested(let personID, let name):
            HStack(spacing: 6) {
                Button("Confirm") {
                    apply { try model.nameFace(row.faceID, personID: personID) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                Button("Not \(name)") {
                    apply { try model.rejectFaceSuggestion(row.faceID, personID: personID) }
                }
                .controlSize(.small)
                .help("Reject \(name) for this face")
            }
        case .confirmed:
            Button("Remove") {
                apply { try model.removeFacePerson(row.faceID) }
            }
            .controlSize(.small)
            .help("Clear this face's confirmed identity")
        }
    }

    private func addNameMenu(for row: PhotoFaceRow) -> some View {
        Menu("Add name") {
            ForEach(model.catalogPeople) { person in
                Button(person.name) {
                    apply { try model.nameFace(row.faceID, personID: person.id) }
                }
            }
            if !model.catalogPeople.isEmpty {
                Divider()
            }
            Button("New person\u{2026}") {
                newPersonNameDraft = ""
                newPersonFaceID = row.faceID
            }
        }
        .controlSize(.small)
        .fixedSize()
        .help("Name this face")
    }

    private var newPersonNameSheet: some View {
        SheetScaffold(
            title: "New Person",
            primaryLabel: "Create Person",
            isPrimaryEnabled: !newPersonNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            cancel: { newPersonFaceID = nil },
            primary: {
                guard let faceID = newPersonFaceID else { return }
                apply { try model.nameFace(faceID, newPersonName: newPersonNameDraft) }
                newPersonFaceID = nil
            }
        ) {
            TextField("Person name", text: $newPersonNameDraft)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func apply(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
