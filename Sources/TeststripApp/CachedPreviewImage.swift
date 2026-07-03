import AppKit
import SwiftUI

enum PreviewImageDataLoader {
    static func loadData(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

    static func loadImage(from url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return nil
            }
            return NSImage(data: data)
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

    @State private var image: NSImage?
    @State private var loadedURL: URL?
    @State private var loadedGeneration: Int?

    var body: some View {
        content
            .task(id: PreviewLoadRequest(url: previewURL, cacheGeneration: cacheGeneration)) {
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
        guard loadedURL != previewURL || loadedGeneration != cacheGeneration else { return }
        if !PreviewImageTransition.shouldRetainCurrentImage(loadedURL: loadedURL, nextURL: previewURL) {
            image = nil
        }
        loadedURL = previewURL
        loadedGeneration = cacheGeneration
        guard let loadedImage = await PreviewImageDataLoader.loadImage(from: previewURL), !Task.isCancelled else {
            return
        }
        image = loadedImage
    }
}

private struct PreviewLoadRequest: Equatable {
    var url: URL?
    var cacheGeneration: Int
}
