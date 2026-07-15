import AppKit
import SwiftUI
import TeststripCore

/// Whether the loupe's 1:1 zoom is honestly sharp with what the preview
/// cache holds right now, still waiting on an original-resolution render,
/// or can never get one (original offline, render failed).
public enum LoupeZoomFullResolutionStatus: Equatable, Sendable {
    case satisfied
    case loading
    case unavailable
}

/// Decides when a 1:1 zoom needs an original-resolution render: whenever the
/// best cached preview level cannot cover the asset's pixels, or the asset's
/// pixel size is unknown so coverage cannot be proven.
enum LoupeZoomRenderPolicy {
    static func fullResolutionIsRequired(cachedLevel: PreviewLevel?, assetMaxPixelDimension: Int?) -> Bool {
        guard let cachedLevel else { return true }
        guard let cachedMaxPixelDimension = cachedLevel.maxPixelDimension else { return false }
        guard let assetMaxPixelDimension else { return true }
        return assetMaxPixelDimension > cachedMaxPixelDimension
    }
}

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

    /// The pixel size to zoom against: the asset's true dimensions when the
    /// catalog knows them (so an upscaled preview occupies the same footprint
    /// the original render will), otherwise the loaded preview's own pixels.
    static func imagePixelSize(
        technicalPixelWidth: Int?,
        technicalPixelHeight: Int?,
        fallback: CGSize
    ) -> CGSize {
        guard let technicalPixelWidth, let technicalPixelHeight,
              technicalPixelWidth > 0, technicalPixelHeight > 0 else {
            return fallback
        }
        return CGSize(width: technicalPixelWidth, height: technicalPixelHeight)
    }
}

/// What the zoom chip in the loupe says while pixel-peeking: always the zoom
/// factor, plus an honest note whenever the pixels on screen are not yet (or
/// can never be) original resolution.
struct LoupeZoomHUDPresentation: Equatable {
    var zoomLabelText: String
    var statusText: String?
    var isLoading: Bool

    init(fullResolutionStatus: LoupeZoomFullResolutionStatus) {
        zoomLabelText = "100%"
        switch fullResolutionStatus {
        case .satisfied:
            statusText = nil
            isLoading = false
        case .loading:
            statusText = "Loading full resolution…"
            isLoading = true
        case .unavailable:
            statusText = "Full resolution unavailable"
            isLoading = false
        }
    }

    var accessibilityValue: String {
        switch (statusText, isLoading) {
        case (nil, _):
            return zoomLabelText
        case (.some, true):
            return "\(zoomLabelText), loading full resolution"
        case (.some, false):
            return "\(zoomLabelText), full resolution unavailable"
        }
    }
}

/// The loupe's image stage: aspect-fitted by default, and a 1:1 pixel zoom
/// when the model carries a zoom focus. Click zooms into the clicked point,
/// click again returns to fit, dragging pans while zoomed. Zooming requests
/// an original-resolution render through the preview queue and shows the
/// upscaled cached preview honestly labelled until it lands.
struct LoupeZoomStageView: View {
    var model: AppModel
    var asset: Asset

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var loadedURL: URL?
    @State private var loadedGeneration: Int?
    @State private var dragStartFocus: LoupeZoomFocus?

    private var isZoomed: Bool {
        model.loupeZoomFocus != nil
    }

    private var displayedPreviewURL: URL? {
        isZoomed ? model.loupeZoomPreviewURL(for: asset.id) : model.loupePreviewURL(for: asset.id)
    }

