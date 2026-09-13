import CoreGraphics
import SwiftUI
import TeststripCore

/// Pure geometry for the loupe's face-box overlay (Task 8): maps a face's
/// normalized bounding box to the point rect within the aspect-fitted
/// (scaledToFit) image frame inside a container, so boxes track the actual
/// displayed (letterboxed) image rather than the raw container bounds.
///
/// The box is normalized against the unrotated image the analyzer saw;
/// `rotation` (clockwise degrees) is the display-time override the image is
/// rotated by at load time (`PreviewImageDataLoader`), so the same rotation is
/// applied to the normalized box and to the fitted frame's dimensions.
enum FaceBoxOverlayGeometry {
    /// `boundingBox` is Vision's convention straight off
    /// `VNFaceObservation.boundingBox` (see `AppleVisionAnalyzer.analyze`):
    /// bottom-left origin, normalized to the image. SwiftUI draws top-left
    /// origin, so the y axis flips here — the same flip
    /// `FaceCropGeometry.pixelCropRect` applies when cropping avatar
    /// thumbnails out of the same observations.
    ///
    /// `imagePixelSize` is the *unrotated* image's pixel size (the space
    /// `boundingBox` is normalized against); quarter turns swap the displayed
    /// frame's width/height before fitting. `rotation` is normalized to
    /// 0/90/180/270.
    static func displayRect(
        boundingBox: FaceBoundingBox,
        imagePixelSize: CGSize,
        containerSize: CGSize,
        rotation: Int = 0
    ) -> CGRect? {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return nil
        }
        let normalizedRotation = normalizedRotation(rotation)
        let rotatedDimensions = RotationTransform.rotatedDimensions(
            width: Int(imagePixelSize.width.rounded()),
            height: Int(imagePixelSize.height.rounded()),
            rotation: normalizedRotation
        )
        let displayedPixelSize = CGSize(
            width: CGFloat(rotatedDimensions.width),
            height: CGFloat(rotatedDimensions.height)
        )
        let scale = min(
            containerSize.width / displayedPixelSize.width,
            containerSize.height / displayedPixelSize.height
        )
        guard scale > 0 else { return nil }
        let fittedSize = CGSize(width: displayedPixelSize.width * scale, height: displayedPixelSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )
        let box = rotatedNormalizedBox(
            topLeftX: boundingBox.x,
            topLeftY: 1.0 - boundingBox.y - boundingBox.height,
            width: boundingBox.width,
            height: boundingBox.height,
            rotation: normalizedRotation
        )
        return CGRect(
            x: origin.x + box.x * fittedSize.width,
            y: origin.y + box.y * fittedSize.height,
            width: box.width * fittedSize.width,
            height: box.height * fittedSize.height
        )
    }

    /// Reduces any degree count to one of the four quarter turns the display
    /// pipeline supports.
    static func normalizedRotation(_ rotation: Int) -> Int {
        let wrapped = ((rotation % 360) + 360) % 360
        switch wrapped {
        case 90, 180, 270:
            return wrapped
        default:
            return 0
        }
    }

    /// Rotates a normalized, top-left-origin box clockwise by `rotation`
    /// (0/90/180/270) within the unit square. A quarter turn swaps the box's
    /// width and height.
    static func rotatedNormalizedBox(
        topLeftX: Double,
        topLeftY: Double,
        width: Double,
        height: Double,
        rotation: Int
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        switch normalizedRotation(rotation) {
        case 90:
            // (x, y) -> (1 - y, x); corners (x, y) and (x+w, y+h).
            return (x: 1.0 - topLeftY - height, y: topLeftX, width: height, height: width)
        case 180:
            // (x, y) -> (1 - x, 1 - y).
            return (
                x: 1.0 - topLeftX - width,
                y: 1.0 - topLeftY - height,
                width: width,
                height: height
            )
        case 270:
            // (x, y) -> (y, 1 - x).
            return (x: topLeftY, y: 1.0 - topLeftX - width, width: height, height: width)
        default:
            return (x: topLeftX, y: topLeftY, width: width, height: height)
        }
    }
}

/// Face bounding boxes drawn over the loupe's aspect-fitted image (Task 8):
/// one outlined rect per detected face, labeled with its naming state
/// (`PhotoFaceState.displayLabel`, shared with the People inspector rows).
/// The box matching `model.focusedFaceID` (set by hovering a People row) is
/// highlighted, and hovering a box sets `model.focusedFaceID` in turn — the
/// same hover-only linking the People rows use (`PhotoFacesSectionView`).
/// Hovering a box also swaps its plain label for a pill; clicking the pill
/// opens the naming popover (`PersonAutocompleteField`), sets
/// `model.editingFaceSource = .loupe`, and gates presentation on both
/// fields (via `FaceNamingPopover.isPresented`) so only the clicked
/// surface presents the popover; the box highlight keys on `editingFaceID`
/// alone (independent of hover), so the popover stays visible as the
/// pointer moves between box and popover. The pill's ✕
/// removes a confirmed person or rejects a suggestion. Neither the pill nor
/// the popover claims the rest of the box, so a click on the box interior
/// still falls through to zoom to 100% at the clicked point
/// (`LoupeZoomStageView.fittedImage`).
struct FaceBoxOverlayView: View {
    var model: AppModel
    var rows: [PhotoFaceRow]
    var imagePixelSize: CGSize
    var containerSize: CGSize
    /// Clockwise display rotation override of the asset, so overlays track
    /// the rotated image.
    var rotation: Int = 0

    var body: some View {
        ForEach(rows) { row in
            if let rect = FaceBoxOverlayGeometry.displayRect(
                boundingBox: row.boundingBox,
                imagePixelSize: imagePixelSize,
                containerSize: containerSize,
                rotation: rotation
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
                model.editingFaceSource = .loupe
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
                        model.editingFaceSource = nil
                    },
                    onCreate: { name in
                        run { try model.nameFace(row.faceID, newPersonName: name) }
                        model.editingFaceID = nil
                        model.editingFaceSource = nil
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
        Binding(
            get: {
                FaceNamingPopover.isPresented(
                    editingFaceID: model.editingFaceID,
                    editingSource: model.editingFaceSource,
                    rowFaceID: faceID,
                    surface: .loupe
                )
            },
            set: { if !$0 { model.editingFaceID = nil; model.editingFaceSource = nil } }
        )
    }

    private func pillTitle(_ state: PhotoFaceState) -> String {
        switch state {
        case .confirmed(_, let name): name
        case .suggested(_, let name): "guess: \(name)"
        case .unnamed: "Name\u{2026}"
        }
    }

    private func removePerson(_ row: PhotoFaceRow) {
        run { try model.removePerson(forFaceRow: row) }
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { model.errorMessage = error.localizedDescription }
    }
}
