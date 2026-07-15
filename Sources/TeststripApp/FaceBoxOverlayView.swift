import CoreGraphics
import SwiftUI
import TeststripCore

/// Pure geometry for the loupe's face-box overlay (Task 8): maps a face's
/// normalized bounding box to the point rect within the aspect-fitted
/// (scaledToFit) image frame inside a container, so boxes track the actual
/// displayed (letterboxed) image rather than the raw container bounds.
enum FaceBoxOverlayGeometry {
    /// `boundingBox` is Vision's convention straight off
    /// `VNFaceObservation.boundingBox` (see `AppleVisionAnalyzer.analyze`):
    /// bottom-left origin, normalized to the image. SwiftUI draws top-left
    /// origin, so the y axis flips here — the same flip
    /// `FaceCropGeometry.pixelCropRect` applies when cropping avatar
    /// thumbnails out of the same observations.
    static func displayRect(
        boundingBox: FaceBoundingBox,
        imagePixelSize: CGSize,
        containerSize: CGSize
    ) -> CGRect? {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return nil
        }
        let scale = min(
            containerSize.width / imagePixelSize.width,
            containerSize.height / imagePixelSize.height
        )
        guard scale > 0 else { return nil }
        let fittedSize = CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )
        let topLeftY = 1.0 - boundingBox.y - boundingBox.height
        return CGRect(
            x: origin.x + boundingBox.x * fittedSize.width,
            y: origin.y + topLeftY * fittedSize.height,
            width: boundingBox.width * fittedSize.width,
            height: boundingBox.height * fittedSize.height
        )
    }
}

/// Face bounding boxes drawn over the loupe's aspect-fitted image (Task 8):
/// one outlined rect per detected face, labeled with its naming state
/// (`PhotoFaceState.displayLabel`, shared with the People inspector rows).
/// The box matching `model.focusedFaceID` (set by hovering a People row) is
/// highlighted, and hovering a box sets `model.focusedFaceID` in turn — the
/// same hover-only linking the People rows use (`PhotoFacesSectionView`).
/// Hovering a box also swaps its plain label for a pill; clicking the pill
/// opens the naming popover (`PersonAutocompleteField`) and pins the box
/// open via `model.editingFaceID`, independent of hover, so the popover
/// stays put while the pointer moves off the box and into it. The pill's ✕
/// removes a confirmed person or rejects a suggestion. Neither the pill nor
/// the popover claims the rest of the box, so a click on the box interior
/// still falls through to zoom to 100% at the clicked point
/// (`LoupeZoomStageView.fittedImage`).
struct FaceBoxOverlayView: View {
    var model: AppModel
    var rows: [PhotoFaceRow]
    var imagePixelSize: CGSize
    var containerSize: CGSize

    var body: some View {
        ForEach(rows) { row in
            if let rect = FaceBoxOverlayGeometry.displayRect(
                boundingBox: row.boundingBox,
                imagePixelSize: imagePixelSize,
                containerSize: containerSize
            ) {
                faceBox(rect: rect, row: row)
            }
        }
    }

    private func faceBox(rect: CGRect, row: PhotoFaceRow) -> some View {
        let isFocused = model.focusedFaceID == row.faceID
        let isEditing = model.editingFaceID == row.faceID
        return RoundedRectangle(cornerRadius: 4)
            .stroke(isFocused || isEditing ? Color.yellow : Color.white.opacity(0.8),
                    lineWidth: isFocused || isEditing ? 2.5 : 1.25)
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .overlay(alignment: .topLeading) {
                if isFocused || isEditing {
                    facePill(row: row, isEditing: isEditing).padding(3)
                } else {
                    faceLabel(row.state.displayLabel, isFocused: false).padding(3)
                }
            }
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    model.focusedFaceID = row.faceID
                } else if model.focusedFaceID == row.faceID {
                    model.focusedFaceID = nil
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.state.displayLabel)
    }

    private func faceLabel(_ text: String, isFocused: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                isFocused ? Color.yellow.opacity(0.85) : Color.black.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 3)
            )
            .fixedSize()
    }

    private func facePill(row: PhotoFaceRow, isEditing: Bool) -> some View {
        HStack(spacing: 2) {
            Button {
                model.editingFaceID = row.faceID
            } label: {
                faceLabel(pillTitle(row.state), isFocused: true)
            }
            .buttonStyle(.plain)
            .popover(isPresented: editingBinding(for: row.faceID), arrowEdge: .bottom) {
                PersonAutocompleteField(
                    candidates: model.rankedPersonCandidates(forFace: row.faceID),
                    onPick: { personID in
                        run { try model.nameFace(row.faceID, personID: personID) }
                        model.editingFaceID = nil
                    },
                    onCreate: { name in
                        run { try model.nameFace(row.faceID, newPersonName: name) }
                        model.editingFaceID = nil
                    }
                )
                .frame(width: 240)
                .padding(8)
            }
            if row.state.personID != nil {
                Button {
                    removePerson(row)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Remove this person")
            }
        }
    }

    private func editingBinding(for faceID: FaceID) -> Binding<Bool> {
        Binding(get: { model.editingFaceID == faceID },
                set: { if !$0, model.editingFaceID == faceID { model.editingFaceID = nil } })
    }

    private func pillTitle(_ state: PhotoFaceState) -> String {
        switch state {
        case .confirmed(_, let name): name
        case .suggested(_, let name): "guess: \(name)"
        case .unnamed: "Name\u{2026}"
        }
    }

    private func removePerson(_ row: PhotoFaceRow) {
        switch row.state {
        case .confirmed:
            run { try model.removeFacePerson(row.faceID) }
        case .suggested(let personID, _):
            run { try model.rejectFaceSuggestion(row.faceID, personID: personID) }
        case .unnamed:
            break
        }
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { model.errorMessage = error.localizedDescription }
    }
}