    var body: some View {
        GeometryReader { proxy in
            stageContent(viewportSize: proxy.size)
        }
        .task(id: StagePreviewLoadKey(
            url: displayedPreviewURL,
            cacheGeneration: model.previewCacheGeneration(for: asset.id)
        )) {
            await loadPreview()
        }
        .task(id: FullResolutionRequestKey(assetID: asset.id.rawValue, isZoomed: isZoomed)) {
            guard isZoomed else { return }
            do {
                try model.requestLoupeFullResolutionPreview(assetID: asset.id)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isZoomed {
                zoomHUD
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private func stageContent(viewportSize: CGSize) -> some View {
        if let image {
            if let focus = model.loupeZoomFocus {
                zoomedImage(image, focus: focus, viewportSize: viewportSize)
            } else {
                fittedImage(image, viewportSize: viewportSize)
            }
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.35))
        }
    }

    private func fittedImage(_ image: NSImage, viewportSize: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: viewportSize.width, height: viewportSize.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let geometry = zoomGeometry(viewportSize: viewportSize, image: image)
                model.zoomLoupe(to: geometry.focus(atFittedViewportPoint: location))
            }
            .overlay {
                faceBoxOverlay(viewportSize: viewportSize, image: image)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Zoom to 100%")
    }

    // Gated to when the inspector (and so its People section) is actually
    // visible: boxes are a People-inspector companion, not default culling
    // chrome, so they stay out of the way of plain culling unless the
    // inspector is open. Only drawn over the aspect-fitted image — the 1:1
    // zoomed view doesn't track pan/zoom for boxes (out of scope for now).
    @ViewBuilder
    private func faceBoxOverlay(viewportSize: CGSize, image: NSImage) -> some View {
        if WorkspaceChromePolicy.showsInspector(model.selectedView), model.isInspectorVisible {
            let rows = model.photoFacesPresentation(for: asset.id).rows
            if !rows.isEmpty {
                FaceBoxOverlayView(
                    model: model,
                    rows: rows,
                    imagePixelSize: zoomGeometry(viewportSize: viewportSize, image: image).imagePixelSize,
                    containerSize: viewportSize
                )
            }
        }
    }

    private func zoomedImage(_ image: NSImage, focus: LoupeZoomFocus, viewportSize: CGSize) -> some View {
        let geometry = zoomGeometry(viewportSize: viewportSize, image: image)
        let displaySize = geometry.actualSizeDisplaySize
        let offset = geometry.offset(for: focus)
        return ZStack {
            Image(nsImage: image)
                .resizable()
                .frame(width: displaySize.width, height: displaySize.height)
                .position(
                    x: viewportSize.width / 2 + offset.width,
                    y: viewportSize.height / 2 + offset.height
                )
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            model.resetLoupeZoom()
        }
        .gesture(panGesture(geometry: geometry))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Return to fit")
    }

    private func panGesture(geometry: LoupeZoomGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStartFocus ?? model.loupeZoomFocus ?? .center
                dragStartFocus = start
                model.zoomLoupe(to: geometry.focus(pannedBy: value.translation, from: start))
            }
            .onEnded { _ in
                dragStartFocus = nil
            }
    }

    private var zoomHUD: some View {
        let presentation = LoupeZoomHUDPresentation(
            fullResolutionStatus: model.loupeZoomFullResolutionStatus(for: asset.id)
        )
        return HStack(spacing: 8) {
            if presentation.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            if let statusText = presentation.statusText {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(presentation.zoomLabelText)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loupe zoom")
        .accessibilityValue(presentation.accessibilityValue)
    }

    private func zoomGeometry(viewportSize: CGSize, image: NSImage) -> LoupeZoomGeometry {
        LoupeZoomGeometry(
            imagePixelSize: LoupeZoomGeometry.imagePixelSize(
                technicalPixelWidth: asset.technicalMetadata?.pixelWidth,
                technicalPixelHeight: asset.technicalMetadata?.pixelHeight,
                fallback: image.previewPixelSize
            ),
            viewportSize: viewportSize,
            displayScale: displayScale
        )
    }

    @MainActor
    private func loadPreview() async {
        guard let displayedPreviewURL else {
            image = nil
            loadedURL = nil
            loadedGeneration = model.previewCacheGeneration(for: asset.id)
            return
        }
        let generation = model.previewCacheGeneration(for: asset.id)
        guard loadedURL != displayedPreviewURL || loadedGeneration != generation else { return }
        if !PreviewImageTransition.shouldRetainCurrentImage(loadedURL: loadedURL, nextURL: displayedPreviewURL) {
            image = nil
        }
        loadedURL = displayedPreviewURL
        loadedGeneration = generation
        guard let loadedImage = await PreviewImageDataLoader.loadImage(from: displayedPreviewURL),
              !Task.isCancelled else {
            return
        }
        image = loadedImage
    }
}

private struct StagePreviewLoadKey: Equatable {
    var url: URL?
    var cacheGeneration: Int
}

private struct FullResolutionRequestKey: Equatable {
    var assetID: String
    var isZoomed: Bool
}

private extension NSImage {
    /// Pixel dimensions of the highest-resolution representation; NSImage's
    /// own size is in points and understates Retina-density previews.
    var previewPixelSize: CGSize {
        guard let representation = representations.max(by: { $0.pixelsWide < $1.pixelsWide }) else {
            return CGSize(width: size.width, height: size.height)
        }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}
