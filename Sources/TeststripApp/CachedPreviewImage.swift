import AppKit
import SwiftUI

enum PreviewImageDataLoader {
    static func loadData(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
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

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    var body: some View {
        content
            .task(id: previewURL) {
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
            return
        }
        guard loadedURL != previewURL else { return }
        image = nil
        loadedURL = previewURL
        guard let data = await PreviewImageDataLoader.loadData(from: previewURL), !Task.isCancelled else {
            return
        }
        image = NSImage(data: data)
    }
}
