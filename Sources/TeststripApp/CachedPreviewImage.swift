import AppKit
import CoreImage
import SwiftUI
import TeststripCore

enum PreviewImageDataLoader {
    static func loadData(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

    static func loadImage(from url: URL, maxPixelDimension: Int?, rotation: Int = 0) async -> NSImage? {
        guard let maxPixelDimension else {
            return await loadImage(from: url, rotation: rotation)
        }
        return await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
                kCGImageSourceShouldCache: false
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            if rotation == 0 {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            let ciImage = CIImage(cgImage: cgImage)
            let oriented = ciImage.oriented(forExifOrientation: Int32(RotationTransform.exifOrientation(forRotation: rotation).rawValue))
            let context = CIContext()
            guard let rotatedCGImage = context.createCGImage(oriented, from: oriented.extent) else {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            let dims = RotationTransform.rotatedDimensions(
                width: cgImage.width, height: cgImage.height, rotation: rotation
            )
            return NSImage(cgImage: rotatedCGImage, size: NSSize(width: dims.width, height: dims.height))
        }.value
    }

    static func loadImage(from url: URL, rotation: Int = 0) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return nil
            }
            guard rotation != 0 else {
                return NSImage(data: data)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return NSImage(data: data)
            }
            let ciImage = CIImage(cgImage: cgImage)
            let oriented = ciImage.oriented(forExifOrientation: Int32(RotationTransform.exifOrientation(forRotation: rotation).rawValue))
            let context = CIContext()
            guard let rotatedCGImage = context.createCGImage(oriented, from: oriented.extent) else {
                return NSImage(data: data)
            }
            let dims = RotationTransform.rotatedDimensions(
                width: cgImage.width, height: cgImage.height, rotation: rotation
            )
            return NSImage(cgImage: rotatedCGImage, size: NSSize(width: dims.width, height: dims.height))
        }.value
    }
}

enum PreviewImageTransition {
    static func shouldRetainCurrentImage(loadedURL: URL?, nextURL: URL?) -> Bool {
        guard let loadedURL, let nextURL else { return false }
        let loadedAssetDirectory = loadedURL.deletingLastPathComponent().standardizedFileURL
        let nextAssetDirectory = nextURL.deletingLastPathComponent().standardizedFileURL
        return loadedAssetDirectory == nextAssetDirectory
    }
}

struct CachedPreviewImage: View {
    enum Scaling {
        case fill
        case fit
    }

    var previewURL: URL?
    var scaling: Scaling
    var cornerRadius: CGFloat = 5
    var cacheGeneration: Int = 0
    var rotation: Int = 0

    @State private var image: NSImage?
    @State private var loadedURL: URL?
    @State private var loadedGeneration: Int?
    @State private var loadedRotation: Int?

    var body: some View {
        content
            .task(id: PreviewLoadRequest(url: previewURL, cacheGeneration: cacheGeneration, rotation: rotation)) {
                await loadPreview()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            switch scaling {
            case .fill:
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            case .fit:
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.35))
        }
    }

    @MainActor
    private func loadPreview() async {
        guard let previewURL else {
            image = nil
            loadedURL = nil
            loadedGeneration = cacheGeneration
            return
        }
        guard loadedURL != previewURL || loadedGeneration != cacheGeneration || loadedRotation != rotation else { return }
        if !PreviewImageTransition.shouldRetainCurrentImage(loadedURL: loadedURL, nextURL: previewURL) {
            image = nil
        }
        loadedURL = previewURL
        loadedGeneration = cacheGeneration
        loadedRotation = rotation
        guard let loadedImage = await PreviewImageDataLoader.loadImage(from: previewURL, rotation: rotation), !Task.isCancelled else {
            return
        }
        image = loadedImage
    }
}

private struct PreviewLoadRequest: Equatable {
    var url: URL?
    var cacheGeneration: Int
    var rotation: Int
}
