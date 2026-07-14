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
/// same hover-only linking the People rows use (`PhotoFacesSectionView`),
/// not click-to-pin: a click on the loupe image already zooms to 100% at the
/// clicked point (`LoupeZoomStageView.fittedImage`), and overloading a click
/// on a face box to instead pin its selection would shadow that existing,
/// discoverable gesture. If Jesse wants persistent face selection later,
/// that's a deliberate follow-up (e.g. a modifier-click), not a silent
/// addition here.
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
        return RoundedRectangle(cornerRadius: 4)
            .stroke(isFocused ? Color.yellow : Color.white.opacity(0.8), lineWidth: isFocused ? 2.5 : 1.25)
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .overlay(alignment: .topLeading) {
                faceLabel(row.state.displayLabel, isFocused: isFocused)
                    .padding(3)
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
}
