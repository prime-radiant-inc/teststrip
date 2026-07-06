import AppKit
import SwiftUI
import TeststripCore

enum FaceCropGeometry {
    static func pixelCropRect(
        boundingBox: FaceBoundingBox,
        imagePixelWidth: Int,
        imagePixelHeight: Int,
        padding: Double = 0.25
    ) -> CGRect {
        let imageRect = CGRect(x: 0, y: 0, width: imagePixelWidth, height: imagePixelHeight)
        guard boundingBox.width > 0, boundingBox.height > 0, imagePixelWidth > 0, imagePixelHeight > 0 else {
            return imageRect
        }
        let inset = padding * max(boundingBox.width, boundingBox.height)
        let minX = max(0.0, boundingBox.x - inset)
        let maxX = min(1.0, boundingBox.x + boundingBox.width + inset)
        let minVisionY = max(0.0, boundingBox.y - inset)
        let maxVisionY = min(1.0, boundingBox.y + boundingBox.height + inset)
        // Vision bounding boxes use a lower-left origin; image pixels use top-left.
        let topLeftMinY = 1.0 - maxVisionY
        let pixelRect = CGRect(
            x: minX * Double(imagePixelWidth),
            y: topLeftMinY * Double(imagePixelHeight),
            width: (maxX - minX) * Double(imagePixelWidth),
            height: (maxVisionY - minVisionY) * Double(imagePixelHeight)
        )
        return pixelRect.integral.intersection(imageRect)
    }
}

struct FaceCropAvatar: View {
    var previewURL: URL?
    var boundingBox: FaceBoundingBox
    var diameter: CGFloat = 52

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    var body: some View {
        content
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.12))
            }
            .task(id: previewURL) {
                await loadFaceCrop()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(.quaternary)
        }
    }

    @MainActor
    private func loadFaceCrop() async {
        guard let previewURL else {
            image = nil
            loadedURL = nil
            return
        }
        guard loadedURL != previewURL else { return }
        loadedURL = previewURL
        let boundingBox = boundingBox
        guard let cropped = await Self.loadCroppedFace(previewURL: previewURL, boundingBox: boundingBox),
              !Task.isCancelled else {
            return
        }
        image = cropped
    }

    private static func loadCroppedFace(previewURL: URL, boundingBox: FaceBoundingBox) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: previewURL, options: [.mappedIfSafe]),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            let rect = FaceCropGeometry.pixelCropRect(
                boundingBox: boundingBox,
                imagePixelWidth: cgImage.width,
                imagePixelHeight: cgImage.height
            )
            guard let cropped = cgImage.cropping(to: rect) else { return nil }
            return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        }.value
    }
}
