import CoreGraphics

/// Image-relative point (0...1 on each axis) the zoomed loupe viewport is
/// centered on; (0.5, 0.5) is the image center. Nil zoom state means the
/// loupe shows the aspect-fitted frame.
public struct LoupeZoomFocus: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let center = LoupeZoomFocus(x: 0.5, y: 0.5)
}

/// Pure geometry for the loupe's 1:1 pixel zoom: how large the image draws,
/// how far it may pan, and how clicks and drags map onto the zoom focus.
struct LoupeZoomGeometry: Equatable {
    var imagePixelSize: CGSize
    var viewportSize: CGSize
    var displayScale: CGFloat

    /// Size in points at which one image pixel maps to one screen pixel.
    var actualSizeDisplaySize: CGSize {
        guard displayScale > 0 else { return .zero }
        return CGSize(
            width: imagePixelSize.width / displayScale,
            height: imagePixelSize.height / displayScale
        )
    }

    /// Size in points of the aspect-fitted image within the viewport.
    var fittedDisplaySize: CGSize {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
        let scale = min(
            viewportSize.width / imagePixelSize.width,
            viewportSize.height / imagePixelSize.height
        )
        guard scale > 0 else { return .zero }
        return CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
    }

    /// Offset in points to apply to the 1:1 image (positioned at the viewport
    /// center) so the focus point sits at the viewport center. The focus is
    /// clamped so the image edges never pull inside the viewport; axes where
    /// the image fits entirely stay centered.
    func offset(for focus: LoupeZoomFocus) -> CGSize {
        let clamped = clampedFocus(focus)
        return CGSize(
            width: (0.5 - clamped.x) * actualSizeDisplaySize.width,
            height: (0.5 - clamped.y) * actualSizeDisplaySize.height
        )
    }

    /// Maps a click on the aspect-fitted image to the focus to zoom into.
    /// Points outside the fitted image clamp to its nearest edge.
    func focus(atFittedViewportPoint point: CGPoint) -> LoupeZoomFocus {
        let fitted = fittedDisplaySize
        guard fitted.width > 0, fitted.height > 0 else { return .center }
        let origin = CGPoint(
            x: (viewportSize.width - fitted.width) / 2,
            y: (viewportSize.height - fitted.height) / 2
        )
        return LoupeZoomFocus(
            x: Self.unitClamped((point.x - origin.x) / fitted.width),
            y: Self.unitClamped((point.y - origin.y) / fitted.height)
        )
    }

    /// Moves the focus by a drag translation: the image tracks the cursor,
    /// so dragging the image left reveals content to the right.
    func focus(pannedBy translation: CGSize, from start: LoupeZoomFocus) -> LoupeZoomFocus {
        let display = actualSizeDisplaySize
        guard display.width > 0, display.height > 0 else { return clampedFocus(start) }
        return clampedFocus(LoupeZoomFocus(
            x: start.x - translation.width / display.width,
            y: start.y - translation.height / display.height
        ))
    }

    func clampedFocus(_ focus: LoupeZoomFocus) -> LoupeZoomFocus {
        LoupeZoomFocus(
            x: Self.clampedFocusComponent(
                focus.x,
                imageExtent: actualSizeDisplaySize.width,
                viewportExtent: viewportSize.width
            ),
            y: Self.clampedFocusComponent(
                focus.y,
                imageExtent: actualSizeDisplaySize.height,
                viewportExtent: viewportSize.height
            )
        )
    }

    private static func clampedFocusComponent(
        _ value: Double,
        imageExtent: CGFloat,
        viewportExtent: CGFloat
    ) -> Double {
        guard imageExtent > 0, imageExtent > viewportExtent else { return 0.5 }
        let halfViewportFraction = viewportExtent / imageExtent / 2
        return min(max(value, halfViewportFraction), 1 - halfViewportFraction)
    }

    private static func unitClamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
